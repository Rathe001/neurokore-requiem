---
name: Resource loaders must use explicit paths, not DirAccess
description: DirAccess directory enumeration over res:// is unreliable in exported Godot 4 builds — silent failures look like "system X does nothing in Steam build but works in editor." Always use ResourceLoader.exists() with explicit file lists.
type: feedback
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
**Rule:** Never use `DirAccess.open(res_path).get_files()` or `dir.list_dir_begin()` to enumerate `.tres` files in `res://`. Use `ResourceLoader.exists(path)` with an explicit list of file paths instead.

**Why:** In exported Godot 4 builds, `.tres` files exist as packed resources but the directory listing returns empty. The same code that works in the editor returns an empty array in the export. This silently empties resource pools and produces "feature X does nothing" bug reports that are hard to diagnose because nothing crashes — the lookup just yields zero hits.

**How to apply:**
- For each-by-name lookups: prefer `AttributeState.CLASS_TO_STAT` (or similar) to enumerate the keys, then build paths via `f"{DIR}{key}.tres"`. See `talent_state.gd._load_trees()` and `perk_state.gd._load_ladders()` for the pattern.
- For flat lists: maintain a `const FILES: Array[String]` next to the loader. See `monster_affix_table.gd` (`AFFIX_FILES`) and `named_monster_table.gd` (`NAMED_FILES`). Adding a new resource = drop the file + add one line.
- Both `PerkState` and `TalentState` `push_warning` if their pool ends up empty after load — surface checks for the next class of silent-load bug.

**Diagnostics:** If a player reports "talents do nothing" / "no rare-pack monsters" / "named bosses never spawn" / "perks aren't unlocking," check the loader pattern first. The fix is mechanical (swap the enumeration for an explicit list).

**Hit it twice already:** v0.1.1 hotfix on 2026-05-06 fixed `PerkState`, `MonsterAffixTable`, `NamedMonsterTable`. `TalentState` was already on the explicit-path pattern from an earlier fix. Any new directory-of-resources system should start with the explicit list, not the dir scan.
