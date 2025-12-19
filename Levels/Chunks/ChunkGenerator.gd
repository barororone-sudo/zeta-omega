extends Node3D

@export var asset_folder: String = "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/"
@export var item_count_min: int = 5
@export var item_count_max: int = 10
@export var spawn_range: float = 30.0

func _ready() -> void:
	_generate_nature()

func _generate_nature() -> void:
	var dir = DirAccess.open(asset_folder)
	if not dir:
		print("❌ ChunkGenerator: Dossier introuvable " + asset_folder)
		return
		
	dir.list_dir_begin()
	var glb_files = []
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".gltf") or file_name.ends_with(".glb")):
			glb_files.append(file_name)
		file_name = dir.get_next()
	
	if glb_files.size() == 0:
		print("⚠️ ChunkGenerator: Aucun modèle trouvé dans " + asset_folder)
		return
		
	var count = randi_range(item_count_min, item_count_max)
	print("🌲 Génération de " + str(count) + " éléments nature...")
	
	for i in range(count):
		var random_file = glb_files.pick_random()
		var full_path = asset_folder + "/" + random_file
		_spawn_prop(full_path)

func _spawn_prop(path: String) -> void:
	var resource = load(path)
	if not resource: return
	
	var instance = resource.instantiate()
	add_child(instance)
	
	var x = randf_range(-spawn_range, spawn_range)
	var z = randf_range(-spawn_range, spawn_range)
	var y_rot = randf_range(0, 360)
	var scale_factor = randf_range(0.8, 1.5)
	
	instance.position = Vector3(x, 0, z)
	instance.rotation_degrees.y = y_rot
	instance.scale = Vector3.ONE * scale_factor
