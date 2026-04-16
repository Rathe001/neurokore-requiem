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
- 2 classes at launch: **Human** and **Cyborg** (name subject to change).
- Each class has a fully viable **base form** plus **3 specializations** unlocked through specific quests — similar to WoW Legion artifact weapon quests. The unlock quest should feel thematic and personal to the spec.
- Deep build diversity per class, with itemization designed to create build desire — finding an item should make you want to try a new build.
- **Base class resource system:** the base (unspecced) form of each class runs all 3 resource meters simultaneously. The early skill tree includes one skill tied to each resource, naturally introducing the player to each spec's mechanics through play. When a spec is chosen, the player commits to that resource exclusively — the other two meters disappear from the UI. This makes specialization feel like a meaningful threshold, not just a menu choice. The base class remains viable through breadth: access to all three resource types and their associated skills, without the depth a specialized build achieves.
- **Character creation:** players choose male or female at the start. Both are fully supported for all classes and specs. This effectively doubles the required player character sprites — a scope consideration for production and a factor in tech stack decisions around animation systems.

---

### Cyborg

A human who has traded flesh for machine. The further down the path, the less human they become.

**Base resources:** Power Grid + Bandwidth + Memory/CPU — all three run simultaneously. One early skill is tied to each, introducing the player to each spec's flavour. Specialization locks in one resource and drops the other two.

#### Specializations

**Forged** *(melee)*
- Fantasy: sell nearly all remaining humanity for raw mechanical power. Extra limbs, chassis upgrades, heavy attachments.
- Resource: **Power Grid** — a power *budget*, not a pool. Each augmentation has a draw cost. You manage what's active simultaneously.
- **Overclock:** push past grid capacity for burst power at the risk of brownout or shutdown.
- Items that increase grid capacity or reduce draw costs are major build-enablers.

**Automaton** *(mid-range)*
- Fantasy: command the machine through AI scripting and a fleet of drones. Set conditions, automate responses, build a system that fights alongside you.
- Resource: **Bandwidth** — caps how many drones/scripts can run simultaneously.
- **Drones are the physical expression of scripts** — each script runs on a drone. The drone type determines what the script can do. Losing a drone means losing that script until redeployed.
- **Scripts are loot items** — each defines a condition/response pair (e.g. `IF surrounded by 3+ enemies → shockwave`). Finding a new script reshapes your build.
- **Drone chassis and components are also loot** — drone items + script items together define the build. Finding a rare drone blueprint is the equivalent of a D2 runeword enabler.
- **Script decay → drone damage** — scripts degrade because drones take damage in combat. You're actively managing a fleet under fire.
- **Overflow/crash:** running too many scripts/drones risks cascade failure. High risk, high reward ceiling.

*Drone types (ideas, TBD):*
- **Combat drones** — offensive, prioritize targets
- **Swarm drones** — large numbers of small, weak micro-drones. Fits end-game horde scale.
- **Shield drones** — orbit the player and intercept incoming projectiles
- **Repair drones** — sustain and healing utility
- **Recon drones** — extend vision range, reveal enemies, mark targets
- **EMP/Hack drones** — disable enemy augmentations or temporarily take control of enemies

*Open questions:*
- Permanent companions vs. deployed/recalled on demand?
- Is there a default starter drone, or is the fleet built entirely through loot?
- Visual style of drones: sleek corporate hardware, cobbled junk drones, or something more organic/grotesque?

**Polymath** *(ranged)*
- Fantasy: augment the mind beyond human limits. The body is just a platform for expanded cognition.
- Resources: **Memory** and **CPU** — two distinct axes.
  - **Memory:** how many abilities are loaded at once. Swapping loadouts is the strategic layer.
  - **CPU:** determines cast speed, cooldown, and the complexity of spells you can execute. Higher CPU unlocks higher-tier abilities.
- **Fragmentation:** memory degrades mid-combat over time, making abilities unreliable until a defrag is performed. Fits the body-horror tone.

---

### Human

Unaugmented. In a world that sells upgrades on every corner, the Human refused — or never had the choice. Their power comes from what the Cyborg cut away.

**Base resources:** Adrenaline + Composure + Sanity — all three run simultaneously. One early skill tied to each. Specialization locks in one and drops the other two.

#### Specializations

**Survivalist**
- Fantasy: adaptability and improvisation. Thrives in chaos, uses scavenged gear and jury-rigged weapons. Gets stronger as conditions get worse.
- Resource: **Adrenaline** — builds under pressure, decays when safe. Rewards aggressive, risky play.

**Gentleman / Lady** *(title reflects character gender)*
- Fantasy: discipline, composure, old-world refinement. Refused augmentation on principle and became dangerous through mastery instead. Precise, methodical — dueling, marksmanship, controlled aggression.
- Resource: **Composure** — maintained through deliberate, controlled play. Breaks under panic, chaos, or sustained damage. High skill ceiling for staying calm under fire.

**Enculted**
- Fantasy: tapped into something ancient living in the network. The augmentations that make the Cyborg powerful are blocking signals the unmodified mind can receive. Unstable, dangerous power with a horror edge.
- Resource: **Sanity** — depletes as occult abilities are used. Push too far and the character becomes dangerous to everything, including themselves.

---

## Spec-Specific Monster Variants

Certain enemies have spec-specific variants — different forms of the same base threat that are tuned to the player's class and spec. The world shapes itself around what threatens *you* specifically. These variants may interact directly with the spec's resource system (e.g. a Software Bug corrupting Automaton scripts, Nanobytes draining the Forged's Power Grid, an Unbeliever suppressing the Enculted's Sanity abilities).

| Class | Spec | Monster Variant | Threat Type |
|---|---|---|---|
| Cyborg | Base | Caustic Beetle | Biological — corrodes hardware |
| Cyborg | Forged | Swarm of Nanobytes | Nano-mechanical |
| Cyborg | Automaton | Software Bug | Digital entity |
| Cyborg | Polymath | Hallucination | Cognitive — generated by the augmented mind itself |
| Human | Base | Wraith | Supernatural — drawn to unshielded minds |
| Human | Survivalist | Irradiated Spider | Biological/environmental |
| Human | Gentleman / Lady | Heathen | Ideological — chaos against order |
| Human | Enculted | Unbeliever | Ideological/spiritual — actively suppresses occult power |

Spec variants **stack** with the standard enemy — both types appear in the same encounter. The base encounter is always the foundation; your spec adds a personal layer of threat on top.

**Multiplayer implication (multiplayer TBD):** in a mixed party, all active spec variants spawn simultaneously. A party of Survivalist + Automaton + Enculted would face irradiated spiders, software bugs, and unbelievers in the same fight. Party composition becomes a tactical decision beyond skill synergies — each member brings their own threat layer into every encounter.

---

## Dialog & UI

- **Portraits:** Animated pixel art portrait busts for NPCs, enemies, and quest-givers — in the style of Bard's Tale 1. Simple animation loops (blinking, mouth movement, class/corruption-specific effects).

---

## Status

Early design phase. Tech stack TBD — will be chosen to fit the game's requirements.

---

## License

MIT — see [LICENSE](LICENSE) for details.
