@tool
extends SceneTree

func _init():
	print("🚀 RUNNING GRASS PAINTER AUTOMATION...")
	
	var main_scene_path = "res://AutoStart.tscn"
	var scene_packed = load(main_scene_path)
	if not scene_packed:
		printerr("❌ Could not load AutoStart.tscn")
		quit()
		return
		
	var root = scene_packed.instantiate()
	
	# Attach GrassPainter script temporarily to a node to run it
	var painter = Node.new()
	painter.set_script(load("res://Tools/GrassPainter.gd"))
	painter.name = "GrassPainter_Runner"
	root.add_child(painter)
	
	# Execute planting
	painter.plant_grass = true # This triggers _plant_grass via setter in tool script? 
	# Setter runs if engine is editor hint.
	# We are running via -s (script), so Engine.is_editor_hint() is True? 
	# usually -s runs as EditorScript? No, MainLoop.
	# Engine.is_editor_hint() is usually true for tool scripts running in editor, but --headless?
	# Let's call the function directly to be safe.
	if painter.has_method("_plant_grass"):
		painter._plant_grass()
	else:
		print("❌ _plant_grass method not found/exposed.")
		
	# SAVE DATA
	# The painter modifies HTerrainData. We need to save that Resource.
	var terrain = root.find_child("HTerrain", true, false)
	if terrain:
		var data = terrain.get_data()
		if data:
			print("💾 Saving HTerrain Data...")
			# Standard saving for HTerrain data
			# Usually resource_path is set.
			if data.resource_path != "":
				ResourceSaver.save(data, data.resource_path)
				print("✅ Data saved to " + data.resource_path)
			else:
				print("⚠️ Data has no resource path. Cannot save.")
				
	# Clean up
	painter.queue_free()
	
	print("✅ Grass Painting Complete.")
	quit()
