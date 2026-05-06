#!/usr/bin/env python3
"""Prepare a Steam build: bump version, roll CHANGELOG, regenerate VDF desc.

Run from anywhere — paths are anchored at the repo root via this script's
location. Both deploy.sh and deploy.bat invoke this before the Godot export
step, so version + notes always match the bits being uploaded.

What it does:
  1. Parses VERSION and BUILD_DATE constants in game/scripts/systems/build_info.gd
  2. Bumps VERSION per --bump flag (default: patch)
  3. Sets BUILD_DATE to today (UTC)
  4. Reads CHANGELOG.md '## [Unreleased]' section.
       - Errors out if the section is empty (deploy refuses to proceed
         without patch notes; this is the forcing function).
       - Rewrites the section as '## [VERSION] - YYYY-MM-DD' and inserts
         a fresh empty '## [Unreleased]' above it.
  5. Reads short git SHA via `git rev-parse --short HEAD`.
  6. Updates app_build_4689320.vdf 'desc' field with version + SHA + the
     first non-blank line of the new release notes (Steamworks build list
     becomes immediately scannable).

Exits non-zero on any failure so deploy scripts halt before uploading.

Usage:
    prepare_build.py [--bump {patch,minor,major}] [--dry-run]

Flags:
    --bump      Which semver component to bump. Default: patch.
    --dry-run   Print what would change without writing files. Useful for
                CI smoke tests or "what version would this be" checks.
"""

import argparse
import datetime
import re
import subprocess
import sys
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent.parent
BUILD_INFO_PATH = ROOT / "game" / "scripts" / "systems" / "build_info.gd"
CHANGELOG_PATH = ROOT / "CHANGELOG.md"
VDF_PATH = SCRIPT_DIR / "app_build_4689320.vdf"


