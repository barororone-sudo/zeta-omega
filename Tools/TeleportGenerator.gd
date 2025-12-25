@tool
extends Node
class_name TeleportGenerator

# This script is meant to be run from the generator to place points
# 10 points per biome type

func generate_points(root_node: Node, terrain):
	print("📍 Generating Teleport Points...")
	var container = Node3D.new()
	container.name = "TeleportPoints"
	root_node.add_child(container)
	container.owner = root_node.owner
	
	# Biome IDs to target
	var biome_ids = [0, 4, 5, 6, 8] # Cliff, Grass, Wild, Forest, Snow
	
	var data = terrain.get_data()
	var res = data.get_resolution()
	var scale = terrain.map_scale
	
	for b_id in biome_ids:
		var count = 0
		var attempts = 0
		
		while count < 10 and attempts < 200:
			attempts += 1
			# Random Pos
			var tx = randi() % res
			var ty = randi() % res
			
			# Check Biome
			# (Assuming we have Splatmap access via Image, expensive but okay for generation)
			# Fast Hack: Random World Pos, check Height rules if splatmap is hard to read
			# Let's use simple height/noise rules for now like the Painter
			
			var h = data.get_height_at(tx, ty)
			if h < 2.5: continue # Underwater
			
			var world_x = tx * scale.x
			var world_z = ty * scale.z
			var pos = Vector3(world_x, h, world_z)
			
			# Spawn Point
			# Spawn Point (Visual Scene)
			var scene = load("res://Entities/World/TeleportPoint.tscn")
			if scene:
				var point = scene.instantiate()
				point.name = "TP_Biome_" + str(b_id) + "_" + str(count)
				point.position = pos
				if "biome_id_int" in point: point.biome_id_int = b_id
				container.add_child(point)
				if root_node.owner: point.owner = root_node.owner
			
			count += 1
			
	print("✅ Teleport Points Generated!")
