"""Mirror rendered art from tools/pilot/output/ into the Godot pilot
project at tools/pilot/godot_test/ so it can load them as
`res://sprites/...` and `res://environment/...`.

Why copy instead of symlink: symlinks on Windows need admin elevation,
and Godot's importer won't follow them reliably anyway.

Run:
    python tools/pilot/copy_sprites_to_godot.py            # all chars + env
    python tools/pilot/copy_sprites_to_godot.py analog_male cyborg_female   # subset of chars
    python tools/pilot/copy_sprites_to_godot.py --env-only                  # just environment
"""
import shutil
import sys
from pathlib import Path

PILOT_ROOT = Path(__file__).parent
SRC = PILOT_ROOT / "output" / "raw"
DST = PILOT_ROOT / "godot_test" / "sprites"
ENV_SRC = PILOT_ROOT / "output" / "environment"
ENV_DST = PILOT_ROOT / "godot_test" / "environment"


def copy_characters(requested: set[str]) -> None:
    if not SRC.exists():
        print(f"[copy] missing {SRC} — render some characters first")
        return
    DST.mkdir(parents=True, exist_ok=True)

    chars = [p for p in SRC.iterdir() if p.is_dir()]
    if requested:
        chars = [c for c in chars if c.name in requested]
        missing = requested - {c.name for c in chars}
        if missing:
            print(f"[copy] WARNING: requested but not rendered: {sorted(missing)}")

    for src_char in chars:
        dst_char = DST / src_char.name
        if dst_char.exists():
            shutil.rmtree(dst_char)
        shutil.copytree(src_char, dst_char)
        n = sum(1 for _ in dst_char.rglob("*.png"))
        mb = sum(p.stat().st_size for p in dst_char.rglob("*.png")) / 1024 / 1024
        print(f"[copy] {src_char.name}: {n} PNGs ({mb:.1f} MB)")


def copy_environment() -> None:
    if not ENV_SRC.exists():
        print(f"[copy] no environment output yet ({ENV_SRC})")
        return
    if ENV_DST.exists():
        shutil.rmtree(ENV_DST)
    shutil.copytree(ENV_SRC, ENV_DST)
    n = sum(1 for _ in ENV_DST.rglob("*.png"))
    mb = sum(p.stat().st_size for p in ENV_DST.rglob("*.png")) / 1024 / 1024
    print(f"[copy] environment: {n} PNGs ({mb:.1f} MB)")


def main():
    args = sys.argv[1:]
    env_only = "--env-only" in args
    chars_only = "--chars-only" in args
    requested = {a for a in args if not a.startswith("--")}

    if not env_only:
        copy_characters(requested)
    if not chars_only:
        copy_environment()


if __name__ == "__main__":
    main()
