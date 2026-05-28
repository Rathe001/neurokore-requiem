"""Batch driver — merges + renders every player class in CHARACTERS in
one sweep, without editing config blocks in merge_mixamo_anims.py /
01_render_sprite_sheet.py per character.

Each character must have a with-skin Idle FBX at
    source/player/{sex}/{class}/Idle.fbx
and the shared anim FBXs at
    source/player/{sex}/*.fbx

Run:
    python tools/pilot/batch_render.py
    python tools/pilot/batch_render.py countess_female enculted_male  # subset

Set BLENDER env var to override the Blender executable path.

~6-8 min per character on a 1344-frame player set (8 dirs × 9 anims).
Output streams to stdout; log to a file with `> log.txt 2>&1` if you
want to walk away.
"""
import os
import subprocess
import sys
import time
from pathlib import Path

PILOT_ROOT = Path(__file__).parent
DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
BLENDER = os.environ.get("BLENDER", DEFAULT_BLENDER)

# (class_name, sex) — must have source/player/{sex}/{class}/Idle.fbx
CHARACTERS = [
    ("analog",      "male"),
    ("analog",      "female"),
    ("cyborg",      "male"),
    ("cyborg",      "female"),
    ("count",       "male"),
    ("countess",    "female"),
    ("enculted",    "male"),
    ("enculted",    "female"),
    ("survivalist", "male"),
    ("survivalist", "female"),
]


def char_name(class_name: str, sex: str) -> str:
    return f"{class_name}_{sex}"


def run_blender(script: str, env: dict) -> int:
    cmd = [BLENDER, "-b", "-P", str(PILOT_ROOT / script)]
    proc = subprocess.run(cmd, env=env)
    return proc.returncode


def main():
    requested = set(sys.argv[1:])
    to_run = [(c, s) for c, s in CHARACTERS if not requested or char_name(c, s) in requested]
    if requested:
        missing = requested - {char_name(c, s) for c, s in CHARACTERS}
        if missing:
            print(f"[batch] WARNING: unknown characters: {sorted(missing)}", file=sys.stderr)
    if not to_run:
        print("[batch] nothing to do")
        return

    print(f"[batch] will process {len(to_run)} character(s):")
    for c, s in to_run:
        print(f"  - {char_name(c, s)}")

    total_start = time.time()
    for class_name, sex in to_run:
        name = char_name(class_name, sex)
        print(f"\n[batch] === {name} ===", flush=True)
        char_start = time.time()

        env = os.environ.copy()
        env["PILOT_CLASS"] = class_name
        env["PILOT_SEX"]   = sex

        rc = run_blender("merge_mixamo_anims.py", env)
        if rc != 0:
            print(f"[batch] {name}: merge failed (rc={rc}), skipping render", file=sys.stderr)
            continue
        rc = run_blender("01_render_sprite_sheet.py", env)
        if rc != 0:
            print(f"[batch] {name}: render failed (rc={rc})", file=sys.stderr)
            continue

        elapsed = time.time() - char_start
        print(f"[batch] {name}: done in {elapsed:.0f}s", flush=True)

    total_elapsed = time.time() - total_start
    print(f"\n[batch] {len(to_run)} character(s) in {total_elapsed/60:.1f} min")


if __name__ == "__main__":
    main()
