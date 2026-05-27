"""
Pilot step 1: img2img stylization via ComfyUI HTTP API.

Reads ONE raw render (S_00.png by default), submits to local ComfyUI
with SDXL + IP-Adapter (anchored on painted-bible character ref) +
ControlNet lineart, writes the painted output to
tools/pilot/output/painted/.

Smoke-test mode runs ONE image first. After it works end-to-end, set
SMOKE_TEST = False to batch all 8 directions.

# Prerequisites

  1. ComfyUI running at http://127.0.0.1:8188 — start with:
       cd <ComfyUI dir>
       python main.py
     (or use the run_nvidia_gpu.bat / run_cpu.bat shortcut)

  2. Models installed in the right ComfyUI folders:
       checkpoints/    sd_xl_base_1.0.safetensors
                       (https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0)
       controlnet/     controlnet-lora-sdxl-canny.safetensors
                       (https://huggingface.co/stabilityai/control-lora)
                       OR diffusers_xl_canny_mid.safetensors (similar)
       ipadapter/      ip-adapter-plus_sdxl_vit-h.safetensors
                       (https://huggingface.co/h94/IP-Adapter)
       clip_vision/    CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors
                       (https://huggingface.co/laion/CLIP-ViT-H-14-laion2B-s32B-b79K)

  3. Custom nodes installed (via ComfyUI Manager or git clone into
     custom_nodes/):
       ComfyUI_IPAdapter_plus  https://github.com/cubiq/ComfyUI_IPAdapter_plus
       (optional but recommended) comfyui_controlnet_aux  for preprocessors

# How it runs

  python tools/pilot/02_stylize.py

  - Verifies ComfyUI is reachable
  - Lists checkpoints / controlnets / ipadapters available so you can
    edit the CKPT_NAME / CONTROLNET_NAME constants below to match what
    you actually have installed
  - Uploads the raw render + the style reference to ComfyUI's input/
  - Submits the workflow, polls for completion, downloads the result
"""

import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

# ── Config ──────────────────────────────────────────────────────────────────

# ComfyUI Desktop installs default to port 8000; the source-repo install
# defaults to 8188. Override via env var if yours differs:
#   $env:COMFYUI_URL = "http://127.0.0.1:8188"; python tools/pilot/02_stylize.py
COMFYUI_URL = os.environ.get("COMFYUI_URL", "http://127.0.0.1:8000")
PROJECT_ROOT = Path(__file__).parent.parent.parent
RAW_DIR = PROJECT_ROOT / "tools" / "pilot" / "output" / "raw"
PAINTED_DIR = PROJECT_ROOT / "tools" / "pilot" / "output" / "painted"

# Style anchor for IP-Adapter.
#
# Originally pointed at the bible's painted soldier ref (374b6a95.png) —
# that worked for STYLE (painted look transferred well) but produced
# identity drift across the 8-direction batch because the bible ref is a
# *different* character than what we're trying to lock. Each frame
# inherited "soldier-ish" style differently, yielding multiple distinct
# characters rather than one consistent one.
#
# Switched to a CANONICAL CHARACTER reference — one specific painted
# frame of THIS character that all 8 directions should converge on.
# This is the D2 production pattern: paint ONE definitive character
# image, anchor every facing on it. Currently using a pick from the
# previous batch (E_00 yellow military soldier with goggles + hammer);
# in production this would be a hand-picked or hand-painted master.
STYLE_REF_PATH = PROJECT_ROOT / "tools" / "pilot" / "canonical_character.png"

# Smoke test: process one image first to validate the pipeline.
SMOKE_TEST = False
SMOKE_TEST_INPUT = "S_00.png"

# Minimal mode: skip ControlNet + IP-Adapter, run pure img2img with
# prompt-driven style only. Set True for the first run on a fresh ComfyUI
# install — only requires the SDXL checkpoint (~6.5GB), no extras. Style
# fidelity to the painted bible will be lower (no anchor reference); set
# False after downloading the full model set + IPAdapter custom node.
MINIMAL_MODE = False

