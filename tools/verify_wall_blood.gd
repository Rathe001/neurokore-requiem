extends SceneTree

# Smoke test the wall blood pipeline:
#   1. Load WallLiquidLayer scene + verify it instantiates with a 2048x256
#      SubViewport.
#   2. Confirm the global shader uniforms exist + receive the texture.
#   3. Walk the wall shader for any parse errors that escaped startup.


func _init() -> void:
	print("\n══ WallLiquidLayer scene ══")
	var packed: PackedScene = load("res://scenes/world/wall_liquid_layer.tscn")
	if packed == null:
		push_error("Failed to load WallLiquidLayer scene")
		quit(); return
	var inst: Node = packed.instantiate()
	get_root().add_child(inst)
	await process_frame
	if inst is WallLiquidLayer:
		var wl: WallLiquidLayer = inst
		print("  fluid_id=%s surface_axis=%s child_count=%d" % [wl.fluid_id, wl.surface_axis, wl.get_child_count()])
		for c in wl.get_children():
			print("    child: %s (%s)" % [c.name, c.get_class()])
			if c is SubViewport:
				print("      size=%s tex=%s" % [(c as SubViewport).size, (c as SubViewport).get_texture()])
	else:
		print("  ERROR: instance is not WallLiquidLayer")
	# Set the global with a known value and read it back to confirm the
	# declaration actually exists in project.godot.
	RenderingServer.global_shader_parameter_set(&"wall_blood_age", 0.42)
	print("  test-set wall_blood_age=0.42, read back: %s" % RenderingServer.global_shader_parameter_get(&"wall_blood_age"))

	print("\n══ Global shader uniforms registered ══")
	var registered: PackedStringArray = RenderingServer.global_shader_parameter_get_list()
	for k in registered:
		print("  %s = type %s, value %s" % [k, RenderingServer.global_shader_parameter_get_type(k), RenderingServer.global_shader_parameter_get(k)])

	print("\n══ procedural_wall.gdshader compile ══")
	var shader: Shader = load("res://scripts/level/build/procedural_wall.gdshader") as Shader
	if shader == null:
		print("  ERROR: failed to load wall shader")
	else:
		# Attach to a ShaderMaterial. Godot validates the shader against
		# the registered global uniforms at this point — type mismatches
		# or undeclared globals surface as errors here.
		var mat := ShaderMaterial.new()
		mat.shader = shader
		print("  loaded OK (%d bytes) + bound to ShaderMaterial" % shader.code.length())

	quit()
