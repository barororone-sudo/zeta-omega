@tool
extends Node

# --- FRESH GENERATOR V2 (ZELDA LOGIC) ---
# Concept: Vous fournissez le noeud Terrain3D, je fournis le contenu.

@export_group("Liens")
@export var terrain_node: Terrain3D

@export_group("Configuration")
@export var height_scale: float = 240.0
@export var terrace_height: float = 8.0
@export var cliff_steepness: float = 0.95
@export var reset_on_start: bool = true

func _ready():
	if Engine.is_editor_hint(): return
	print("🌱 FreshGenerator V2 (Zelda) prêt.")
	
	# AUTO-DETECTION (Si l'utilisateur ne sait pas faire le lien)
	if not terrain_node:
		var parent = get_parent()
		if parent:
			var t = parent.find_child("Terrain3D", true, false)
			if t: 
				print("✅ Terrain3D trouvé automatiquement : " + str(t.get_path()))
				terrain_node = t
	
	call_deferred("_start_generation")

func _start_generation():
	if not terrain_node:
		print("❌ ERREUR: Impossible de trouver le noeud 'Terrain3D'.")
		print("👉 Assurez-vous qu'un noeud nommé 'Terrain3D' existe dans la scène.")
		return
		
	print("🚀 Début de la génération sur: " + str(terrain_node.name))
	
	# 1. SETUP ASSETS (TEXTURES)
	_ensure_assets()
	
	# 2. SETUP DATA
	var storage = terrain_node.get("data")
	if not storage: storage = terrain_node.get("storage")
	
	if not storage:
		print("📦 Création d'un nouveau Storage...")
		storage = ClassDB.instantiate("Terrain3DData")
		if not storage: storage = ClassDB.instantiate("Terrain3DStorage")
		terrain_node.set("data", storage)
		terrain_node.set("storage", storage)
	
	if reset_on_start and storage.has_method("clear"):
		storage.clear()
		
	# 3. ADD REGION (0,0)
	if storage.has_method("add_region"):
		var reg = ClassDB.instantiate("Terrain3DRegion")
		reg.set("location", Vector2i(0,0))
		
		var r_size = 1024
		var h_map = Image.create(r_size, r_size, false, Image.FORMAT_RF)
		var c_map = Image.create(r_size, r_size, false, Image.FORMAT_RGBA8)
		c_map.fill(Color(0,0,0,1)) # ID 0 par défaut
		
		reg.set("height_map", h_map)
		reg.set("control_map", c_map)
		
		storage.add_region(reg)
		print("✅ Région 0,0 Initialisée.")
		
	# 5. VEGETATION
	_decorate_terrain(storage)
	
	print("🏁 Génération terminée.")

func _ensure_assets():
	if terrain_node.assets: return
	
	print("🎨 Chargement des Textures Zelda...")
	var assets = ClassDB.instantiate("Terrain3DAssets")
	var list = []
	
	var _add_tex = func(name, path_c):
		var t = ClassDB.instantiate("Terrain3DTextureAsset")
		t.name = name
		t.albedo_color = Color.WHITE
		if ResourceLoader.exists(path_c):
			t.albedo_texture = load(path_c)
			var path_n = path_c.replace("_Color", "_NormalGL")
			if ResourceLoader.exists(path_n): t.normal_texture = load(path_n)
		list.append(t)
		
	# 0: Dirt, 1: Rock, 2: Snow, 3: Grass
	_add_tex.call("Dirt", "res://Assets/3D/Nature/Ground068_1K-JPG/Ground068_1K-JPG_Color.jpg")
	_add_tex.call("Rock", "res://Assets/3D/Nature/Rock030_1K-JPG/Rock030_1K-JPG_Color.jpg")
	_add_tex.call("Snow", "res://Assets/3D/Nature/Ice002_1K-JPG/Ice002_1K-JPG_Color.jpg")
	_add_tex.call("Grass", "res://Assets/3D/Nature/Grass001_1K-JPG_Color.jpg")
	
	assets.texture_list = list
	terrain_node.assets = assets