# Model names. EDIT THESE to match your local ComfyUI installation.
# After the first run, this script prints what's actually installed so
# you can pick the right names without guessing.
CKPT_NAME = "sd_xl_base_1.0.safetensors"
CONTROLNET_NAME = "controlnet-canny-sdxl-1.0.safetensors"

# Prompts: positive describes what we want, negative pushes away from
# the failure modes we've seen in the bible iterations.
POSITIVE_PROMPT = (
    "Diablo 2 inventory sprite, painted brush style, cyberpunk soldier "
    "with hammer, hand-painted illustration, 1996 ARPG aesthetic, "
    "gritty body-horror facility, baked lighting, dimetric isometric view, "
    "complementary-color lighting, dark industrial atmosphere"
)
NEGATIVE_PROMPT = (
    "3D render, photoreal, modern game graphics, clean polish, smooth "
    "shading, modern indie style, white background, isolated on platform, "
    "League key art, anime, cell shading"
)

# img2img denoising — how much the model can change the input.
# 0.0 = no change, 1.0 = full re-paint. Higher = more aggressive re-style
# but less faithful to the input pose. Without ControlNet to enforce
# silhouette, ~0.65 is the upper limit before the pose drifts.
#
# Iteration log on the fresh install:
#   0.6  -> chromatic noise (input too small, before 1024 upscale fix)
#   0.4  -> pose preserved but no style shift (looked like 3D render)
#   0.65 -> trying now
DENOISE_STRENGTH = 0.65

# SDXL was trained on 1024x1024 and produces garbage on smaller inputs.
# Raw renders are 256x256, so we upscale them to 1024 before VAE encode.
# The painted output saves at 1024 — downscale to 256 happens at the
# Godot import step (high-res masters, scaled at runtime).
SDXL_RESOLUTION = 1024

# ControlNet strength — how strongly the lineart guides the output.
# Dropped from 0.8 → 0.5 so the model has room to RESHAPE the character
# toward the canonical (armored soldier). At 0.8 the 3D mannequin's
# silhouette was winning over the canonical — output kept the X Bot
# rounded-chest mannequin shape with a paint job, ignoring the
# canonical's armor design.
CONTROLNET_STRENGTH = 0.5

# IP-Adapter strength — how heavily the style ref biases the result.
# Max it out — we want the canonical to dominate.
IPADAPTER_WEIGHT = 1.0

# Seed for reproducibility while iterating; bump to randomize.
SEED = 42

# ── Helpers ─────────────────────────────────────────────────────────────────


def check_comfyui_reachable() -> bool:
    """Verify ComfyUI is running. Return True on success."""
    try:
        with urllib.request.urlopen(f"{COMFYUI_URL}/system_stats", timeout=3) as r:
            stats = json.loads(r.read())
        print(f"[stylize] ComfyUI reachable at {COMFYUI_URL}")
        if "system" in stats:
            sys_info = stats["system"]
            print(f"[stylize]   OS: {sys_info.get('os')}, Python: {sys_info.get('python_version', '?').split()[0]}")
        if "devices" in stats and stats["devices"]:
            d = stats["devices"][0]
            print(f"[stylize]   Device: {d.get('name')} ({d.get('type')})")
        return True
    except urllib.error.URLError as e:
        print(f"[stylize] ERROR: ComfyUI not reachable at {COMFYUI_URL}")
        print(f"[stylize]   Detail: {e}")
        print(f"[stylize]   Start ComfyUI first, then re-run this script.")
        return False


