@tool
extends Node3D

# VEGETATION SNAPPER
# A dedicated tool to debug and fix "floating trees" by reading raw heightmap data.

@export_category("Configuration")
@export var terrain_path: NodePath
@export var mesh_tree: Mesh
@export var count: int = 1000
@export var range_size: float = 500.0
@export var vertical_offset: float = -0.5
@export var random_seed: int = 42

@export_category("Actions")
@export var generate_trees: bool = false : set = _on_gen
@export var clear_trees: bool = false : set = _on_clear

func _on_gen(val):
	if val: 
		generate_trees = false # Reset toggle
		_generate()

func _on_clear(val):
	if val:
		clear_trees = false # Reset toggle
		_clear()

func _clear():
	var existing = find_child("Snapper_MultiMesh", true, false)
	if existing:
		existing.queue_free()
		print("🗑️ Cleared previous trees.")

func _generate():
	print("🌲 VegetationSnapper: Starting...")
	
	if not terrain_path:
		printerr("❌ Error: Assign the HTerrain node first!")
		return
		
	var terrain = get_node(terrain_path)
	if not terrain:
		printerr("❌ Error: HTerrain node not found at path!")
		return
		
	var data = terrain.get_data()
	if not data:
		printerr("❌ Error: HTerrain has no data loaded!")
		return
		
	if not mesh_tree:
		printerr("❌ Error: Assign a Mesh to populate!")
		return

	_clear()
	
	# Prepare MultiMesh
	var mmi = MultiMeshInstance3D.new()
	mmi.name = "Snapper_MultiMesh"
	add_child(mmi)
	mmi.owner = get_tree().edited_scene_root
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_tree
	mm.instance_count = count
	
	var rng = RandomNumberGenerator.new()
	rng.seed = random_seed
	
	var res = data.get_resolution()
	var map_scale_y = terrain.map_scale.y
	
	# Global Transform info to convert World <-> Heightmap
	# We assume trees are placed relative to THIS node (VegetationSnapper)
	# But get_height_at is local to Terrain.
	
	print("🔍 Reading Heightmap (Res: ", res, ", Scale Y: ", map_scale_y, ")...")
	
	for i in range(count):
		# 1. Random World Position (X, Z) relative to this tool
		var lx = rng.randf_range(-range_size, range_size)
		var lz = rng.randf_range(-range_size, range_size)
		
		var global_pos_candidate = global_transform * Vector3(lx, 0, lz)
		
		# 2. Convert to Terrain Local Space
		var terrain_local_pos = terrain.global_transform.affine_inverse() * global_pos_candidate
		
		# 3. Get Map Coordinates (Account for Map Scale)
		var map_x = int(terrain_local_pos.x / terrain.map_scale.x)
		var map_z = int(terrain_local_pos.z / terrain.map_scale.z)
		
		# 4. Check Bounds
		if map_x < 0 or map_x >= res or map_z < 0 or map_z >= res:
			# Hide this instance (Out of bounds)
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -9999, 0)))
			continue
			
		# 5. READ REAL HEIGHT (CRITICAL STEP)
		var h_raw = data.get_height_at(map_x, map_z)
		var h_scaled = h_raw * terrain.map_scale.y
		
		# 6. Apply Offset
		# var final_y = h_scaled + vertical_offset (Not used directly, we use world pos)
		
		# 7. Construct Final Transform
		# Re-construct local pos taking map_scale into account
		var local_pos_on_mesh = Vector3(map_x * terrain.map_scale.x, h_scaled, map_z * terrain.map_scale.z)
		var final_world_pos = terrain.to_global(local_pos_on_mesh)
		final_world_pos.y += vertical_offset
		
		# Convert back to MMI local
		var mmi_local_pos = mmi.to_local(final_world_pos)
		
		# Random Rotation/Scale
		var r_scale = rng.randf_range(0.8, 1.2)
		var r_rot = rng.randf() * TAU
		var basis = Basis().rotated(Vector3.UP, r_rot).scaled(Vector3(r_scale, r_scale, r_scale))
		
		mm.set_instance_transform(i, Transform3D(basis, mmi_local_pos))
		
	mmi.multimesh = mm
	print("✅ Generated ", count, " instances with Offset ", vertical_offset)
