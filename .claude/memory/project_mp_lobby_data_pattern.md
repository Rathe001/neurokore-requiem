---
name: mp-lobby-data-pattern
description: Pattern for replicating per-character metadata to other peers in coop — publish via Steam.setLobbyMemberData, read via getLobbyMemberData, listen for lobby_data_update to refresh late arrivals.
type: project
---

**The problem.** Remote-peer Player nodes need to render with their PEER's character data (gender, class, name, etc.), not the LOCAL player's. Reading `PlayerState.gender` on a remote `PrototypePlayer` returns the local player's gender — that's only the right answer for the avatar the local user controls.

**The pattern** (proven for gender in v0.4.1 — generalizes to any per-character metadata):

1. **Publish to the gameplay lobby** on join/create. Each peer writes their own data via `Steam.setLobbyMemberData(lobby_id, KEY, value)`. Steam replicates the string to every other member automatically — no custom RPC needed.
   - Code lives in `gameplay_chat_state.gd` `_publish_self()`. Wired to `NetState.lobby_created_result` + `lobby_joined_result`.

2. **Read on demand** via a registry-style helper. Map Godot peer id → Steam id → call `Steam.getLobbyMemberData(lobby_id, steam_id, KEY)`.
   - `GameplayChatState.gender_for_peer(peer_id)` is the reference example. Returns the StringName-typed value with a safe default.
   - `NetState.steam_id_for_peer(peer_id)` is the bridge — handles host (peer_id=1 → lobby_owner_id) and clients (delegates to `peer.get_steam_id_for_peer_id`).

3. **Cache on the spawned Player node** for fast access from per-frame code:
   - Add a field like `remote_gender: StringName = &""` on `PrototypePlayer`.
   - `PlayersContainer._spawn_for(peer_id)` sets it BEFORE `add_child` so `_ready_remote` reads the right value on first render: `player.remote_gender = GameplayChatState.gender_for_peer(peer_id)`.
   - Local/SP path leaves the field empty so `PlayerState.{field}` wins.

4. **Refresh on late data** via `Steam.lobby_data_update` signal. The data may arrive AFTER the remote Player spawned (peer joined first, published their data second). PlayersContainer connects:
   ```gdscript
   Steam.lobby_data_update.connect(_on_lobby_data_update)
   ```
   The handler walks already-spawned remote players and calls a `refresh_remote_gender(new_gender)` method that re-applies the appearance only if the value changed (no-op shortcut).

**Why this pattern over RPC:**
- Zero custom RPC plumbing — Steam handles replication.
- Late joiners get the existing data automatically when they enter the lobby; no "sync on join" code needed.
- Persistent across reconnects — Steam keeps member data until they leave.
- Works the same for any string-valued metadata.

**Constraints:**
- Member data is STRING typed. Bool encodes as "0"/"1"; enums as their identifier; numbers via str()/int().
- Keys must be plain `String` (not StringName) when passed to `setLobbyMemberData` / `getLobbyMemberData`.
- Don't use this for high-frequency state (HP, position, etc.) — that's MultiplayerSynchronizer's job. Lobby member data is for character identity that changes at most a few times per session.

**Where the gender example lives end-to-end** (use as template for any new per-peer field):
- `gameplay_chat_state.gd:GENDER_KEY` constant + publish in `_publish_self()` + `gender_for_peer(peer_id)` helper.
- `prototype_player.gd:remote_gender` field + `refresh_remote_gender()` public method + branch in `_apply_gender_appearance()` that prefers `remote_gender` over `PlayerState.gender`.
- `players_container.gd:_spawn_for()` sets it pre-add_child + `_on_lobby_data_update` listener.
