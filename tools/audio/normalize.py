#!/usr/bin/env python3
"""Normalize every audio asset under game/resources/audio.

Uses ffmpeg's loudnorm filter (EBU R128) with conservative SFX targets:
  - Integrated loudness  I = -18 LUFS
  - True peak ceiling    TP = -6 dBFS
  - Loudness range       LRA = 11

The headroom is the important part — peaks land 6 dB below clipping so
several SFX summing in the mix still have ~6 dB of margin before the
master clips. Tune call-site volume_db (e.g. enemy_death's -12 in
prototype_enemy._die) on top of this if a specific event still feels
too loud.

Re-running is safe but slightly degrades quality each pass; ideally
re-extract source clips and rerun rather than normalizing repeatedly.

Usage:
    normalize.py [<dir>...]

Defaults to game/resources/audio/sfx and game/resources/audio/ambient.
Pass explicit directories to scope a re-run to one category.
"""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIRS = [
    ROOT / "game" / "resources" / "audio" / "sfx",
    ROOT / "game" / "resources" / "audio" / "ambient",
]

LOUDNORM = "loudnorm=I=-18:TP=-6:LRA=11"


def fail(msg: str) -> "NoReturn":
    print(f"[normalize] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        fail(f"command failed: {' '.join(cmd)}\nstderr: {e.stderr}")


SAMPLE_RATE_RE = re.compile(r", (\d+) Hz")


def detect_sample_rate(path: Path) -> int:
    """Read the source sample rate so we don't downsample 48kHz to 44.1."""
    proc = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=sample_rate",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        check=False, capture_output=True, text=True,
    )
    raw = proc.stdout.strip()
    return int(raw) if raw.isdigit() else 48000


def normalize_wav(path: Path) -> None:
    sr = detect_sample_rate(path)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False, dir=path.parent) as tmp:
        tmp_path = Path(tmp.name)
    try:
        run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(path),
            "-af", LOUDNORM,
            "-ar", str(sr),
            "-c:a", "pcm_s16le",
            str(tmp_path),
        ])
        shutil.move(str(tmp_path), str(path))
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def normalize_ogg(path: Path) -> None:
    sr = detect_sample_rate(path)
    with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False, dir=path.parent) as tmp:
        tmp_path = Path(tmp.name)
    try:
        run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(path),
            "-af", LOUDNORM,
            "-ar", str(sr),
            "-c:a", "libvorbis", "-qscale:a", "4",
            str(tmp_path),
        ])
        shutil.move(str(tmp_path), str(path))
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, OSError):
            pass
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dirs", nargs="*", type=Path,
                        help="Directories to scan; default scans game/resources/audio/{sfx,ambient}")
    args = parser.parse_args()

    targets = [Path(d) for d in args.dirs] if args.dirs else DEFAULT_DIRS

    wav_files: list[Path] = []
    ogg_files: list[Path] = []
    for d in targets:
        if not d.exists():
            print(f"[normalize] skip: {d.relative_to(ROOT)} (does not exist)")
            continue
        wav_files.extend(sorted(d.rglob("*.wav")))
        ogg_files.extend(sorted(d.rglob("*.ogg")))

    total = len(wav_files) + len(ogg_files)
    if total == 0:
        print("[normalize] no audio files found")
        return
    print(f"[normalize] processing {len(wav_files)} wav + {len(ogg_files)} ogg = {total} files")
    print(f"[normalize] target: {LOUDNORM}")
    print()

    for i, path in enumerate(wav_files, start=1):
        print(f"  [{i}/{len(wav_files)}] wav  {path.relative_to(ROOT)}")
        normalize_wav(path)
    for i, path in enumerate(ogg_files, start=1):
        print(f"  [{i}/{len(ogg_files)}] ogg  {path.relative_to(ROOT)}")
        normalize_ogg(path)
    print()
    print(f"[normalize] done. {total} files normalized.")


if __name__ == "__main__":
    main()
