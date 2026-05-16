#!/usr/bin/env python3
"""Extract SFX clips from a YouTube URL.

Downloads the audio with yt-dlp, runs ffmpeg silencedetect to find the
gaps between sound effects, then cuts each non-silent region into its
own numbered .wav. The clips land in
`.tmp/yt-extract-<label>/clips/clip_NN.wav` so you can audit them and
move the good ones into res://resources/audio/sfx/...

Usage:
    extract_yt_sfx.py <url> <label> [--noise-db -30] [--min-silence 0.15]

Args:
    url           YouTube URL.
    label         Short slug used for the output folder. Pick something
                  meaningful — e.g. "unarmed", "enemy_death", "ambient".
    --noise-db    Silence threshold in dB (default -30). Lower (e.g. -40)
                  catches quieter sounds; higher (-20) skips background hiss.
    --min-silence Minimum silence duration in seconds to count as a cut
                  point (default 0.15). Tune up if individual swings/hits
                  are being split into multiple clips.

Requires yt-dlp and ffmpeg on PATH.
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP_BASE = ROOT / ".tmp"


def fail(msg: str) -> "NoReturn":
    print(f"[extract_yt_sfx] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    """Run a subprocess, surfacing the command on failure."""
    try:
        return subprocess.run(cmd, check=True, **kwargs)
    except subprocess.CalledProcessError as e:
        fail(f"command failed: {' '.join(cmd)}\n{e}")


def download_audio(url: str, work_dir: Path) -> Path:
    """Pull the YouTube audio as a wav into `work_dir/source.wav`."""
    source = work_dir / "source.wav"
    if source.exists():
        print(f"  (cached) {source.relative_to(ROOT)}")
        return source
    # yt-dlp writes to <out>.<ext>; we tell it to use 'source' as the base
    # and force wav extraction so ffmpeg downstream doesn't have to guess.
    run([
        "yt-dlp",
        "-x", "--audio-format", "wav",
        "--no-playlist",
        "-o", str(work_dir / "source.%(ext)s"),
        url,
    ])
    if not source.exists():
        fail(f"yt-dlp finished but {source} not found")
    # Capture the video title for later cross-reference. Best-effort —
    # don't fail the extraction if the title query hiccups.
    try:
        title = subprocess.run(
            ["yt-dlp", "--get-title", "--no-playlist", url],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        (work_dir / "title.txt").write_text(title + "\n", encoding="utf-8")
    except subprocess.CalledProcessError:
        pass
    return source


SILENCE_START_RE = re.compile(r"silence_start: ([\d.]+)")
SILENCE_END_RE = re.compile(r"silence_end: ([\d.]+)")


def detect_clip_windows(source: Path, noise_db: float, min_silence: float) -> list[tuple[float, float]]:
    """Run ffmpeg silencedetect and return clip (start, end) pairs.

    Each non-silent region between detected silences becomes one clip.
    The very first clip starts at 0.0 (if audio begins with sound), and
    the last clip ends at the file duration.
    """
    # ffmpeg writes silencedetect markers to stderr.
    proc = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-nostats", "-i", str(source),
            "-af", f"silencedetect=noise={noise_db}dB:duration={min_silence}",
            "-f", "null", "-",
        ],
        check=False, capture_output=True, text=True,
    )
    log = proc.stderr
    starts = [float(m.group(1)) for m in SILENCE_START_RE.finditer(log)]
    ends = [float(m.group(1)) for m in SILENCE_END_RE.finditer(log)]
    # Source duration — also parsed from ffmpeg's banner.
    dur_match = re.search(r"Duration: (\d+):(\d+):([\d.]+)", log)
    if not dur_match:
        fail("ffmpeg did not report a duration; is the source a valid audio file?")
    h, m, s = dur_match.groups()
    total = int(h) * 3600 + int(m) * 60 + float(s)
    # Build clip windows: 0.0 → starts[0], ends[0] → starts[1], ..., ends[-1] → total.
    boundaries: list[tuple[float, float]] = []
    cursor = 0.0
    for i, s_start in enumerate(starts):
        if s_start > cursor + 0.05:
            boundaries.append((cursor, s_start))
        if i < len(ends):
            cursor = ends[i]
    if total > cursor + 0.05:
        boundaries.append((cursor, total))
    # Filter out clips shorter than 100ms — usually crowd noise / artifact.
    return [(a, b) for (a, b) in boundaries if (b - a) >= 0.10]


def cut_clips(source: Path, windows: list[tuple[float, float]], clips_dir: Path) -> None:
    """Slice each clip window into its own wav."""
    if clips_dir.exists():
        shutil.rmtree(clips_dir)
    clips_dir.mkdir(parents=True, exist_ok=True)
    width = max(2, len(str(len(windows))))
    for i, (start, end) in enumerate(windows, start=1):
        out = clips_dir / f"clip_{str(i).zfill(width)}.wav"
        run([
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-y",
            "-ss", f"{start:.3f}",
            "-to", f"{end:.3f}",
            "-i", str(source),
            "-c", "copy",  # no re-encode — keep the original samples
            str(out),
        ])


def write_silences_file(work_dir: Path, windows: list[tuple[float, float]]) -> None:
    """Mirror the prior .tmp/yt-extract layout so the format is consistent."""
    lines = [f"{a:.6f} {b:.6f}\n" for (a, b) in windows]
    (work_dir / "silences.txt").write_text("".join(lines), encoding="utf-8")


def main() -> None:
    # Windows console defaults to cp1252 and chokes on the unicode arrow
    # in our log lines. Same trap prepare_build.py works around.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, OSError):
            pass
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("label", help="Slug for the output folder, e.g. 'unarmed'")
    parser.add_argument("--noise-db", type=float, default=-30.0)
    parser.add_argument("--min-silence", type=float, default=0.15)
    args = parser.parse_args()

    work_dir = TMP_BASE / f"yt-extract-{args.label}"
    work_dir.mkdir(parents=True, exist_ok=True)

    print(f"[extract_yt_sfx] {args.label}: downloading audio")
    source = download_audio(args.url, work_dir)
    print(f"[extract_yt_sfx] {args.label}: scanning for clip windows (noise={args.noise_db}dB, min_silence={args.min_silence}s)")
    windows = detect_clip_windows(source, args.noise_db, args.min_silence)
    if not windows:
        fail("no non-silent regions detected; try lowering --noise-db or --min-silence")
    write_silences_file(work_dir, windows)
    clips_dir = work_dir / "clips"
    print(f"[extract_yt_sfx] {args.label}: cutting {len(windows)} clips → {clips_dir.relative_to(ROOT)}")
    cut_clips(source, windows, clips_dir)
    print(f"[extract_yt_sfx] {args.label}: done. {len(windows)} clips ready for audit.")


if __name__ == "__main__":
    main()
