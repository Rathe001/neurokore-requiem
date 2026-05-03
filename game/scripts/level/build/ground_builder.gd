extends RefCounted
class_name GroundBuilder
## World-bottom catcher and kill zone. No global floor plane — each room and
## corridor builds its own floor (so pits are possible). The catcher prevents
## stray physics objects from falling forever; the kill zone catches anything
## that drops off a ledge.

static func build(ctx: LevelBuildContext) -> void:
	var w := ctx.layout.ground_size.x + 40.0
	var d := ctx.layout.ground_size.y + 40.0

	var bottom := StaticBody3D.new()
	bottom.name = &"WorldBottom"
	bottom.input_ray_pickable = false
	var bs := CollisionShape3D.new()
	bs.shape = BoxShape3D.new()
	(bs.shape as BoxShape3D).size = Vector3(w, 1.0, d)
	bs.position.y = -20.0
	bottom.add_child(bs)
	ctx.root.add_child(bottom)

	# Backup kill zone — sits BELOW the deepest pit (bottomless = 10m deep)
	# so anything that somehow tunnels past the per-pit kill areas (or falls
	# off geometry that isn't a pit) still gets caught. PitBuilder creates
	# per-pit kill areas at each pit's actual depth so the player visibly
	# falls to the bottom before dying. Mask is all-bits so the area catches
	# bodies on every layer — without this, the player (layer 4) silently
	# slips past the area and lands on the WorldBottom catcher, where LoS
	# rays at their Y skim under the floors and every enemy shoots them
	# through it.
	var kill := Area3D.new()
	kill.name = &"KillZone"
	kill.collision_mask = 0xFFFFFFFF
	var ks := CollisionShape3D.new()
	ks.shape = BoxShape3D.new()
	(ks.shape as BoxShape3D).size = Vector3(w, 8.0, d)
	# Top of the zone at y = -16 (well below the bottomless pit's 10m depth
	# so the per-pit areas always trigger first).
	kill.position.y = -20.0
	kill.add_child(ks)
	kill.body_entered.connect(func(body: Node) -> void:
		if body.has_method(&"take_damage"):
			body.take_damage(9999, Vector3.ZERO, 0.0)
	)
	ctx.root.add_child(kill)