func _generate_zelda_terrain(storage):
	if not storage: return
	print("⛰️ Sculpture Zelda en cours...")
	
	# Access Region 0,0
	# API Safe access (Vector2i or Objects)
	var active = []
	if storage.has_method("get_regions_active"): active = storage.get_regions_active()
	
	if active.is_empty(): return
	
	var region = active[0]
	# Convert Vector2i to Object if needed
	if region is Vector2i and storage.has_method("get_region"):
		region = storage.get_region(region)
		
	var h_img = region.get("height_map")
	var c_img = region.get("control_map")
	
	if not h_img or not c_img: return
	
	var size = h_img.get_width()
	
	# Noise
	var noise = FastNoiseLite.new(); noise.frequency = 0.0015; noise.seed = 42
	var noise_m = FastNoiseLite.new(); noise_m.frequency = 0.004; noise_m.seed = 99
	
	for y in range(size):
		for x in range(size):
			var base = noise.get_noise_2d(x, y)
			var mount = noise_m.get_noise_2d(x, y)
			
			var raw_h = base * 40.0
			if base > 0.1:
				raw_h += mount * height_scale * smoothstep(0.1, 0.4, base)
				
			# TERRACES
			var steps = raw_h / terrace_height
			var i_step = floor(steps)
			var f_step = steps - i_step
			var t = clamp((f_step - 0.5) / (1.0 - cliff_steepness) + 0.5, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			var final_h = (i_step + t) * terrace_height
			
			h_img.set_pixel(x, y, Color(final_h, 0, 0, 1))
			
			# TEXTURES (ID 0..3)
			# 3=Grass (Base), 1=Cliff, 2=Snow, 0=Dirt
			var tex_id = 3
			if final_h > height_scale * 0.75: tex_id = 2 # Snow
			elif abs(final_h - raw_h) > 2.0: tex_id = 1 # Cliff
			elif final_h < -2.0: tex_id = 0 # Dirt/Water
			
			c_img.set_pixel(x, y, Color(float(tex_id)/255.0, 0, 0, 1))
				
	# UPDATE FORCE
	region.set("height_map", h_img)
	region.set("control_map", c_img)
	
	if storage.has_method("force_update_terrain"):
		storage.force_update_terrain()
	elif terrain_node.has_method("notify_property_list_changed"):
		terrain_node.notify_property_list_changed()

func _decorate_terrain(storage):
	print("🌲 Décoration (Arbres & Rochers)...")
	var assets = _scan_assets_safe("res://Assets/")
	var batch = {} 
	
	var r_size = 1024
	var start_x = 0; var start_z = 0
	
	for x in range(start_x + 10, start_x + r_size - 10, 8):
		for z in range(start_z + 10, start_z + r_size - 10, 8):
			var h = storage.get_height(Vector3(x, 0, z))
			if is_nan(h): continue
			if h <= 0: continue # Pas sous l'eau
			
			var n = storage.get_normal(Vector3(x, h, z))
			var slope = n.angle_to(Vector3.UP)
			
			var type = ""
			if slope > 0.6: 
				if randf() > 0.8: type = "rock"
			elif h < height_scale * 0.6: # Pas trop haut
				if randf() > 0.8: type = "tree"
				
			if type != "" and not assets[type].is_empty():
				var path = assets[type].pick_random()
				if not batch.has(path): batch[path] = []
				
				var t = Transform3D()
				t.origin = Vector3(x, h, z)
				t = t.scaled(Vector3.ONE * randf_range(0.8, 1.2))
				batch[path].append(t)
				
	for k in batch:
		_create_multimesh(k, batch[k])

func _scan_assets_safe(root_path: String) -> Dictionary:
	var res = {"tree": [], "rock": []}
	_scan_dir_recursive(root_path, res)
	return res

func _scan_dir_recursive(path: String, res: Dictionary):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_scan_dir_recursive(path + "/" + file_name, res)
			else:
				var lower = file_name.to_lower()
				var full_path = path + "/" + file_name
				if lower.ends_with(".glb") or lower.ends_with(".gltf") or lower.ends_with(".tscn"):
					if "tree" in lower or "palm" in lower: res["tree"].append(full_path)
					elif "rock" in lower or "stone" in lower: res["rock"].append(full_path)
			file_name = dir.get_next()

func _create_multimesh(path, transforms):
	if transforms.is_empty(): return
	var scene = load(path)
	if not scene: return
	var temp = scene.instantiate()
	var mesh = null
	if temp is MeshInstance3D: mesh = temp.mesh
	else:
		var mi = temp.find_child("MeshInstance3D", true, false)
		if mi: mesh = mi.mesh
	temp.free()
	
	if not mesh: return
	
	var mmi = MultiMeshInstance3D.new()
	mmi.name = "MMI_" + path.get_file().get_basename()
	var mm = MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh; mm.instance_count = transforms.size()
	mmi.multimesh = mm
	add_child(mmi)
	mmi.owner = get_tree().edited_scene_root
	for i in range(transforms.size()): mm.set_instance_transform(i, transforms[i])
