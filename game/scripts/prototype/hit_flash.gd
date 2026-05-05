extends RefCounted
class_name HitFlash
## Brief red overlay applied to every MeshInstance3D under a target Node3D
## when it takes damage. Uses GeometryInstance3D.material_overlay so the
## base materials stay untouched and we can clear the effect by nulling a
## single property per mesh.

const FLASH_COLOR := Color(1.0, 0.18, 0.18, 0.7)
const HEAL_COLOR := Color(0.30, 1.0, 0.45, 0.7)
const FLASH_DURATION := 0.18

## Apply the flash to all meshes under `root`, fading to transparent over
## FLASH_DURATION. Pass the previous tween (if any) so a fresh hit cancels
## a still-fading prior flash cleanly. Returns the new tween so the caller
## can store it for the next call. `host` owns the tween lifecycle.
static func play(host: Node, root: Node3D, prior: Tween = null, color: Color = FLASH_COLOR) -> Tween:
	if root == null:
		return null
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	if meshes.is_empty():
		return null

	# Clear any prior overlay before reapplying — a stacked hit lands before
	# the prior tween's `finished` cleanup runs, so nulling here guarantees
	# we never leak a stale overlay onto the meshes.
	for m in meshes:
		m.material_overlay = null
	if prior != null and prior.is_valid():
		prior.kill()

	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = color
	overlay.disable_receive_shadows = true
	for m in meshes:
		m.material_overlay = overlay

	var tween := host.create_tween()
	tween.tween_property(overlay, "albedo_color:a", 0.0, FLASH_DURATION)
	tween.finished.connect(func() -> void:
		for m: MeshInstance3D in meshes:
			# `material_overlay == overlay` guards against another flash having
			# replaced the overlay between this one starting and finishing.
			if is_instance_valid(m) and m.material_overlay == overlay:
				m.material_overlay = null
	)
	return tween


static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)
