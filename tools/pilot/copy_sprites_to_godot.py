"""Mirror rendered character sprites from tools/pilot/output/raw/ into
tools/pilot/godot_test/sprites/ so the Godot pilot project can load them
as `res://sprites/<character>/<anim>/<dir>_<frame>.png`.

Why copy instead of symlink: symlinks on Windows need admin elevation,
and Godot's importer won't follow them reliably anyway.

Run:
    python tools/pilot/copy_sprites_to_godot.py            # copies all characters
    python tools/pilot/copy_sprites_to_godot.py analog_male cyborg_female   # subset
"""
import shutil
import sys
from pathlib import Path

PILOT_ROOT = Path(__file__).parent
SRC = PILOT_ROOT / "output" / "raw"
DST = PILOT_ROOT / "godot_test" / "sprites"


def main():
    if not SRC.exists():
        print(f"[copy] missing {SRC} — render some sprites first")
        return
    requested = set(sys.argv[1:])
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


if __name__ == "__main__":
    main()
