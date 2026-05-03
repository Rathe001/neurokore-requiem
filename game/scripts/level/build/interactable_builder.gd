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
		var inst := slot.scene.instantiate() as Node3D
		if inst == null:
			push_error("[InteractableBuilder] Slot '%s' scene didn't instantiate to a Node3D." % slot.id)
			continue
		inst.transform.origin = center + slot.offset
		if slot.rotation_y != 0.0:
			inst.rotation_degrees.y = slot.rotation_y
		ctx.root.add_child(inst)

		var key := StringName("%s.%s" % [room_id, slot.id])
		if ctx.slots.has(key):
			push_warning("[InteractableBuilder] Duplicate slot key '%s'; later instance wins." % key)
		ctx.slots[key] = inst