def list_available_models() -> dict:
    """Query ComfyUI for what's actually installed and print a digest.
    Returns the raw dict so the caller can sanity-check model names."""
    with urllib.request.urlopen(f"{COMFYUI_URL}/object_info", timeout=10) as r:
        info = json.loads(r.read())

    ckpts = info.get("CheckpointLoaderSimple", {}).get("input", {}).get("required", {}).get("ckpt_name", [[]])[0]
    controlnets = info.get("ControlNetLoader", {}).get("input", {}).get("required", {}).get("control_net_name", [[]])[0]
    # IP-Adapter nodes are from a custom pack. Try both common node names.
    ipadapter_node = info.get("IPAdapterUnifiedLoader") or info.get("IPAdapter") or {}
    has_ipadapter = bool(ipadapter_node)

    print(f"[stylize] Checkpoints installed ({len(ckpts)}):")
    for c in ckpts[:5]:
        print(f"[stylize]   - {c}")
    if len(ckpts) > 5:
        print(f"[stylize]   ... and {len(ckpts) - 5} more")
    print(f"[stylize] ControlNets installed ({len(controlnets)}):")
    for c in controlnets[:5]:
        print(f"[stylize]   - {c}")
    if len(controlnets) > 5:
        print(f"[stylize]   ... and {len(controlnets) - 5} more")
    print(f"[stylize] IP-Adapter custom nodes: {'YES' if has_ipadapter else 'NOT INSTALLED'}")
    if not has_ipadapter:
        print(f"[stylize]   Install via ComfyUI Manager or:")
        print(f"[stylize]   git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus")
        print(f"[stylize]   into ComfyUI/custom_nodes/")

    # Cross-check our configured names exist
    missing = []
    if CKPT_NAME not in ckpts:
        missing.append(f"Checkpoint {CKPT_NAME!r} (top-of-script CKPT_NAME)")
    if CONTROLNET_NAME not in controlnets:
        missing.append(f"ControlNet {CONTROLNET_NAME!r} (top-of-script CONTROLNET_NAME)")
    if missing:
        print(f"[stylize] WARNING: configured models not found:")
        for m in missing:
            print(f"[stylize]   - {m}")
        print(f"[stylize] Edit the constants at top of 02_stylize.py to match what you have.")

    return {"checkpoints": ckpts, "controlnets": controlnets, "has_ipadapter": has_ipadapter}


def upload_image(path: Path) -> str:
    """Upload an image to ComfyUI's input/ folder. Returns the filename
    ComfyUI uses to reference it."""
    if not path.exists():
        raise FileNotFoundError(f"Cannot upload missing image: {path}")
    with open(path, "rb") as f:
        body = f.read()
    boundary = uuid.uuid4().hex
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    # Multipart form: image file + overwrite flag + type=input
    parts = []
    parts.append(f"--{boundary}".encode())
    parts.append(f'Content-Disposition: form-data; name="image"; filename="{path.name}"'.encode())
    parts.append(b"Content-Type: image/png")
    parts.append(b"")
    parts.append(body)
    parts.append(f"--{boundary}".encode())
    parts.append(b'Content-Disposition: form-data; name="overwrite"')
    parts.append(b"")
    parts.append(b"true")
    parts.append(f"--{boundary}--".encode())
    data = b"\r\n".join(parts)
    req = urllib.request.Request(f"{COMFYUI_URL}/upload/image", data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        result = json.loads(r.read())
    return result.get("name", path.name)


def build_minimal_workflow(raw_image_name: str, output_prefix: str, seed: int) -> dict:
    """Minimal img2img workflow — SDXL checkpoint only, no ControlNet, no
    IP-Adapter. Style is purely prompt-driven. Use this to validate the
    pipeline works end-to-end before installing the full model set.

        LoadImage(raw) ─► ImageScale(1024) ─► VAEEncode ─► (latent) ─┐
                                                                      │
        Checkpoint ─┬─► (model) ────────────────────────────────────► KSampler
                    ├─► (clip) ─► CLIPTextEnc(+) ──►                   │
                    │            CLIPTextEnc(-) ──►                   │
                    └─► (vae) ────────────────────────────────────────► VAEDecode ─► SaveImage
    """
    return {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": CKPT_NAME},
        },
        "2": {
            "class_type": "LoadImage",
            "inputs": {"image": raw_image_name},
        },
        # Upscale 256x256 input to 1024x1024 (SDXL's training resolution).
        # Without this, SDXL outputs chromatic noise — it never saw small
        # images during training.
        "2a": {
            "class_type": "ImageScale",
            "inputs": {
                "image": ["2", 0],
                "width": SDXL_RESOLUTION,
                "height": SDXL_RESOLUTION,
                "upscale_method": "lanczos",
                "crop": "disabled",
            },
        },
        "3": {
            "class_type": "VAEEncode",
            "inputs": {"pixels": ["2a", 0], "vae": ["1", 2]},
        },
        "4": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": POSITIVE_PROMPT, "clip": ["1", 1]},
        },
        "5": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": NEGATIVE_PROMPT, "clip": ["1", 1]},
        },
        "6": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["1", 0],
                "positive": ["4", 0],
                "negative": ["5", 0],
                "latent_image": ["3", 0],
                "seed": seed,
                "steps": 30,
                "cfg": 7.0,
                "sampler_name": "dpmpp_2m_sde",
                "scheduler": "karras",
                "denoise": DENOISE_STRENGTH,
            },
        },
        "7": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["6", 0], "vae": ["1", 2]},
        },
        "8": {
            "class_type": "SaveImage",
            "inputs": {
                "images": ["7", 0],
                "filename_prefix": output_prefix,
            },
        },
    }


