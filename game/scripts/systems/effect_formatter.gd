class_name EffectFormatter extends RefCounted

## Renders the per-stat live-effect bullet lines that show up in the
## buff tooltip (and any future surface that wants to summarise what a
## perk + its talent stack are actively doing). One place to update
## when a new effect kind needs a tooltip line — the HUD just calls
## buff_lines_for_stat and never has to know the spec details.
##
## Convention: each match arm produces SHORT lines (one mechanic each).
## Headline live counter first (X/Y of whatever the spec grants), then
## stat-scaling or talent-gated effects under it. Lines are skipped
## when their underlying value is zero so an unallocated talent doesn't
## leave a stale row.
##
## All methods are static; PerkState / TalentState / Effects /
## InventoryState / SlotRegistry / AttributeState / PlayerState are
## autoloads so they resolve from any context.


## Returns the bullet lines (no leading bullet glyph) to render under
## the perk description in the buff tooltip. `player` may be null
## during early init or in tooling — count-based lines are skipped
## gracefully in that case.
static func buff_lines_for_stat(stat_id: StringName, player: PrototypePlayer) -> Array[String]:
	var lines: Array[String] = []
	match stat_id:
		&"amb":
			if player != null:
				lines.append("%d/%d followers" % [player.get_charm_count(), player.get_charm_max()])
			var dot: float = TalentState.get_aggregate(&"doomsayer_dot_per_tick")
			if dot > 0.0:
				var dmg_mult := AttributeState.get_player_damage_mult(PlayerState.class_id, PlayerState.spec_id)
				var per_tick: float = dot * dmg_mult
				var dps: int = int(round(per_tick / PrototypePlayer.DOOMSAYER_TICK_INTERVAL))
				lines.append("Aura of Dread: %d dps aura" % dps)
		&"ing":
			if player != null:
				lines.append("%d/%d traps active" % [player.get_trap_count(), player.get_trap_max()])
		&"opt":
			if player != null:
				var drones := player.get_drone_count()
				if drones > 0:
					lines.append("%d %s orbiting" % [drones, "drone" if drones == 1 else "drones"])
		&"dev":
			var unlocked := InventoryState.get_extra_weapon_slot_count()
			if unlocked > 0:
				var filled := 0
				for i in unlocked:
					if InventoryState.get_equipped(SlotRegistry.EXTRA_WEAPON_SLOTS[i]) != null:
						filled += 1
				lines.append("%d/%d extra weapons equipped" % [filled, unlocked])
		&"cla":
			var bolts := int(round(Effects.get_aggregate(&"telekinesis_bolts")))
			if bolts > 0:
				lines.append("%d %s per trigger" % [bolts, "bolt" if bolts == 1 else "bolts"])
		&"ort":
			var pct := Effects.get_aggregate(&"exile_curse_damage_pct")
			if pct > 0.0:
				lines.append("Cursed enemies take +%d%% damage" % int(round(pct)))
	return lines