# ── Helpers ───────────────────────────────────────────────────────────────────
def fail(msg: str) -> "NoReturn":
    print(f"[prepare_build] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def read(path: Path) -> str:
    if not path.exists():
        fail(f"{path} not found")
    return path.read_text(encoding="utf-8")


def write(path: Path, content: str, dry_run: bool) -> None:
    if dry_run:
        print(f"[prepare_build] (dry-run) would write {path.relative_to(ROOT)}")
        return
    # Force LF newlines. Without this, Windows runs of write_text default to
    # CRLF and the resulting commit gets "CRLF will be replaced by LF"
    # warnings on every deploy because .gitattributes normalizes text files
    # to LF in the repo.
    path.write_text(content, encoding="utf-8", newline="\n")


def git_short_sha() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return "unknown"


# ── Version handling ──────────────────────────────────────────────────────────
VERSION_RE = re.compile(r'^const VERSION := "(\d+)\.(\d+)\.(\d+)"', re.MULTILINE)
BUILD_DATE_RE = re.compile(r'^const BUILD_DATE := "(\d{4}-\d{2}-\d{2})"', re.MULTILINE)


def bump_version(current: tuple[int, int, int], part: str) -> tuple[int, int, int]:
    major, minor, patch = current
    if part == "major":
        return (major + 1, 0, 0)
    if part == "minor":
        return (major, minor + 1, 0)
    if part == "patch":
        return (major, minor, patch + 1)
    fail(f"unknown --bump value: {part}")


def update_build_info(bump: str, dry_run: bool) -> tuple[str, str]:
    """Bump VERSION + BUILD_DATE in build_info.gd. Returns (new_version, new_date)."""
    text = read(BUILD_INFO_PATH)
    m = VERSION_RE.search(text)
    if not m:
        fail(f"VERSION constant not found in {BUILD_INFO_PATH}")
    current = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    new = bump_version(current, bump)
    new_version = f"{new[0]}.{new[1]}.{new[2]}"
    today = datetime.date.today().isoformat()

    text = VERSION_RE.sub(f'const VERSION := "{new_version}"', text, count=1)
    text = BUILD_DATE_RE.sub(f'const BUILD_DATE := "{today}"', text, count=1)
    write(BUILD_INFO_PATH, text, dry_run)
    return new_version, today


# ── CHANGELOG handling ────────────────────────────────────────────────────────
UNRELEASED_RE = re.compile(
    r"^## \[Unreleased\]\s*\n(.*?)(?=^## \[|\Z)", re.MULTILINE | re.DOTALL
)


def extract_unreleased(text: str) -> str:
    """Return the body (without the heading) of '## [Unreleased]'."""
    m = UNRELEASED_RE.search(text)
    if not m:
        fail("CHANGELOG.md is missing a '## [Unreleased]' section")
    body = m.group(1).strip()
    if not body:
        fail(
            "CHANGELOG.md '## [Unreleased]' section is empty. "
            "Add notes describing what's in this build before deploying."
        )
    return body


def rotate_changelog(version: str, date: str, dry_run: bool) -> str:
    """Move [Unreleased] body to a versioned section. Returns the unreleased body
    so the caller can use the first line for the VDF desc."""
    text = read(CHANGELOG_PATH)
    body = extract_unreleased(text)
    new_section = f"## [Unreleased]\n\n## [{version}] - {date}\n\n{body}\n"
    text = UNRELEASED_RE.sub(new_section + "\n", text, count=1)
    write(CHANGELOG_PATH, text, dry_run)
    return body


def first_summary_line(body: str) -> str:
    """Pick a single short summary line for the build description.

    Walks the changelog body, skips '### Added/Fixed/Changed' headings and
    blank lines, and returns the first list item (with the leading '- '
    stripped). Truncated to 60 chars so the Steamworks build list stays
    legible — the full notes live in CHANGELOG.md.
    """
    for raw in body.splitlines():
        line = raw.strip()
        if not line or line.startswith("###"):
            continue
        if line.startswith("- "):
            line = line[2:].strip()
        if len(line) > 60:
            line = line[:57].rstrip() + "..."
        return line
    return "see CHANGELOG.md"


# ── VDF handling ──────────────────────────────────────────────────────────────
DESC_RE = re.compile(r'^(\s*"desc"\s*)"[^"]*"', re.MULTILINE)


def update_vdf_desc(version: str, sha: str, summary: str, dry_run: bool) -> str:
    """Rewrite the 'desc' field in the Steam app build VDF."""
    text = read(VDF_PATH)
    desc = f"v{version} · {sha} · {summary}"
    if not DESC_RE.search(text):
        fail(f"VDF at {VDF_PATH} has no 'desc' field")
    text = DESC_RE.sub(rf'\1"{desc}"', text, count=1)
    write(VDF_PATH, text, dry_run)
    return desc


# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> None:
    # Windows console defaults to cp1252, which chokes on the middot ('·') in
    # the build desc and the box-drawing chars in the summary banner. Force
    # UTF-8 so the script behaves the same on Windows / macOS / Linux.
    # reconfigure() is available on Python 3.7+; guarded for safety.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, OSError):
            pass
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bump",
        choices=["patch", "minor", "major"],
        default="patch",
        help="Which semver component to increment (default: patch)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would change without writing files",
    )
    args = parser.parse_args()

    version, date = update_build_info(args.bump, args.dry_run)
    body = rotate_changelog(version, date, args.dry_run)
    sha = git_short_sha()
    summary = first_summary_line(body)
    desc = update_vdf_desc(version, sha, summary, args.dry_run)

    print()
    print("─── Build prepared " + "─" * 40)
    print(f"  Version:  {version}  ({args.bump} bump)")
    print(f"  Date:     {date}")
    print(f"  Git SHA:  {sha}")
    print(f"  VDF desc: {desc}")
    print("─" * 60)
    if args.dry_run:
        print("\n[prepare_build] dry-run — no files written.")
    else:
        print("\nNext: deploy script will export and upload this build.")
        print(
            "After upload succeeds, commit the version bump + changelog with\n"
            f"    git commit -am 'Release v{version}'"
        )


if __name__ == "__main__":
    main()
