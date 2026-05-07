"""One-shot icon crop: find the saturated logo content in download.png,
crop to a tight square, resize to 512x512.

The source has a dark grungy background and a bright cyan/pink logo, so
saturation-based content detection finds the logo cleanly without
misfiring on lighter background highlights (metal panels, wires).
"""

import sys
from pathlib import Path

from PIL import Image

SRC = Path("C:/Users/josh/Desktop/download.png")
DST = Path("C:/Users/josh/Desktop/icon-512.png")

# Saturation threshold for "this is logo content" — tuned by eye for
# the cyan/pink palette vs. desaturated grayscale background. Bump
# higher if background highlights leak in, lower if drips get clipped.
SAT_THRESHOLD = 160
# Padding around the detected logo as a fraction of the longer logo
# axis. 0.04 = 4% breathing room on each side.
PAD_FRAC = 0.04


def main() -> int:
	img = Image.open(SRC).convert("RGB")
	W, H = img.size

	hsv = img.convert("HSV")
	sat = hsv.split()[1]
	# point() builds a lookup table; produces a binary mask where
	# saturated (logo) pixels are 255 and gray (background) are 0.
	mask = sat.point(lambda p: 255 if p > SAT_THRESHOLD else 0)
	bbox = mask.getbbox()
	if bbox is None:
		print(f"No saturated content found at threshold {SAT_THRESHOLD}; aborting.")
		return 1

	left, top, right, bottom = bbox
	logo_w = right - left
	logo_h = bottom - top
	pad = int(max(logo_w, logo_h) * PAD_FRAC)
	left = max(0, left - pad)
	top = max(0, top - pad)
	right = min(W, right + pad)
	bottom = min(H, bottom + pad)

	# Square crop centered on the logo's bounding box.
	w = right - left
	h = bottom - top
	size = max(w, h)
	cx = (left + right) // 2
	cy = (top + bottom) // 2
	half = size // 2
	sl = max(0, cx - half)
	st = max(0, cy - half)
	sr = min(W, sl + size)
	sb = min(H, st + size)
	# Snap back if we ran off the right/bottom — preserves square shape
	# even when the logo is closer to one edge.
	if sr - sl < size:
		sl = sr - size
	if sb - st < size:
		st = sb - size
	sl = max(0, sl)
	st = max(0, st)

	cropped = img.crop((sl, st, sl + size, st + size))
	resized = cropped.resize((512, 512), Image.LANCZOS)
	resized.save(DST, "PNG", optimize=True)

	print(f"Source:  {W}x{H}")
	print(f"Logo bbox (raw): {bbox}  ({logo_w}x{logo_h})")
	print(f"Crop:    ({sl}, {st})  {size}x{size}")
	print(f"Saved:   {DST}  (512x512)")
	return 0


if __name__ == "__main__":
	sys.exit(main())
