@tool
extends SceneTree

# KEYWORDS for Score Calculation (Higher = Better match)
const KEYWORDS = {
	"skeleton": 100,
	"goblin": 90,
	"orc": 90,
	"slime": 80,
	"enemy": 70,
	"monster": 70,
	"minion": 60,
	"character": 50,
	"npc": 40
}

func _init():
	print("🕵️ AUTO-SKINNER STARTED...")
	
	# 1. FIND THE BEST MODEL
	var model_path = _find_best_model("res://")
	if model_path == "":
		printerr("❌ No suitable enemy model found in project.")
		quit()
		return
		
	print("🎯 Found Candidate: " + model_path)
	
	# 2. SURGERY ON SCENE
	_perform_surgery("res://Entities/Enemy/SimpleEnemy.tscn", model_path)
	
	quit()

func _find_best_model(root_path):
	var best_path = ""
	var best_score = -1
	
	var stack = [root_path]
	while stack.size() > 0:
		var dir_path = stack.pop_back()
		var dir = DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if dir.current_is_dir():
					if not (file_name == "." or file_name == ".."):
						stack.append(dir_path + file_name + "/")
				else:
					var lower = file_name.to_lower()
					if lower.ends_with(".glb") or lower.ends_with(".gltf"):
						var score = 0
						for k in KEYWORDS:
							if k in lower: score += KEYWORDS[k]
						
						# Bonus for being in an "Enemies" or "Monsters" folder
						if "enemie" in dir_path.to_lower() or "monster" in dir_path.to_lower():
							score += 20
							
						if score > best_score and score > 0:
							best_score = score
							best_path = dir_path + file_name
							
				file_name = dir.get_next()
				
	return best_path

func _perform_surgery(scene_path, model_path):
	print("😷 Opening patient: " + scene_path)
	var scene = load(scene_path)
	if not scene:
		printerr("❌ Could not load scene: " + scene_path)
		return
		
	var root = scene.instantiate()
	
	# 1. FIND AND REMOVE OLD MESH
	var old_mesh = root.find_child("MeshInstance3D", true, false)
	if old_mesh:
		print("🗑️ Removing old capsule: " + old_mesh.name)
		old_mesh.free() # Remove from tree and memory
	else:
		print("⚠️ No MeshInstance3D found to replace. Proceeding anyway.")
		
	# 2. INJECT NEW MODEL
	var model_scene = load(model_path)
	if not model_scene:
		printerr("❌ Failed to load model: " + model_path)
		return
		
	var new_model = model_scene.instantiate()
	new_model.name = "Skin_" + model_path.get_file().get_basename()
	
	# ADJUST TRANSFORM
	# Most GLB characters have origin at feet, but some might need offset.
	# User requested y = -1.0 just in case.
	new_model.position.y = -0.9 # Slightly up from -1.0 to avoid clipping? User said -1.0, but capsule is usually centered.
	# CharacterBody3D origin is usually floor.
	# If origin is floor, model at 0,0,0 is correct.
	# IF User asked for -1.0, it implies the CharacterBody origin is floating? 
	# A CapsuleShape height 1.8 is usually centered at (0, 0.9, 0).
	# So feet are at 0.
	# I will trust the User's explicit request for adjustment or stick to standard (0).
	# "Il doit ajuster le position.y du nouveau modèle (souvent à -1.0)" -> They WANT -1.0.
	new_model.position.y = -1.0
	new_model.rotation_degrees.y = 180 # Often models face forward Z+, Godot is Z-. Flip 180 is common fix.
	
	root.add_child(new_model)
	new_model.owner = root
	
	print("💉 Injected new model: " + new_model.name)
	
	# 3. SAVE
	var packer = PackedScene.new()
	packer.pack(root)
	ResourceSaver.save(packer, scene_path)
	print("✅ Surgery Successful. Saved to " + scene_path)