def build_full_workflow(raw_image_name: str, style_ref_name: str, output_prefix: str, seed: int) -> dict:
    """Full ComfyUI API workflow — SDXL + IP-Adapter (style anchor) +
    ControlNet (canny). Requires the full model set + IPAdapter custom
    node pack. See module docstring for setup.

    Graph shape:

        LoadImage(raw)  ─┬─► VAEEncode ─► (latent_image) ─┐
                         │                                │
        Checkpoint   ────┼─► (model) ──► IPAdapterApply ──┤
                         │                       ▲        │
                         │                       │        │
        LoadImage(style)─┴────────────────────── │        │
                                                          ▼
        CLIPTextEnc(+) ─► CN_Apply ◄── CN_Loader        KSampler
        CLIPTextEnc(-) ─► (neg)                            │
                                                            ▼
                                                       VAEDecode
                                                            │
                                                            ▼
                                                       SaveImage
    """
    return {
        # 1: Load SDXL checkpoint -> model, clip, vae
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": CKPT_NAME},
        },
        # 2: Load the raw render (the 3D sprite to be painted)
        "2": {
            "class_type": "LoadImage",
            "inputs": {"image": raw_image_name},
        },
        # 2a: Upscale 256x256 raw render to 1024x1024 for SDXL. Same fix
        # as the minimal workflow — SDXL produces chromatic noise on
        # smaller inputs.
        "2a": {
            "class_type": "ImageScale",
            "inputs": {
                "image": ["2", 0],
                "width": SDXL_RESOLUTION,
                "height": SDXL_RESOLUTION,
                "upscale_method": "lanczos",
                "crop": "disabled",
            },
        },
        # 3: Load the painted bible style anchor (for IP-Adapter)
        "3": {
            "class_type": "LoadImage",
            "inputs": {"image": style_ref_name},
        },
        # 4: Encode upscaled render to latent for img2img
        "4": {
            "class_type": "VAEEncode",
            "inputs": {"pixels": ["2a", 0], "vae": ["1", 2]},
        },
        # 5: Positive prompt
        "5": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": POSITIVE_PROMPT, "clip": ["1", 1]},
        },
        # 6: Negative prompt
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": NEGATIVE_PROMPT, "clip": ["1", 1]},
        },
        # 7: IP-Adapter unified loader (loads ipadapter + clip_vision in one node)
        "7": {
            "class_type": "IPAdapterUnifiedLoader",
            "inputs": {"model": ["1", 0], "preset": "PLUS (high strength)"},
        },
        # 8: Apply IP-Adapter — bias the model toward the style reference.
        # weight_type controls HOW the style influence is distributed across
        # diffusion steps. Valid values in this version of IPAdapter Plus:
        #   "standard"                — even distribution, full strength
        #   "prompt is more important" — prompt dominates style ref
        #   "style transfer"          — style ref dominates prompt
        # Switched from "style transfer" → "prompt is more important" in
        # the consistency-tuning pass. "style transfer" produced different
        # character interpretations per frame because each frame's silhouette
        # caused different style-ref blends. With the prompt now dominating
        # and the prompt being IDENTICAL across all 8 directions, identity
        # should be more consistent at small cost to painterly distinctness.
        "8": {
            "class_type": "IPAdapter",
            "inputs": {
                "model": ["7", 0],
                "ipadapter": ["7", 1],
                "image": ["3", 0],
                "weight": IPADAPTER_WEIGHT,
                "weight_type": "style transfer",
                "start_at": 0.0,
                "end_at": 1.0,
            },
        },
        # 9: Load ControlNet
        "9": {
            "class_type": "ControlNetLoader",
            "inputs": {"control_net_name": CONTROLNET_NAME},
        },
        # 9a: Canny edge detection on the upscaled input. ControlNet for
        # canny expects edge-detected input, not raw RGB. Thresholds
        # tuned for clean character silhouettes against a black bg —
        # lower thresholds catch more edges, higher = cleaner.
        "9a": {
            "class_type": "Canny",
            "inputs": {
                "image": ["2a", 0],
                "low_threshold": 0.1,
                "high_threshold": 0.3,
            },
        },
        # 10: Apply ControlNet using the canny-edge image to lock silhouette.
        "10": {
            "class_type": "ControlNetApply",
            "inputs": {
                "conditioning": ["5", 0],
                "control_net": ["9", 0],
                "image": ["9a", 0],
                "strength": CONTROLNET_STRENGTH,
            },
        },
        # 11: Sample — the actual diffusion
        "11": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["8", 0],
                "positive": ["10", 0],
                "negative": ["6", 0],
                "latent_image": ["4", 0],
                "seed": seed,
                "steps": 30,
                "cfg": 7.0,
                "sampler_name": "dpmpp_2m_sde",
                "scheduler": "karras",
                "denoise": DENOISE_STRENGTH,
            },
        },
        # 12: Decode latent back to pixels
        "12": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["11", 0], "vae": ["1", 2]},
        },
        # 13: Save output PNG
        "13": {
            "class_type": "SaveImage",
            "inputs": {
                "images": ["12", 0],
                "filename_prefix": output_prefix,
            },
        },
    }


