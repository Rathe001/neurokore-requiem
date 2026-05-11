---
name: Multiplayer architecture plan
description: Coop PvE multiplayer via Steam P2P. Phases 0/1A/1B/2A/2B shipped. Phase 2C (cleanup) is next. Full plan + per-phase commit refs in docs/multiplayer.md.
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
**Read `docs/multiplayer.md` first** — that's the source of truth and lives in the repo, so it survives across machines. This memory file is just a quick orientation for resumed sessions.

**Stack:**
- GodotSteam GDExtension 4.18.1 (installed at `game/addons/godotsteam/`, sourced from Codeberg — the GitHub repo is archived). Provides Steam SDK + `SteamMultiplayerPeer` + Stats / Cloud in one package. We originally agreed on `godot-steam-multiplayer-peer` (Expressobits) but its upstream paused in Dec 2025; we switched at install time.
- Two autoloads: `SteamState` (SDK init + `Steam.run_callbacks()` per frame) and `NetState` (lobby + peer lifecycle + chat + start_game flow).
- App ID 4689320, `steam_appid.txt` at `game/` root.

**Phase status (2026-05-08):**
- ✅ Phase 0 — GodotSteam install + autoload foundation (`5a64928`)
- ✅ Phase 1A — Lobby plumbing in NetState (`1926fb6`)
- ✅ Phase 1B — Lobby UI (4 panels + startup_screen wiring) (`a00b429`)
- ✅ Phase 2A — Networked transport + scene transition (`2bebf03`)
- ✅ Phase 2B — Per-peer player avatars + position sync (`efe84b4`)
- 🔜 **Phase 2C — Cleanup. NEXT UP.**
- 📅 Phase 3 — Enemies (host-authoritative + RPC damage)
- 📅 Phase 4 — Combat events (projectile / hitscan / impact bursts)
- 📅 Phase 5 — Loot system (instanced + manual-drop sharing)
- 📅 Phase 6 — World state (level transitions + door/switch sync)
- 📅 Phase 7 — Drop-in coop (mid-session join handshake)

**Phase 2C scope** (per `docs/multiplayer.md`):
- Mid-game disconnect: peer drops → despawn avatar (already wired in PlayersContainer); audit no leftover refs in HUD / target locks; add a notification.
- Quit-to-menu from MP: `main_menu.gd._on_quit_to_menu_pressed` already calls `NetState.leave_lobby()`. Audit it actually nulls `multiplayer.multiplayer_peer` on every machine and other peers see the leave.
- Defensive guards on remote players: `take_damage` / `_die` / `respawn` aren't gated on `_is_remote_player()` yet. Add early-returns so stray gameplay calls don't NPE on a null `_combat`.
- Despawn animation polish (defer to Phase 3+ if too much).
- Reconnection (nice-to-have, defer if significant).

**Critical gotcha to remember:** `multiplayer.has_multiplayer_peer()` is **NOT** a reliable SP/MP discriminator — GodotSteam plumbing leaves it set in SP. Always use `NetState.is_in_lobby()`. This bit us in Phase 2B and the `_is_remote_player()` helper in `prototype_player.gd` + the `PlayersContainer._ready` branch already gate on NetState. Future networked code should follow the same rule.

**Local two-instance testing:**
- Editor (host) + a debug-export `.exe` launched with `--mp-force-client` (the .exe is in `build/windows/`, rebuild via `Godot --headless --path game --export-debug "Windows Desktop" build/windows/neurokore-requiem.exe`).
- This validates: lobby flow, scene transitions, avatar spawn on both ends.
- This does NOT validate: actual cross-peer P2P traffic. Steam routing same-Steam-id-to-itself is undefined. Position sync, RPCs, member-join callbacks for distinct peers all need real two-account testing or playtest deployment.

**Class-variant monsters in MP:** deferred — not a launch feature.

**How to apply (resumed sessions):** When designing new networked behaviour, ask "what's authoritative on the host vs. predicted on the client?" Damage / AI / loot / world state always host. Visuals can be client-side. For SP/MP detection, use `NetState.is_in_lobby()` not `multiplayer.has_multiplayer_peer()`. New replicated entities need their authority + sync frequency decided up front (don't retrofit).
