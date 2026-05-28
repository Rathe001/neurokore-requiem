"""Scan tools/pilot/output/raw/<character>/<anim>/<dir>_<frame>.png
and write an interactive HTML viewer at tools/pilot/output/viewer.html.

Open by double-clicking (no server needed — uses relative image paths).

Run:
    python tools/pilot/build_viewer.py
"""
import json
import re
import webbrowser
from pathlib import Path

OUTPUT_ROOT = Path(__file__).parent / "output"
RAW_ROOT = OUTPUT_ROOT / "raw"

DIRECTIONS = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
FRAME_RE = re.compile(r"^([A-Z]+)_(\d+)\.png$")


def scan() -> dict:
    """Build {character: {anim: {direction: [relative_paths]}}}."""
    manifest = {}
    if not RAW_ROOT.exists():
        return manifest
    for char_dir in sorted(RAW_ROOT.iterdir()):
        if not char_dir.is_dir():
            continue
        char = char_dir.name
        manifest[char] = {}
        for anim_dir in sorted(char_dir.iterdir()):
            if not anim_dir.is_dir():
                continue
            anim = anim_dir.name
            per_dir: dict[str, list[str]] = {d: [] for d in DIRECTIONS}
            for png in sorted(anim_dir.iterdir()):
                m = FRAME_RE.match(png.name)
                if not m:
                    continue
                d, frame = m.group(1), int(m.group(2))
                if d not in per_dir:
                    continue
                rel = f"raw/{char}/{anim}/{png.name}"
                per_dir[d].append((frame, rel))
            for d in per_dir:
                per_dir[d] = [p for _, p in sorted(per_dir[d])]
            manifest[char][anim] = per_dir
    return manifest


HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Neurokore sprite viewer</title>
<style>
  :root {
    --bg: #0e0d12;
    --panel: #18171f;
    --text: #d7d3e0;
    --muted: #6e6a7c;
    --accent: #ff5577;
    --border: #2a2832;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font: 14px/1.4 system-ui, sans-serif;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
  }
  header {
    padding: 12px 20px;
    border-bottom: 1px solid var(--border);
    display: flex;
    gap: 16px;
    align-items: center;
    flex-wrap: wrap;
  }
  header h1 { font-size: 16px; margin: 0; font-weight: 600; }
  label { color: var(--muted); margin-right: 6px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.06em; }
  select, button {
    background: var(--panel);
    color: var(--text);
    border: 1px solid var(--border);
    padding: 6px 10px;
    border-radius: 4px;
    font: inherit;
    cursor: pointer;
  }
  button.active { border-color: var(--accent); color: var(--accent); }
  main { padding: 24px; }
  .grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 14px;
    max-width: 1100px;
    margin: 0 auto;
  }
  .cell {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 8px;
    text-align: center;
  }
  .cell.selected { border-color: var(--accent); }
  .cell .label { color: var(--muted); font-size: 11px; letter-spacing: 0.08em; margin-bottom: 4px; }
  .cell img {
    width: 100%;
    height: auto;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
    background:
      linear-gradient(45deg, #1d1c25 25%, transparent 25%) 0 0 / 16px 16px,
      linear-gradient(-45deg, #1d1c25 25%, transparent 25%) 0 0 / 16px 16px,
      linear-gradient(45deg, transparent 75%, #1d1c25 75%) 8px 8px / 16px 16px,
      linear-gradient(-45deg, transparent 75%, #1d1c25 75%) 8px 8px / 16px 16px,
      #131218;
  }
  .stage {
    display: flex;
    gap: 24px;
    align-items: flex-start;
    justify-content: center;
    max-width: 1100px;
    margin: 0 auto;
  }
  .stage .big {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 16px;
  }
  .stage .big img {
    width: 512px;
    height: 512px;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
    background:
      linear-gradient(45deg, #1d1c25 25%, transparent 25%) 0 0 / 32px 32px,
      linear-gradient(-45deg, #1d1c25 25%, transparent 25%) 0 0 / 32px 32px,
      linear-gradient(45deg, transparent 75%, #1d1c25 75%) 16px 16px / 32px 32px,
      linear-gradient(-45deg, transparent 75%, #1d1c25 75%) 16px 16px / 32px 32px,
      #131218;
  }
  .stage .controls {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 6px;
    width: 200px;
  }
  .stage .controls button {
    padding: 12px 0;
    font-weight: 600;
  }
  .info {
    color: var(--muted);
    font-size: 12px;
    text-align: center;
    margin: 16px 0;
  }
  .fps {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .fps input { width: 50px; background: var(--panel); color: var(--text); border: 1px solid var(--border); padding: 4px; border-radius: 4px; }
</style>
</head>
<body>
<header>
  <h1>Neurokore sprite viewer</h1>
  <div><label>Character</label><select id="char"></select></div>
  <div><label>Animation</label><select id="anim"></select></div>
  <div><label>View</label>
    <button id="mode-grid" class="active">All 8 dirs</button>
    <button id="mode-single">Single big</button>
  </div>
  <div class="fps"><label>FPS</label><input id="fps" type="number" min="1" max="60" value="12"></div>
</header>
<main>
  <div class="info" id="status">…</div>
  <div id="grid" class="grid"></div>
  <div id="stage" class="stage" style="display:none">
    <div class="big"><img id="big-img" alt=""></div>
    <div>
      <div class="info">Pick direction</div>
      <div class="controls" id="dir-controls"></div>
    </div>
  </div>
</main>

<script>
const MANIFEST = __MANIFEST__;
const DIRECTIONS = ["NW", "N", "NE", "W", "S", "E", "SW", "S", "SE"];
// 3x3 layout: NW N NE / W . E / SW S SE  (center is S duplicate for symmetry)

let currentChar, currentAnim, currentDir = "S", mode = "grid", fps = 12;
let frameIdx = 0;
let timer = null;

const $ = (id) => document.getElementById(id);

function frameCount() {
  const anim = MANIFEST[currentChar][currentAnim];
  return Math.max(1, anim["S"].length);
}

function tick() {
  frameIdx = (frameIdx + 1) % frameCount();
  render();
}

function startLoop() {
  clearInterval(timer);
  timer = setInterval(tick, 1000 / fps);
}

function buildGrid() {
  // 3x3 layout: NW N NE / W (label) E / SW S SE
  const layout = [
    ["NW", "N",  "NE"],
    ["W",  null, "E" ],
    ["SW", "S",  "SE"],
  ];
  const grid = $("grid");
  grid.innerHTML = "";
  grid.style.gridTemplateColumns = "repeat(3, 1fr)";
  for (const row of layout) {
    for (const d of row) {
      const cell = document.createElement("div");
      cell.className = "cell";
      if (d === null) {
        cell.innerHTML = `<div class="label">center</div><div style="color:var(--muted);padding:40px 0">—</div>`;
      } else {
        cell.dataset.dir = d;
        cell.innerHTML = `<div class="label">${d}</div><img alt="${d}">`;
      }
      grid.appendChild(cell);
    }
  }
}

function buildDirControls() {
  const layout = [
    ["NW", "N",  "NE"],
    ["W",  null, "E" ],
    ["SW", "S",  "SE"],
  ];
  const c = $("dir-controls");
  c.innerHTML = "";
  for (const row of layout) {
    for (const d of row) {
      const b = document.createElement("button");
      b.textContent = d || "·";
      if (!d) { b.disabled = true; b.style.opacity = 0.2; }
      else b.onclick = () => { currentDir = d; updateDirButtons(); render(); };
      c.appendChild(b);
    }
  }
  updateDirButtons();
}

function updateDirButtons() {
  for (const b of $("dir-controls").querySelectorAll("button")) {
    b.classList.toggle("active", b.textContent === currentDir);
  }
}

function render() {
  const anim = MANIFEST[currentChar][currentAnim];
  if (mode === "grid") {
    for (const cell of $("grid").querySelectorAll(".cell[data-dir]")) {
      const d = cell.dataset.dir;
      const frames = anim[d] || [];
      if (!frames.length) continue;
      const img = cell.querySelector("img");
      img.src = frames[frameIdx % frames.length];
    }
  } else {
    const frames = anim[currentDir] || [];
    if (frames.length) $("big-img").src = frames[frameIdx % frames.length];
  }
  $("status").textContent =
    `${currentChar} / ${currentAnim} / frame ${frameIdx + 1} of ${frameCount()}`;
}

function populateChars() {
  const sel = $("char");
  sel.innerHTML = "";
  for (const c of Object.keys(MANIFEST)) {
    const o = document.createElement("option"); o.value = c; o.textContent = c; sel.appendChild(o);
  }
  currentChar = Object.keys(MANIFEST)[0];
  sel.value = currentChar;
}

function populateAnims() {
  const sel = $("anim");
  sel.innerHTML = "";
  for (const a of Object.keys(MANIFEST[currentChar])) {
    const o = document.createElement("option"); o.value = a; o.textContent = a; sel.appendChild(o);
  }
  currentAnim = Object.keys(MANIFEST[currentChar])[0];
  sel.value = currentAnim;
}

function applyMode() {
  $("grid").style.display = mode === "grid" ? "" : "none";
  $("stage").style.display = mode === "single" ? "" : "none";
  $("mode-grid").classList.toggle("active", mode === "grid");
  $("mode-single").classList.toggle("active", mode === "single");
}

$("char").onchange = (e) => {
  currentChar = e.target.value;
  populateAnims();
  frameIdx = 0;
  render();
};
$("anim").onchange = (e) => {
  currentAnim = e.target.value;
  frameIdx = 0;
  render();
};
$("mode-grid").onclick = () => { mode = "grid"; applyMode(); render(); };
$("mode-single").onclick = () => { mode = "single"; applyMode(); render(); };
$("fps").onchange = (e) => {
  fps = parseInt(e.target.value, 10) || 12;
  startLoop();
};

if (Object.keys(MANIFEST).length === 0) {
  $("status").textContent = "No sprite data found — run 01_render_sprite_sheet.py first.";
} else {
  populateChars();
  populateAnims();
  buildGrid();
  buildDirControls();
  applyMode();
  render();
  startLoop();
}
</script>
</body>
</html>
"""


def main():
    manifest = scan()
    if not manifest:
        print(f"[viewer] No renders found under {RAW_ROOT}")
        return
    html = HTML.replace("__MANIFEST__", json.dumps(manifest))
    out = OUTPUT_ROOT / "viewer.html"
    out.write_text(html, encoding="utf-8")
    chars = list(manifest.keys())
    print(f"[viewer] wrote {out}")
    print(f"[viewer] characters: {chars}")
    for c in chars:
        anims = list(manifest[c].keys())
        print(f"[viewer]   {c}: {anims}")
    webbrowser.open(out.as_uri())


if __name__ == "__main__":
    main()
