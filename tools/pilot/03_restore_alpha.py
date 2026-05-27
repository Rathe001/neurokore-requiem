"""
Pilot step 1b: restore alpha channel on painted outputs.

SDXL's VAE strips alpha during encode/decode, so painted outputs come
back as opaque images with whatever background the model invented.
For sprite assets we need transparent backgrounds — the level renders
separately.

Fix: use the raw render's alpha channel (which IS transparent
everywhere outside the character) as a mask on the painted output.
Painted character pixels stay painted; painted background pixels
become transparent.

Run from project root:

    python tools/pilot/03_restore_alpha.py

Reads:  tools/pilot/output/raw/{name}.png       (RGBA, char + alpha)
        tools/pilot/output/painted/{name}.png   (RGB, painted output + bg)
Writes: tools/pilot/output/painted/{name}.png   (RGBA, painted char on alpha)

Idempotent: re-running is safe, output is overwritten with the same
result. The painted/ files become RGBA after this step (originally RGB).
"""

from pathlib import Path
from PIL import Image

PROJECT_ROOT = Path(__file__).parent.parent.parent
RAW_DIR = PROJECT_ROOT / "tools" / "pilot" / "output" / "raw"
PAINTED_DIR = PROJECT_ROOT / "tools" / "pilot" / "output" / "painted"


def restore_alpha(raw_path: Path, painted_path: Path) -> None:
    """Take the painted image and re-apply the raw render's alpha
    channel. Resizes the raw alpha up to match the painted resolution
    (raw is 256², painted is 1024²)."""
    raw = Image.open(raw_path).convert("RGBA")
    painted = Image.open(painted_path).convert("RGBA")

    # Painted output is 1024², raw is 256². Scale the raw alpha up to
    # match. Bilinear keeps the edges soft so we don't get aliased
    # silhouettes — the character outline is already a few pixels wide
    # in the raw, so a slight upscale blur is forgiving.
    if raw.size != painted.size:
        raw = raw.resize(painted.size, Image.LANCZOS)

    # Extract alpha channel from the raw render
    _, _, _, raw_alpha = raw.split()
    # Replace the painted output's alpha with the raw's alpha
    r, g, b, _ = painted.split()
    masked = Image.merge("RGBA", (r, g, b, raw_alpha))

    masked.save(painted_path)


def main() -> int:
    if not RAW_DIR.exists() or not PAINTED_DIR.exists():
        print(f"[restore_alpha] Missing raw or painted dir.")
        return 1

    painted_files = sorted(PAINTED_DIR.glob("*.png"))
    if not painted_files:
        print(f"[restore_alpha] No painted PNGs found.")
        return 1

    processed = 0
    skipped = 0
    for painted_path in painted_files:
        raw_path = RAW_DIR / painted_path.name
        if not raw_path.exists():
            print(f"[restore_alpha] no matching raw for {painted_path.name}, skipping")
            skipped += 1
            continue
        restore_alpha(raw_path, painted_path)
        print(f"[restore_alpha] {painted_path.name}")
        processed += 1

    print(f"[restore_alpha] done — {processed} processed, {skipped} skipped")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
