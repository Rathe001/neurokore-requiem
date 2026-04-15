# Neurokore: Requiem

A Diablo 2-style ARPG set in a campy 80s sci-fi / Neuromancer cyberpunk hybrid world.

---

## Table of Contents

- [Vision](#vision)
- [Tone & Setting](#tone--setting)
- [Art Style](#art-style)
- [Camera & Perspective](#camera--perspective)
- [Level Design](#level-design)
- [Combat & Scale](#combat--scale)
- [Classes](#classes)
- [Dialog & UI](#dialog--ui)
- [Status](#status)
- [License](#license)

---

## Vision

Neurokore: Requiem is a hack-and-slash ARPG in the tradition of Diablo 2 — deep build crafting, loot-driven progression, and dense enemy encounters — set in a world where corporate dystopia, neural augmentation, and campy 80s horror collide.

---

## Tone & Setting

- **Baseline:** Gritty neon-noir. Wet streets, corporate surveillance, burned-out chrome. The world is oppressive and lived-in.
- **Surface layer:** Campy 80s sci-fi aesthetic — practical special effects energy, lurid colors, over-the-top set pieces.
- **Edge:** 80s horror. Body horror from failed augmentations, something ancient and wrong bleeding through the network, grotesque enemies that feel like they belong in *The Thing* or *Videodrome* as much as *Neuromancer*.
- The tension between the technological and the monstrous is a core thematic thread.

---

## Art Style

- **Style:** Isometric pixel art — modern fidelity, not chunky retro. Slightly more pixelated than the reference mockup (`reference/mockups/world1.png`).
- **Palette:** Dark, desaturated base with neon pops. Teal/cyan dominant, hot pink and red as accent colors. Wet-street reflections on ground surfaces.
- **Lighting:** Real-time dynamic lighting — sprites receive light rather than baking it into textures. Neon signs, explosions, and spells cast actual light into the environment.
- **Animation:** ~25fps sprite animation in the Diablo 2 tradition. Weighted, deliberate feel.
- **Bosses:** Large-scale pixel art enemies — the small player character scale makes oversized bosses highly readable and impactful.

---

## Camera & Perspective

- **Projection:** Fixed isometric.
- **Occlusion:** Any geometry that would obscure the player character (walls, roofs, structures) becomes transparent. The player is always visible.
- **No rotation or zoom** (fixed camera).

---

## Level Design

- **Construction:** Tile-based, procedurally generated. Tiles and layouts simulate a hand-crafted look.
- **Hand-crafted rooms:** Specific events, boss arenas, story moments, and landmark rooms are hand-crafted but designed to slot seamlessly into procedurally generated levels.
- **Progression:** Early areas are tighter and less dense. End-game environments support Vampire Survivors-scale hordes.

---

## Combat & Scale

- **Feel:** D2-style — deliberate, weighted, build-dependent. Combat should feel impactful, not floaty.
- **Enemy density:** Scales across the game. Early game: small groups. End-game: large hordes filling the screen.
- **Player scale:** Smaller than D2. More screen real estate means more simultaneous action and more readable large bosses.
- **Core mechanic:** Class-specific (see Classes). No universal mechanic shared across all classes.

---

## Classes

- **Class identity is the core design pillar.** Each class plays differently enough that it could feel like a different game mode.
- Class-specific core mechanics — not all classes share the same resource systems, survival mechanics, or win conditions. For example, not all classes will have a health bar.
- Details TBD as classes are designed individually.

---

## Dialog & UI

- **Portraits:** Animated pixel art portrait busts for NPCs, enemies, and quest-givers — in the style of Bard's Tale 1. Simple animation loops (blinking, mouth movement, class/corruption-specific effects).

---

## Status

Early design phase. Tech stack TBD — will be chosen to fit the game's requirements.

---

## License

MIT — see [LICENSE](LICENSE) for details.
