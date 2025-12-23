@tool
extends Node

# --- CONFIGURATION (ZERO CONFIG) ---
@export_category("🪄 Baguette Magique")
@export var Magic_Button_GENERATE_ALL: bool = false : set = _on_magic_button

# --- STATE ---
var _assets_library = {
	"forest": [], # tree, pine, fir
	"jungle": [], # palm, jungle
	"desert": [], # cactus, sand
	"mountain": [], # rock, stone, boulder
	"ruins": []   # ruin, column, wall
}

var _keywords = {
	"forest": ["tree", "pine", "fir", "oak", "birch"],
	"jungle": ["palm", "jungle", "fern", "monstera"],
	"desert": ["cactus", "sand", "dead_bush"],
	"mountain": ["rock", "stone", "boulder", "cliff", "pebble"],
	"ruins": ["ruin", "column", "wall", "arch", "brick"]
}

# --- MAIN ENTRY POINT ---
func _on_magic_button(val):
	if not val: return
	print("\n✨ --- DÉBUT DE LA MAGIE --- ✨")
	
	# 1. SCAN (Le Renifleur)
	print("🕵️ 1. Scanning des assets dans 'res://'...")
	_reset_library()
	_scan_recursive("res://")
	_print_library_stats()
	
	# 2. AMBIANCE (Le Décorateur)
	print("☀️ 2. Mise en place de l'ambiance...")
	_setup_ambiance()
	
	# 3. TERRAIN (Le Sculpteur)
	print("⛰️ 3. Sculpture du terrain...")
	_setup_terrain_and_sculpt()
	
	# 4. PLANTATION (Le Jardinier)
	print("🌳 4. Plantation de la végétation...")
	_plant_vegetation()
	
	print("✅ --- MAGIE TERMINÉE --- ✅")

# --- 1. SCANNER ---
func _reset_library():
	for k in _assets_library: _assets_library[k] = []

func _scan_recursive(path: String):
	var dir = DirAccess.open(path)
	if not dir: return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir():
			if not (file_name == "." or file_name == ".." or file_name.begins_with(".")):
				_scan_recursive(path.ends_with("/") and path + file_name or path + "/" + file_name)
		else:
			# Check extension
			if file_name.ends_with(".glb") or file_name.ends_with(".gltf") or file_name.ends_with(".tscn"):
				_categorize_asset(path.ends_with("/") and path + file_name or path + "/" + file_name)
		
		file_name = dir.get_next()

func _categorize_asset(full_path: String):
	var lower_name = full_path.get_file().to_lower()
	
	for category in _keywords:
		for keyword in _keywords[category]:
			if keyword in lower_name:
				_assets_library[category].append(full_path)
				return # Un asset va dans une seule catégorie (la première trouvée)

func _print_library_stats():
	for k in _assets_library:
		if _assets_library[k].is_empty():
			printerr("⚠️ Attention: Aucun asset trouvé pour le biome '" + k + "'")
		else:
			print("   -> " + k.capitalize() + ": " + str(_assets_library[k].size()) + " assets.")

# --- 2. AMBIANCE ---
func _setup_ambiance():
	var parent = get_parent()
	if not parent: return
	
	# Light
	var sun = parent.find_child("DirectionalLight3D", true, false)
	if not sun:
		sun = DirectionalLight3D.new()
		sun.name = "DirectionalLight3D"
		parent.add_child(sun)
		sun.owner = get_tree().edited_scene_root
		print("   + Soleil créé.")
	
	sun.current = true
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.shadow_enabled = true
	
	# Env
	var env_node = parent.find_child("WorldEnvironment", true, false)
	if not env_node:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		parent.add_child(env_node)
		env_node.owner = get_tree().edited_scene_root
		print("   + WorldEnvironment créé.")
	
	if not env_node.environment:
		var env = Environment.new()
		var sky = Sky.new()
		var mat = ProceduralSkyMaterial.new()
		mat.sky_top_color = Color(0.2, 0.5, 0.8) # Genshin Blue
		mat.ground_bottom_color = Color(0.1, 0.3, 0.1)
		sky.sky_material = mat
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.ssao_enabled = true
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.01
		env.volumetric_fog_albedo = Color(0.8, 0.9, 1.0)
		env_node.environment = env
		print("   + Environment 'Anime' configuré.")

