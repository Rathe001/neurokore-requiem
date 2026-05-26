# Art Reference Bible — Neurokore: Requiem (2D iso rework)

This folder is the visual-style lock for the 2D iso pivot. Every sprite
gen, every tile gen, every UI element should pass the "does it sit
cleanly next to these 24 images" test.

The goal style: **hand-painted 1996-2000 ARPG**, dimetric iso (~26.5°,
2:1 tile ratio), gritty body-horror cyberpunk tone, complementary-color
lighting (red+teal / orange+cyan), heavy baked shadows. Imagine
Diablo 2 made by the Sanitarium team with a Crusader: No Remorse art
direction nudge.

What it is NOT: clean 3D-rendered hero shots on floating platforms,
modern indie 3D-character polish, painterly-but-bright JRPG vibes.
Nine drift-style images were generated and deleted earlier in this
session — if future gens look like those (isolated character on black
background with neon platform, "League key art" lighting), the prompt
needs the painted-style anchors below.

## Midjourney prompt locking

The painted aesthetic in this bible was locked using the file with
prefix `httpss.mj.run1Lz-I0yhrNI_` as the reference image — that
reference URL (or one anchored on the soldier sprite `374b6a95`)
should be the `--sref` source for all future gens. If MJ rejects
`--sref`, try `--oref` or inline URL at prompt start.

**Always-include negative prompts:**

> NOT 3D rendered, NOT clean polish, NOT modern indie style, NOT
> isolated on black background, NOT floating platform hero shot

---

## Environments (11 images)

Painted iso scenes. Use as `--sref` style anchors for tile / room
generation. Each one suggests a theme variant for procgen levels.

### Primary references (use these first)

- **`larg_aaec3751..._3.png`** — Crimson sanctum corridor. Two figures
  with rifles approaching a red-glow shrine room. **The single best
  reference in the set** — character scale visible, dramatic lighting
  that doesn't fight gameplay readability, perfect D2 iso angle. Anchor
  for "sub-level / sanctum / dungeon" theme.

- **`Diablo_2_..._low_light_bas_5b7251e8..._2.png`** — Sanitarium dome
  with stairwells and warm light through grates. Single tiny figure
  shows character scale at iso. Closest framing to actual D2 dungeon
  composition. Anchor for "facility interior / dome / industrial
  silhouette" theme.

- **`Sci_Fi_..._huma_80349311..._3.png`** — Asylum cell with table,
  vault door, grates. Lowest visual noise of any reference — entities
  would read cleanly against this. Anchor for "personal quarters /
  cell / interior" theme.

### Secondary references

- **`Diablo_2_..._high_tech_pri_b44f4cb2..._1.png`** — Infernal forge
  with blue stone + molten orange pipes + grate floors. Anchor for
  "danger biome / boss arena / hot biome."
- **`Sci_Fi_..._alie_649857a0..._0.png`** — Red neon street with
  lamp + characters. Anchor for "outdoor / transition / town hub."
- **`Sci_Fi_..._land_1e0aab5f..._3.png`** — Cyberpunk street with
  CRN neon sign + single figure at scale. Strong gameplay readability.
  Anchor for "outdoor industrial street."
- **`Sci_Fi_..._land_ef2070d9..._2.png`** — Boiler dome with vault
  door, red/teal accents. Anchor for "industrial set piece /
  destructible reactor / boss room."

### Tertiary / atmosphere references

- **`Sci_Fi_..._larg_aaec3751..._2.png`** — Cyberpunk Victorian
  street with "BURN" sign. Slightly drifts toward 2010s indie
  aesthetic; use sparingly.
- **`Sci_Fi_..._awe_474b8775..._1.png`** — Green-tinted abandoned
  lab. Very busy / cluttered; entity readability suffers against it.
  Use for "depths / forgotten zone" only.
- **`isometric_..._bloody_room_..._c5f4310f..._0.png`** — Blood-
  soaked lab with skulls + monitors. Tone is bang-on but unbuildable
  as gameplay tiles. Use as "post-fight / encounter aftermath" mood ref.
- **`isometric_..._1990s_..._chaos_50_..._30c97468..._3.png`** — BQB
  bed / personal quarters with neon sign. Flavor piece. Anchor for
  "NPC quarters / vendor room / safe zone."

---

