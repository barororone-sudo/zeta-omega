@tool
extends SceneTree

func _init():
	print("🤖 SCENE INJECTOR STARTING...")
	var main_scene_path = "res://AutoStart.tscn" # From project.godot
	var enemy_scene_path = "res://Entities/Enemy/SimpleEnemy.tscn"
	
	var main_packed = load(main_scene_path)
	if not main_packed:
		printerr("❌ Could not load Main Scene: " + main_scene_path)
		quit()
		return
		
	var main_root = main_packed.instantiate()
	
	var enemy_packed = load(enemy_scene_path)
	if not enemy_packed:
		printerr("❌ Could not load Enemy Scene: " + enemy_scene_path)
		quit()
		return
		
	var enemy_instance = enemy_packed.instantiate()
	enemy_instance.name = "SimpleEnemy_AutoAdded"
	enemy_instance.position = Vector3(5, 10, 5)
	
	main_root.add_child(enemy_instance)
	enemy_instance.owner = main_root # Crucial for saving!
	
	var packer = PackedScene.new()
	packer.pack(main_root)
	var err = ResourceSaver.save(packer, main_scene_path)
	
	if err == OK:
		print("✅ Enemy successfully injected into " + main_scene_path)
	else:
		printerr("❌ Failed to save scene. Error code: " + str(err))
		
	quit()
