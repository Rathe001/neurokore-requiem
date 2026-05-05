class_name EffectFormatter extends RefCounted

## Renders per-class live-effect bullet lines for the buff tooltip.
## stat_id uses the legacy 3-letter tree IDs (ort/ing/amb/dev/opt/cla)
## that perk .tres files still carry. Each match arm produces short
## lines — one mechanic each. Lines are skipped when their value is
## zero so unallocated talents don't leave stale rows.


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
				var dmg_mult := 1.0  # placeholder — will use gear bonus when implemented
				var per_tick: float = dot * dmg_mult
				var dps: int = int(round(per_tick / PlayerDoomsayer.DOOMSAYER_TICK_INTERVAL))
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
