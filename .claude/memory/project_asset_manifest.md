---
name: asset-manifest-at-docs-assets-md
description: "Third-party asset provenance is tracked in docs/assets.md. Every external asset (audio, models, textures) must get a row with source URL and license status before it can ship. Append when the user shares a new asset link."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`docs/assets.md` is the single source of truth for every external asset
shipped with the game — used to compile credits and audit licenses
before any Steam release.

**Why:** assets accumulate over a long playtest cycle. Source URLs go
stale in commit messages and chat history. A consolidated manifest is
the only reliable way to audit "what do we need licenses for" before
the commercial release.

**How to apply:**
- When the user shares a new asset link (YouTube SFX, Blenderkit model,
  Freesound, commercial pack), immediately append a row in the right
  section of `docs/assets.md` with the source URL, intended use, and
  status ⚠️ (TBD license).
- When wiring the asset into the game, fill in the `Files` column with
  the destination paths in `res://resources/audio/...` or wherever it
  lands.
- Do **not** mark anything ✅ unless the user confirms they verified the
  license terms allow shipping in a paid Steam game.
- Existing rows with status ⚠️ for legacy assets (the "Pre-existing /
  provenance unverified" section) need the user to track down sources
  before launch. Flag this in any pre-release readiness audit.

**Categories currently tracked:**
- 3D Models
- Audio — SFX (YouTube extracts)
- Audio — Ambient
- Audio — Pre-existing (provenance unverified)
- Audio — Music

**Status legend** (defined at top of the file):
- ✅ verified, shippable
- ⚠️ TBD — captured but not reviewed
- ❌ confirmed not shippable, must replace
