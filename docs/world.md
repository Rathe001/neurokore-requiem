# World

What the game world feels like, why it looks the way it does, and how zones and lighting reinforce the tone. Deep narrative content (Earth Facility #723, the reps, the Confrontation) lives in [`narrative-bible.md`](narrative-bible.md) — none of it is shipped yet.

## Tone

Three layers, coexisting without cancelling each other out:

- **Baseline — gritty neon-noir.** Wet streets, corporate surveillance, burned-out chrome. Power is held by entities too large to see and too indifferent to hate. People are resources. The city does not care about you.
- **Surface — campy 80s sci-fi.** Lurid colors, over-the-top set pieces, practical-effects energy. Not ironic distance — genuine enthusiasm. Flash Gordon chrome lives alongside Neuromancer grime.
- **Edge — 80s body horror.** Augmentations that went wrong (or right). Something ancient living in the network that the augmented mind cannot access and the unaugmented mind cannot ignore. Enemies that belong in *The Thing* or *Videodrome* as much as in *Neuromancer*.

The horror does not come from the unknown — it comes from the known: procedures that failed, experiments that were abandoned, systems that kept running after everyone who understood them was gone.

## What the player should feel

- **Small.** Corporations are incomprehensibly large. Earth Facility #723 is a rounding error in a quarterly report.
- **Watched.** Surveillance is ambient and total. Not threatening. Just present.
- **Expendable.** Not persecuted, just irrelevant. The horror of the facility isn't that the corp wanted the people inside to die. It's that the corp didn't think about them at all.
- **Occasionally awed.** The world is genuinely strange and sometimes beautiful. Neon in rain. Bioluminescent experiments. The deep network, glimpsed.

## The faction dynamic

The Analog and Cyborg paths are ideologically opposed. Analog rejects the machine — flesh that refuses to become obsolete. Cyborg embraces it — pragmatism that crossed the threshold. They distrust each other on principle.

But they share an enemy. The corporation that owns Earth Facility #723 — and everything else — cares about neither side. Analog workers are cheap labor. Cyborg assets are expensive hardware to be depreciated. Both are line items. The corp did not choose a side in the flesh-versus-machine debate. It chose profit.

This makes the factional tension a secondary conflict beneath a shared existential one. The two origins will never like each other. But when the alternative is corporate indifference — the kind that cuts power to a facility and forgets the people inside — the enemy of my enemy is enough. For now.

In practice: safe houses contain both origins coexisting uneasily; cross-origin NPCs are dismissive or suspicious, not hostile; cooperation feels grudging and temporary, never warm.

## Art direction

Stylized, not photo-real. Low-poly meshes carry the silhouette work; high-res PBR textures and realistic dynamic lighting do the surface detail. Hardware budget goes into lighting, not vertex counts.

- **Camera.** Fixed pitch, yaw, and distance — the visual feel of classic isometric, but fully 3D under the hood. Geometry that would obscure the player fades transparent. No rotation, no zoom.
- **Palette.** Dark, desaturated base with neon pops. Teal/cyan dominant, hot pink and red as accent colors. Wet-street reflections on ground surfaces.
- **Lighting carries the world.** Neon signs, explosions, and abilities cast actual light into the environment. The look depends on it; performance discipline around dynamic lights is a first-class concern.
- **Bosses.** Player character is smaller than D2; oversized bosses read clean against that scale.

Class accent colors live in `attribute_state.gd` (`CLASS_COLORS`) — the source of truth for any UI tinting.

## Lighting policy

**Darkness is the default.** Well-lit areas are rare and should feel like relief — psychological, not mechanical. The player learns to associate light with safety, rest, and human presence. That conditioning is built slowly and paid off deliberately.

The darkness has an in-world reason: corporate withdrawal. Power grids failed or were cut. Emergency lighting ran out. Whatever remains is incidental. **Well-lit areas signal one of three things:** someone is still here and wants to be found; someone is still here and doesn't care if they're found; or something is drawing power that shouldn't be.

### Zone lighting tiers

| Tier | Description | Examples |
|---|---|---|
| **Blackout** | No ambient light. Player light source only. | Sub-Level Zero, deep abandoned zones |
| **Failing** | Intermittent flickering institutional lighting. | EF-723 starting zones |
| **Dim** | Low ambient. Functional but oppressive. | Most outdoor and transitional zones |
| **Lit** | Functioning lights, human presence implied. | Safe houses, vendor hubs, key story locations |
| **Relief** | Intentional dramatic lighting — a doorway, a beacon. | End of Sub-Level Zero, key payoff moments |

Most of the game lives in Blackout and Failing. Lit and Relief are used sparingly.

### Light sources

Equippable gear in the dedicated **Recon slot** — never competes with build choices. No mechanical advantage between sources; the choice is stylistic. Each has a beam type (directional / wide / omni), a color, and a reliability profile (steady / intermittent / unstable).

The Enculted's default lamp behaves like the others, with one exception: it occasionally illuminates things that are not there. This is not announced. Players who notice it draw their own conclusions.

## Zones

**Zones are not levels — they are places.** Each zone has a reason to exist that predates the player arriving in it, and evidence of what happened there before they showed up. The zone registry is mostly concept-only today; the only built one is Sub-Level Zero, documented in the [narrative bible](narrative-bible.md#sub-level-zero).

### Level construction

Modular geometry pieces assembled procedurally to simulate a hand-crafted look, with hand-authored rooms (boss arenas, story moments, landmark spaces) slotted in seamlessly. Density scales across the game: early areas are tighter and less dense; end-game environments support Vampire-Survivors-scale hordes.

Architectural notes worth holding onto when designing zones:

- **Crouch tunnels and pit-pillar nav links** are part of the navigation toolkit — enemies use them too. Navmesh `agent_height` must stay synced with enemy `CROUCH_HEIGHT`.
- **Surveillance is ambient.** Cameras, intercoms, and watchful infrastructure should appear without being interactive. The world watches the player — most of the time it doesn't act on what it sees.
- **Lighting profiles drive zone behavior**, not hardcoded constants. Outdoor zones, indoor zones, and ruins all need their own profile.

Code-side architecture: modular builders are done; declarative `LevelGraph` resources are done; full procgen is deferred. New levels should use `LevelGraph` rather than raw `pieces[]`.