## Player characters (7 images)

All painted style, all suitable as canonical class refs for the
bake-3D-to-2D sprite pipeline.

### Anchor reference (use as `--sref` for all char gens)

- **`Diablo_2_..._character_sprite_sci-fi_sol_374b6a95..._0.png`** —
  Male soldier with spiked shoulder pad and gun, embedded in library/
  forge. **The original painted-style anchor.** Use this as the
  reference URL for every future character gen.

### Class archetype suggestions

| Image | Visual read | Suggested class fit |
|---|---|---|
| `httpss.mj.run1Lz_..._3e664f7a..._0.png` | Male soldier with rifle, red alley | **Analog — Ranged combat** |
| `d9be6241..._0.png` | Character in red/black armor, red neon room | **Analog — Heavy** |
| `548d68af..._1.png` | Female with backpack + sash, red trim | **Analog — Pilot/scavenger** |
| `0ffb09b8..._3.png` | Bipedal mech with leg cannons | **Cyborg — Heavy combat variant** |
| `d009b01a..._0.png` | Humanoid mech on launchpad with "D" neon | **Cyborg — Alt loadout** |
| `7b2c00af..._0.png` | Female in red armor with cyan energy blade | **Polymath / Enculted — Techno-mage** |

The 4-6 distinct class archetypes here cover most of the design's
class identity space. Mapping to `docs/classes.md`:

- **Analog generalist + 3 specs** → use the soldier/heavy/pilot refs
- **Cyborg generalist + 3 specs** → use the mech refs
- **Polymath / Enculted** → use the techno-mage ref

---

## Monsters (6 images)

All painted style. Body-horror set is the strongest material in the
bible — use these as the foundation for enemy concept work.

### Body horror tier (primary monster refs)

- **`body_horror__082e8344..._3.png`** — Red parasite/crab humanoid
  with cables, near a green CRT terminal. **Anchor for "amalgamation
  / biomechanical fusion" enemies.** Body horror + sci-fi + scale all
  in one frame.
- **`body_horror__48fb5483..._3.png`** — Red walker mech with cannon
  legs facing a small character. **Anchor for "boss / elite walker"
  enemies.** Scale-via-tiny-figure framing is exemplary.
- **`body_horror__b9502765..._3.png`** — Pale humanoid with mechanical
  arms, perched, red eyes. **Anchor for "elite stalker / leaper"
  enemies.** Body horror without losing silhouette legibility.
- **`body_horror__ce70019d..._1.png`** — Vampire-faced body horror
  humanoid crouched near red neon symbol. **Anchor for "feral
  cultist / Enculted enemy"** matching the narrative bible's reps.

### 1980s sci-fi tier (set-piece monster refs)

- **`1980s_sci_fi_e09a1316..._1.png`** — Giant mech-spider with laser
  arm and umbrella plating, character at scale beside it. **Anchor
  for "boss / mini-boss / heavy walker"** encounters.
- **`1980s_sci_fi_868d172e..._0.png`** — Bedroom scene with red bed +
  small character + huge green werewolf silhouette. **Compositionally
  ambiguous** — read this as a *scene/encounter mood ref* rather than
  a single-monster sprite ref. Useful for "haunting encounter" setup.

---

## Gaps to fill before vertical slice starts

| Asset class | Target count | Notes |
|---|---|---|
| Item icons | 8-12 references | D2-style inventory grid icons. Hand-painted weapons, armor pieces, consumables, "rune" / chip items. Square frames, baked lighting on the icon, dark background. |
| UI frames | 4-6 references | D2 stone-bordered panel art. Status bars, inventory grid frame, skill tree node art, tooltip background. |
| VFX refs | 6-8 references | Spell impacts, muzzle flashes, hit-flash bursts, explosions — all in the painted aesthetic. "Frame from an attack animation, painted style, embedded in environment." |

Once those land we have the full bible and can spec the vertical slice.

---

## File naming pattern

All files share the prefix `Rathe001_` (Midjourney user identifier).
The descriptive segment after that captures the original prompt; UUID
+ index at the end disambiguates within a batch. Don't rename — the
URL pattern matters for re-referencing from Midjourney.

If a future bible needs a tag attached to a file (e.g., "this is the
locked anchor"), add a sidecar `.txt` rather than renaming the .png.
