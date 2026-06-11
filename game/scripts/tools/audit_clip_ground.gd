extends SceneTree
## Measures each locomotion clip's foot-ground contact: min Foot/Toe bone
## world Y sampled across the clip, relative to the skeleton root. A clip
## whose minimum sits higher than idle's reads as "feet floating" in game
## because the character seat is measured under the forced idle pose.
##   godot --headless --path game --script scripts/tools/audit_clip_ground.gd

const CLIPS := [
	&"xbot/idle", &"xbot/pistol_idle", &"xbot/rifle_idle",
	&"xbot/jog", &"xbot/pistol_run", &"xbot/rifle_run",
	&"xbot/strafe_left", &"xbot/strafe_right", &"xbot/walk_back",
	&"xbot/fire", &"xbot/pistol_fire", &"xbot/fire_move",
]


func _init() -> void:
	# Defer past tree activation — node adds in _init aren't in-tree yet
	# (global transforms error with !is_inside_tree()).
	_measure.call_deferred()


func _measure() -> void:
	var ps := load("res://assets/characters/player_analog_male/player_analog_male.fbx") as PackedScene
	var char_root := ps.instantiate() as Node3D
	root.add_child(char_root)
	var skel := _find_skeleton(char_root)
	if skel == null:
		print("NO SKELETON")
		quit()
		return
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	char_root.add_child(ap)
	XBotAnimations.install_on(ap)
	for clip: StringName in CLIPS:
		if not ap.has_animation(clip):
			print("%-24s MISSING" % clip)
			continue
		var anim := ap.get_animation(clip)
		var min_y := INF
		var max_min_y := -INF
		var samples := 24
		for s in samples:
			ap.stop()
			ap.play(clip)
			ap.advance(anim.length * float(s) / float(samples))
			skel.force_update_all_bone_transforms()
			var frame_min := INF
			for b in skel.get_bone_count():
				var bn := skel.get_bone_name(b)
				if not (bn.contains("Foot") or bn.contains("Toe")):
					continue
				var wy := (skel.global_transform * skel.get_bone_global_pose(b)).origin.y
				frame_min = minf(frame_min, wy)
			min_y = minf(min_y, frame_min)
			max_min_y = maxf(max_min_y, frame_min)
		# Hips yaw at mid-clip — a clip authored facing sideways shows
		# here as ±90 vs idle's baseline.
		ap.stop()
		ap.play(clip)
		ap.advance(anim.length * 0.5)
		skel.force_update_all_bone_transforms()
		var hips_yaw := 0.0
		for b in skel.get_bone_count():
			if skel.get_bone_name(b).contains("Hips"):
				var basis := skel.get_bone_global_pose(b).basis
				var fwd := -basis.z
				hips_yaw = rad_to_deg(atan2(fwd.x, fwd.z))
				break
		print("%-24s contact_min=%.3f  highest_contact=%.3f  hips_yaw=%.0f°" % [clip, min_y, max_min_y, hips_yaw])
	quit()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null
