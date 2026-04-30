# Art Style

- **Style:** Low-poly 3D with high-resolution PBR textures. Clean, readable silhouettes at the locked camera angle; surface detail carried by textures and lighting rather than polygon count. Stylized — not aiming for photo-realism.
- **Palette:** Dark, desaturated base with neon pops. Teal/cyan dominant, hot pink and red as accent colors. Wet, reflective ground surfaces wherever the fiction supports it.
- **Lighting:** Dynamic real-time lighting is the dominant visual identity. Neon signs, spells, generator rooms, and equipped light sources cast actual light into the world. See [`lighting.md`](lighting.md) for the full lighting design — it drives more of the visual feel than any other single system.
- **Materials:** PBR — metallic, roughness, emissive, normal maps. Emissive surfaces carry the neon aesthetic.
- **Animation:** 3D keyframe animation. Weighted and deliberate — closer to Diablo 2's animation philosophy than to fluid action-game animation. Attacks should feel committed.
- **Bosses:** Oversized models relative to the player. The fixed camera and small base-player scale make large bosses highly readable and impactful.

## Camera & Perspective

- **Projection:** Fixed camera — locked pitch, yaw, and distance. Same visual feel as the previous isometric plan, but 3D under the hood.
- **Occlusion:** Geometry that would obscure the player (walls, roofs, overhead structures) must become transparent or fade. The player is always visible.
- **No rotation or zoom.** The camera is part of the game's identity — not a user control.

## Low-Poly Discipline

- Spend polygon budget on **silhouette**, not surface detail. Textures and normal maps carry surface detail.
- Consistent poly-density across assets — mixing a highly detailed model with a low-poly one breaks the style.
- UV-efficient authoring — shared texture atlases where appropriate to keep VRAM within the integrated-graphics target.
- Emissive texture channels do a lot of the heavy lifting for the neon aesthetic.

## Class Color Language

Each class has a consistent color identity used across models, materials, UI, ability effects, and enemy design. Established through concept work — treat as a visual consistency guide that carries through into 3D authoring (emissive accents, rim lights, particle effects, UI theming).

| Class | Color Identity |
|---|---|
| Cyborg (origin) | Teal/cyan + muted pink |
| Forged | Red |
| Automaton | Teal/green data |
| Polymath | Yellow |
| Analog (origin) | Brown |
| Survivalist | Dirty yellow, rust orange |
| Count / Countess | Ivory |
| Enculted | Purple |

This color language should carry through to ability particle effects, resource meter colors, portrait rim lighting, and class-specific UI elements.
