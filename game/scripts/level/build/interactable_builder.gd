extends RefCounted
class_name InteractableBuilder
## Spawns the interactable scenes declared on a RoomDef.slots array and
## registers each instance in ctx.slots under "{room_id}.{slot_id}" so the
## puzzle layer (and anything else) can look them up by name.

static func spawn_slots(ctx: LevelBuildContext, room_id: StringName, center: Vector3, rd: RoomDef, extras: Array[InteractableSlot] = []) -> void:
	_spawn_list(ctx, room_id, center, rd.slots)
	if not extras.is_empty():
		_spawn_list(ctx, room_id, center, extras)


static func _spawn_list(ctx: LevelBuildContext, room_id: StringName, center: Vector3, slots: Array[InteractableSlot]) -> void:
	for slot: InteractableSlot in slots:
		if slot == null or slot.scene == null:
			push_warning("[InteractableBuilder] Room '%s' has a slot with no scene; skipping." % room_id)
			continue
		# Early dedup. The previous "later instance wins" warning fired in
		# every build because procgen often adds slots in both rd.slots and
		# piece.additional_slots — the orphaned instance would still get
		# instantiated, added to the scene tree, AND queue_freed implicitly
		# by Godot when ctx.slots[key] = inst overwrote the reference,
		# leaving a leaked dangling Node3D until next frame. Check first,
		# skip the whole instantiate path on duplicates.
		var key := StringName("%s.%s" % [room_id, slot.id])
		if ctx.slots.has(key):
			continue
		var inst := slot.scene.instantiate() as Node3D
		if inst == null:
			push_error("[InteractableBuilder] Slot '%s' scene didn't instantiate to a Node3D." % slot.id)
			continue
		inst.transform.origin = center + slot.offset
		if slot.rotation_y != 0.0:
			inst.rotation_degrees.y = slot.rotation_y
		# Deterministic name keyed on (room_id, slot.id) so the same node lives at
		# the same NodePath on host AND client. Required for @rpc methods on
		# interactables — Godot routes RPCs by path, and Godot's auto-@N suffix
		# rename can drift between peers if iteration order isn't byte-identical
		# (which it usually is, but we don't want to bet a P0 MP bug on it).
		inst.name = _slot_node_name(room_id, slot.id)
		ctx.root.add_child(inst)
		ctx.slots[key] = inst


# Build a Godot-safe deterministic node name from the slot key. Strips the
# few characters Godot rejects in node names (`/` `:` `@` `.`) and replaces
# them with `_`. Keeps the rest readable in the editor.
static func _slot_node_name(room_id: StringName, slot_id: StringName) -> String:
	var raw := "Slot_%s_%s" % [room_id, slot_id]
	return raw.replace("/", "_").replace(":", "_").replace("@", "_").replace(".", "_")