# --- 3. TERRAIN ---
func _setup_terrain_and_sculpt():
	var terrain_node = _find_terrain_node()
	if not terrain_node:
		printerr("❌ CRITIQUE: Pas de nœud Terrain3D trouvé dans la scène. Ajoutez-en un svp.")
		return
	
	var data = terrain_node.get("data")
	if not data: data = terrain_node.get("storage")
	
	if not data:
		printerr("❌ CRITIQUE: Terrain3D n'a pas de Data/Storage.")
		return
		
	# Init Regions (3x3 grid centered = 9 regions for safety, or just 1 big one)
	# User asked for 3 regions. Let's ensure (0,0), (0,1), (1,0) exist.
	var regions_to_ensure = [Vector2i(0,0), Vector2i(0,1), Vector2i(1,0)]
	if data.has_method("add_region"):
		for r in regions_to_ensure:
			if not data.has_region(r):
				data.add_region(Vector3(r.x, 0, r.y))
	
	var region_size = 1024
	if data.has_method("get_region_size"): region_size = data.get_region_size()
	
	var noise_height = FastNoiseLite.new()
	noise_height.frequency = 0.003
	noise_height.fractal_octaves = 4
	
	var noise_biome = FastNoiseLite.new()
	noise_biome.seed = 123
	noise_biome.frequency = 0.0005
	
	var active_regions = []
	if data.has_method("get_regions_active"): active_regions = data.get_regions_active()
	
	for region in active_regions:
		var rx = region.x
		var ry = region.y
		var start_x = rx * region_size
		var start_z = ry * region_size
		
		print("   -> Traitement Région ", rx, ",", ry)
		
		for x in range(start_x, start_x + region_size):
			for z in range(start_z, start_z + region_size):
				# 1. Base Coat (Opacité Max pour cacher le damier)
				# Texture ID 3 = Herbe (supposons)
				# set_control(x, z, texture_id)
				data.set_control(Vector3(x, 0, z), 3) # Force Grass Everywhere
				
				# 2. Sculpt
				var h = noise_height.get_noise_2d(x, z) * 60.0 # Hauteur modérée
				if h < 0: h *= 0.2 # Plaines plus plates
				data.set_height(Vector3(x, 0, z), h)
				
				# 3. Biome Paint
				var biome_val = noise_biome.get_noise_2d(x, z)
				if biome_val > 0.4:
					data.set_control(Vector3(x, 0, z), 2) # Snow/Mountains
				elif biome_val < -0.4:
					data.set_control(Vector3(x, 0, z), 0) # Sand/Dirt
					
	terrain_node.notify_property_list_changed()

# --- 4. PLANTATION ---
func _plant_vegetation():
	var terrain_node = _find_terrain_node()
	if not terrain_node: return
	var data = terrain_node.get("data")
	if not data: data = terrain_node.get("storage")
	
	# Clear old decoration
	for c in get_children():
		if c.name.begins_with("MMI_"): c.queue_free()
		
	# Noise de densité (Clusters)
	var noise_distri = FastNoiseLite.new()
	noise_distri.frequency = 0.02
	
	var batch = {} # asset_path -> [transforms]
	
	var active_regions = []
	if data.has_method("get_regions_active"): active_regions = data.get_regions_active()
	var region_size = 1024
	if data.has_method("get_region_size"): region_size = data.get_region_size()

	for region in active_regions:
		var start_x = region.x * region_size
		var start_z = region.y * region_size
		
		# Optim: Pas de 10m
		for x in range(start_x, start_x + region_size, 10):
			for z in range(start_z, start_z + region_size, 10):
				
				var h = data.get_height(Vector3(x, 0, z))
				if is_nan(h): continue
				
				# Biome Logic
				var biome_type = "forest" # Default
				var b_val = _get_pixel_biome_val(x, z) # Fake func wrapping perlin
				
				if b_val > 0.4: biome_type = "mountain"
				elif b_val < -0.4: biome_type = "desert"
				
				# Cluster Logic
				var d_val = noise_distri.get_noise_2d(x, z)
				if d_val < 0.2: continue # Espace vide
				
				if _assets_library[biome_type].is_empty(): continue
				
				var asset_path = _assets_library[biome_type].pick_random()
				
				# Transform
				var norm = data.get_normal(Vector3(x, h, z))
				var t = Transform3D()
				t.origin = Vector3(x, h, z)
				
				# Align to normal randomly
				var up = Vector3.UP.lerp(norm, 0.5 if biome_type == "mountain" else 0.1).normalized()
				var right = up.cross(Vector3.FORWARD).normalized()
				var fwd = right.cross(up).normalized()
				if is_nan(right.x): right = Vector3.RIGHT; fwd = Vector3.FORWARD # Safety
				
				t.basis = Basis(right, up, fwd)
				t = t.scaled(Vector3.ONE * randf_range(0.8, 1.5))
				t = t.rotated(up, randf() * TAU)
				
				if not batch.has(asset_path): batch[asset_path] = []
				batch[asset_path].append(t)
				
	# Instantiate
	for path in batch:
		_instantiate_multimesh(path, batch[path])

func _get_pixel_biome_val(x, z):
	# Recreate same noise as terrain func to match
	# TODO: Store this noise instance effectively
	var n = FastNoiseLite.new()
	n.seed = 123
	n.frequency = 0.0005
	return n.get_noise_2d(x, z)

func _instantiate_multimesh(path, transforms):
	var scn = load(path)
	if not scn: return
	
	# Extract Mesh
	var temp = scn.instantiate()
	var mesh = null
	if temp is MeshInstance3D: mesh = temp.mesh
	else:
		for c in temp.get_children():
			if c is MeshInstance3D: mesh = c.mesh; break
	temp.queue_free()
	
	if not mesh: return
	
	var mmi = MultiMeshInstance3D.new()
	mmi.name = "MMI_" + path.get_file().get_basename()
	add_child(mmi)
	mmi.owner = get_tree().edited_scene_root
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	mmi.multimesh = mm
	
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

func _find_terrain_node():
	# Recursive search
	var p = get_parent()
	while p:
		var t = p.find_child("Terrain3D", true, false)
		if t: return t
		p = p.get_parent()
		if p == get_tree().root: break
	return null