def submit_prompt(workflow: dict, client_id: str) -> str:
    """POST workflow to /prompt. Returns the prompt_id for polling."""
    payload = {"prompt": workflow, "client_id": client_id}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{COMFYUI_URL}/prompt",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            result = json.loads(r.read())
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"[stylize] ERROR submitting prompt:")
        print(err_body)
        raise
    return result["prompt_id"]


def wait_for_prompt(prompt_id: str, timeout_sec: int = 600) -> dict:
    """Poll /history/{prompt_id} until ComfyUI reports the prompt finished.
    Returns the history dict for that prompt."""
    deadline = time.time() + timeout_sec
    last_status = ""
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"{COMFYUI_URL}/history/{prompt_id}", timeout=5) as r:
                hist = json.loads(r.read())
        except urllib.error.URLError:
            time.sleep(1.0)
            continue
        if prompt_id in hist:
            return hist[prompt_id]
        # Not in history yet — still queued / running. Read queue state.
        try:
            with urllib.request.urlopen(f"{COMFYUI_URL}/queue", timeout=3) as r:
                queue = json.loads(r.read())
            running = len(queue.get("queue_running", []))
            pending = len(queue.get("queue_pending", []))
            status = f"running={running}, pending={pending}"
            if status != last_status:
                print(f"[stylize]   queue: {status}")
                last_status = status
        except urllib.error.URLError:
            pass
        time.sleep(1.0)
    raise TimeoutError(f"Prompt {prompt_id} did not finish in {timeout_sec}s")


