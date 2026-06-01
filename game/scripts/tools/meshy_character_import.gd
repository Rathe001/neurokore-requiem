@tool
extends EditorScenePostImport

# Post-import fixup for Meshy character FBXs.
#
# Meshy exports an FBX whose materials reference textures by Mixamo's
# `/tmp/.../Image_0.jpg` placeholder paths — Godot's importer can't
# resolve them and the meshes import grey. The Meshy zip alongside
# each FBX bundles the actual textures under predictable filenames:
#   Meshy_AI_<name>_texture.png            — base color
#   Meshy_AI_<name>_texture_normal.png     — normal map
#   Meshy_AI_<name>_texture_metallic.png   — metallic
#   Meshy_AI_<name>_texture_roughness.png  — roughness
#   Meshy_AI_<name>_texture_emission.png   — emission
#
# This script walks the imported scene, finds those textures in the
# FBX's directory, builds a single StandardMaterial3D, and assigns it
# to every surface of every MeshInstance3D. The material is baked into
# the .scn import cache — zero runtime cost.
#
# Wired via .fbx.import → import_script/path. scaffold_character_imports.py
# writes that line for every player + enemy character FBX.


func _post_import(scene: Node) -> Object:
	var source: String = get_source_file()
	var dir: String = source.get_base_dir()
	var mat: StandardMaterial3D = _build_material(dir)
	if mat != null:
		_apply_material(scene, mat)
	return scene


# Locates the Meshy_AI_* textures in `dir` and bakes them into a single
# StandardMaterial3D. Returns null if no base-color texture is found —
# the FBX's default (grey) material stays in that case.
func _build_material(dir: String) -> StandardMaterial3D:
	var base: String = _find_texture(dir, "_texture.png", true)
	if base == "":
		return null
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(base)
	var nrm: String = _find_texture(dir, "_normal.png", false)
	if nrm != "":
		mat.normal_enabled = true
		mat.normal_texture = load(nrm)
	var met: String = _find_texture(dir, "_metallic.png", false)
	if met != "":
		mat.metallic = 1.0
		mat.metallic_texture = load(met)
	var rgh: String = _find_texture(dir, "_roughness.png", false)
	if rgh != "":
		mat.roughness = 1.0
		mat.roughness_texture = load(rgh)
	var emi: String = _find_texture(dir, "_emission.png", false)
	if emi != "":
		mat.emission_enabled = true
		mat.emission_texture = load(emi)
	return mat


# Finds the first Meshy_AI_*<suffix> file in `dir`. When `exclude_subtype`
# is true, also skips files where the suffix appears mid-name (so a
# search for "_texture.png" doesn't match "_texture_normal.png" etc).
func _find_texture(dir: String, suffix: String, exclude_subtype: bool) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("Meshy_AI_") and name.ends_with(suffix):
			if not exclude_subtype:
				return dir + "/" + name
			# Base color: name should end with "_texture.png" but not
			# "_texture_<anything>.png". Strip the suffix and confirm the
			# rest doesn't end with an underscore-prefixed subtype.
			var trimmed := name.substr(0, name.length() - suffix.length())
			if not trimmed.contains("_texture_"):
				return dir + "/" + name
		name = d.get_next()
	d.list_dir_end()
	return ""


func _apply_material(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for surf in range(mesh.get_surface_count()):
				mi.set_surface_override_material(surf, mat)
	for child in node.get_children():
		_apply_material(child, mat)
