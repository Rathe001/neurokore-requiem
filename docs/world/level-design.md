# Level Design

## Construction

- **Tile-based procedural generation** — tiles and layouts simulate a hand-crafted look.
- **Hand-crafted rooms** — specific events, boss arenas, story moments, and landmark rooms are hand-crafted but slot seamlessly into procedurally generated levels.
- **Density progression** — early areas are tighter and less dense. End-game environments support Vampire Survivors-scale hordes.

---

## Surveillance Atmosphere

The world is watched. Surveillance infrastructure is ambient and total — not threatening, just present. No one is on the other end. The system is still running because no one turned it off.

This is a tone mechanic, not a gameplay mechanic. Surveillance elements never punish the player, cannot be meaningfully disabled, and do not affect combat or stealth. Their purpose is to make the player feel observed and irrelevant simultaneously.

### Elements

**Surveillance cameras** — mounted on walls and ceilings, rotate to physically follow the player as they move through a zone. The acknowledgement without reaction is the point.

**Dead monitors** — screens displaying a grainy feed of the player's current position. The log goes nowhere. The feed has no audience.

**Automated scan beams** — sweep patterns the player passes through with no consequence. The scanner registers them, records them, does nothing with the data.

**Tracking drones** — hover units that maintain observation distance without engaging. Not guards. Observers. May drift away after a period without reacting.

### Zone Variation

In active corporate zones, surveillance feels dense and functional — everything works, everything watches. In abandoned zones, cameras still rotate but some are stuck mid-pan, some face walls, some flicker. The decay makes it more unsettling: the infrastructure outlasted the people who built it and still doesn't care that you're there.

### Performance Constraints

Surveillance elements must not add meaningful overhead in horde-density zones:

- **Frustum culling** — off-screen cameras do not update. Only visible cameras rotate.
- **Stepped rotation** — cameras snap to a new angle every few frames rather than updating continuously. Cheaper, and more authentically CCTV-like.
- **Fixed observation radius** — cameras only track the player within a set distance; idle outside it. Limits active cameras to a small subset at any time.
- **Static monitor textures** — dead monitors use a render texture baked on room entry, not a live feed. Same visual effect, near-zero runtime cost.
- **Drone reuse** — tracking drones share movement logic with existing enemy AI (maintain distance, no combat state). No separate system required.