def download_output(image_info: dict, dest_path: Path) -> None:
    """Download the painted output image from ComfyUI."""
    params = urllib.parse.urlencode({
        "filename": image_info["filename"],
        "subfolder": image_info.get("subfolder", ""),
        "type": image_info.get("type", "output"),
    })
    with urllib.request.urlopen(f"{COMFYUI_URL}/view?{params}", timeout=30) as r:
        data = r.read()
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    with open(dest_path, "wb") as f:
        f.write(data)


# ── Main ────────────────────────────────────────────────────────────────────


def stylize_one(input_filename: str, style_filename: str) -> Path | None:
    """Process one image end-to-end. Returns the output path on success."""
    client_id = uuid.uuid4().hex
    output_prefix = f"painted_{Path(input_filename).stem}"

    if MINIMAL_MODE:
        workflow = build_minimal_workflow(input_filename, output_prefix, SEED)
        save_node_id = "8"
    else:
        workflow = build_full_workflow(input_filename, style_filename, output_prefix, SEED)
        save_node_id = "13"
    print(f"[stylize] Submitting workflow for {input_filename}...")
    prompt_id = submit_prompt(workflow, client_id)
    print(f"[stylize]   prompt_id: {prompt_id}")

    print(f"[stylize] Waiting for completion (this is the slow step — 30-90s on a 12GB GPU)...")
    t0 = time.time()
    result = wait_for_prompt(prompt_id)
    elapsed = time.time() - t0
    print(f"[stylize] Completed in {elapsed:.1f}s")

    # Find the saved image in the result outputs
    outputs = result.get("outputs", {})
    save_node_output = outputs.get(save_node_id, {})
    images = save_node_output.get("images", [])
    if not images:
        print(f"[stylize] ERROR: no output image in result. Full result:")
        print(json.dumps(result, indent=2))
        return None

    image_info = images[0]
    dest = PAINTED_DIR / f"{Path(input_filename).stem}.png"
    download_output(image_info, dest)
    print(f"[stylize] Saved: {dest}")
    return dest


def main() -> int:
    print(f"[stylize] Project root: {PROJECT_ROOT}")
    print(f"[stylize] Raw renders dir: {RAW_DIR}")
    print(f"[stylize] Painted output dir: {PAINTED_DIR}")
    print(f"[stylize] Style anchor: {STYLE_REF_PATH.name}")
    print()

    if not check_comfyui_reachable():
        return 1

    models = list_available_models()
    print()

    if not STYLE_REF_PATH.exists():
        print(f"[stylize] ERROR: style anchor missing: {STYLE_REF_PATH}")
        return 1
    if not RAW_DIR.exists():
        print(f"[stylize] ERROR: no raw renders. Run 01_render_sprite_sheet.py first.")
        return 1

    raw_pngs = sorted(RAW_DIR.glob("*.png"))
    if not raw_pngs:
        print(f"[stylize] ERROR: no PNGs in {RAW_DIR}. Run 01_render_sprite_sheet.py first.")
        return 1

    # Upload style anchor (once for the whole batch)
    print(f"[stylize] Uploading style anchor...")
    style_filename = upload_image(STYLE_REF_PATH)
    print(f"[stylize]   uploaded as: {style_filename}")

    if SMOKE_TEST:
        target = RAW_DIR / SMOKE_TEST_INPUT
        if not target.exists():
            print(f"[stylize] ERROR: smoke test input missing: {target}")
            return 1
        print(f"[stylize] SMOKE TEST: processing {target.name} only")
        raw_input_name = upload_image(target)
        result = stylize_one(raw_input_name, style_filename)
        if result is None:
            return 1
        print()
        print(f"[stylize] Smoke test complete. Inspect {result}")
        print(f"[stylize] If it looks good, edit SMOKE_TEST = False and re-run for the full batch.")
    else:
        print(f"[stylize] BATCH: processing {len(raw_pngs)} images")
        for i, png in enumerate(raw_pngs):
            print(f"[stylize] [{i+1}/{len(raw_pngs)}] {png.name}")
            raw_input_name = upload_image(png)
            stylize_one(raw_input_name, style_filename)

    return 0


if __name__ == "__main__":
    sys.exit(main())
