---
name: Verify MP and SP both work for every change
description: Every feature or bug fix must work in both single-player and multiplayer — investigate the host-authoritative + replication implications before declaring done
type: feedback
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
When implementing a feature or fixing a bug, always reason about how it behaves in **both** single-player and multiplayer paths before declaring it done. Don't ship code that only works in SP.

**Why:** Josh is a solo developer who can only test MP with friends sporadically, so MP regressions accumulate silently between playtests. Several patches landed broken in MP because the SP-only path was the only one mentally exercised — enemies replicating, interactables routing RPCs, ID-space confusion (Steam id vs Godot peer id), authority gating, host vs client level-build duplication, etc.

**How to apply:**
- Before writing code, ask: "what runs on the host, what runs on each client, what replicates, what's RPC'd?"
- For host-authoritative state (enemies, world objects), confirm clients receive it via MultiplayerSpawner / MultiplayerSynchronizer / explicit RPCs.
- For client-initiated actions, confirm they route through `@rpc` to the authority and the result fans back out (e.g. interact → request RPC to host → host runs logic → host broadcasts result).
- Watch for ID-space confusion: `multiplayer.get_unique_id()` returns Godot peer ids (1=host); `SteamState.steam_id` and `NetState.lobby_members` keys are Steam ids. Mixing the two breaks owner checks silently. Use `NetState.steam_id_for_peer()` to bridge.
- Watch for level-build duplication: both peers run `LevelBuilder._build_level()` locally; gate dynamic spawns (enemies, pickups) with `NetState.is_client()` returns true → bail.
- For authority gating, the local player on each peer has `is_multiplayer_authority() == true` for its own avatar. Use that check, not `multiplayer.is_server()`, when the question is "is this MY avatar."
- Notifications and HUD updates must target the local-authority player; emitting on a remote avatar delivers to nobody.
- Static geometry (walls, floors, doors-as-nodes) builds locally on each peer and doesn't replicate — but RPCs to those nodes route by NodePath, so deterministic node names are required.

When a fix could plausibly affect MP (anything touching damage, spawning, interactables, inventory, world state) and the user can't immediately test it, call this out in the response so they know to verify on their next playtest.
