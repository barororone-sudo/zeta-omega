@tool
extends Node

## Biome Placer (Genshin/Zelda Style)
## Placement organique de végétation basé sur des Clusters et la Texture du sol.

@export_category("Configuration")
@export var terrain_node: Terrain3D
@export var assets_folder: String = "res://Assets/"
@export var button_scan: bool = false:
	set(value):
		if value: scan_assets()
		button_scan = false
@export var button_place: bool = false:
	set(value):
		if value and terrain_node: place_objects()
		button_place = false

@export_category("Density & Clusters")
@export var global_density: float = 0.5 ## Objets par mètre carré (approx)
@export var cluster_noise: FastNoiseLite ## Noise pour les Bosquets vs Clairières
@export var cluster_threshold: float = 0.5 ## > 0.5 = Bosquet (Plein d'arbres), < 0.5 = Rien

@export_category("Texture Rules (IDs)")
@export var tex_grass_ids: Array[int] = [3, 4] ## IDs considérés comme Herbe/Forêt
@export var tex_sand_ids: Array[int] = [0, 7] ## IDs considérés comme Désert
@export var tex_snow_ids: Array[int] = [2, 6] ## IDs considérés comme Neige
@export var tex_rock_ids: Array[int] = [1, 5] ## IDs considérés comme Roche

# Base de données interne
var assets_db = {
	"FOREST": [],   # tree, pine, oak...
	"DESERT": [],   # cactus, palm, dead...
	"ROCK": [],     # rock, stone, boulder...
	"RUIN": [],     # ruin, column, arch...
	"ICE": []       # snow, pine_snow...
}

var _created_multimeshes = []

func _ready():
	if not cluster_noise:
		cluster_noise = FastNoiseLite.new()
		cluster_noise.seed = randi()
		cluster_noise.frequency = 0.02 # Des clusters de taille moyenne (50m)
		cluster_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

# ---------------------------------------------------------
# 1. SCANNER INTELLIGENT
# ---------------------------------------------------------
func scan_assets():
	print("🔍 [BiomePlacer] Scanning Assets dans : ", assets_folder)
	# Reset
	for k in assets_db: assets_db[k] = []
	
	_scan_recursive(assets_folder)
	
	# Résumé
	for k in assets_db:
		print("   Category [", k, "]: ", assets_db[k].size(), " items.")

func _scan_recursive(path: String):
	var dir = DirAccess.open(path)
	if not dir: return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != ".." and not file_name.begins_with("addons"):
				_scan_recursive(path + file_name + "/")
		else:
			if file_name.ends_with(".glb") or file_name.ends_with(".gltf") or file_name.ends_with(".tscn"):
				_categorize(path + file_name, file_name.to_lower())
		file_name = dir.get_next()

func _categorize(full_path: String, lname: String):
	if "tree" in lname or "pine" in lname or "oak" in lname or "fir" in lname or "bush" in lname or "shrub" in lname:
		assets_db["FOREST"].append(full_path)
	elif "cactus" in lname or "palm" in lname or "dead" in lname:
		assets_db["DESERT"].append(full_path)
	elif "rock" in lname or "stone" in lname or "boulder" in lname:
		assets_db["ROCK"].append(full_path)
	elif "ruin" in lname or "column" in lname or "wall" in lname:
		assets_db["RUIN"].append(full_path)
	elif "ice" in lname or "snow" in lname:
		assets_db["ICE"].append(full_path)
	# Fallback : si c'est scan générique, peut-être ajouter à FOREST par défaut ? Non, soyons stricts.

# ---------------------------------------------------------
# 2. PLACEMENT ORGANIQUE
# ---------------------------------------------------------
func place_objects():
	if not terrain_node or not terrain_node.storage:
		printerr("❌ [BiomePlacer] Terrain3D manquant.")
		return
		
	# Nettoyage
	_clear_multimeshes()
	
	print("🌱 [BiomePlacer] Début du placement organique...")
	var storage = terrain_node.storage
	var region_size = 1024
	var step = max(1, int(1.0 / global_density))
	
	# Préparation des instancers (Map: Path -> Array[Transform3D])
	var processing_queue = {} 
	
	var height_map: Image = storage.get_map_region(0, 0)
	var control_map: Image = storage.get_map_region(1, 0)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = randi()
	
	for z in range(0, region_size, step):
		for x in range(0, region_size, step):
			# Jitter
			var jx = x + rng.randf_range(-2, 2)
			var jz = z + rng.randf_range(-2, 2)
			
			# Clamp
			jx = clamp(jx, 0, region_size-1)
			jz = clamp(jz, 0, region_size-1)
			
			# -------------------
			# REGÈLE CLUSTER
			# -------------------
			var noise_val = cluster_noise.get_noise_2d(jx, jz) # -1..1
			
			# "Bosquet vs Clairière"
			# Si densité < seuil, on skip (= Clairière dégagée)
			# Mais attention, pour le désert, c'est peut-être différent ?
			# Appliquons cette règle surtout pour la FORÊT.
			
			# Lecture Texture
			# Control map pixel : R = Texture ID (normalisé ?)
			# Dans Terrain3D 0.9.x, Control Map R est bien l'ID principal.
			# Attention : get_pixel return Color. r est float 0..1.
			# ID = int(round(col.r * 255.0))
			var ctrl_col = control_map.get_pixel(int(jx), int(jz)) # Pixel int coords
			var tex_id = int(round(ctrl_col.r * 255.0))
			
			# Hauteur
			var h_col = height_map.get_pixel(int(jx), int(jz))
			var height = h_col.r # Supposons que c'est la hauteur réelle (format dépendant)
			
			if height < 0: continue # Eau
			
			var category = ""
			
			# -------------------
			# RÈGLES DE BIOME
			# -------------------
			if tex_id in tex_grass_ids:
				# Logique CLUSTER pour la forêt
				if noise_val > cluster_threshold: 
					category = "FOREST"
				elif noise_val > cluster_threshold - 0.2:
					# Bordure de forêt -> Petits rochers ou buissons ?
					if rng.randf() < 0.3: category = "ROCK"
					
			elif tex_id in tex_sand_ids:
				# Désert : plus éparse, moins de clusters denses, juste du bruit
				# Mais on peut utiliser le noise pour des oasis
				if rng.randf() < 0.05: # Très rare
					category = "DESERT"
				elif noise_val > 0.7: # Oasis de cactus
					category = "DESERT"
					
			elif tex_id in tex_snow_ids:
				if rng.randf() < 0.1:
					category = "ICE"
			
			elif tex_id in tex_rock_ids:
				# Falaise -> Parfois des rochers qui tombent
				if rng.randf() < 0.05:
					category = "ROCK"

			
			if category == "" or assets_db[category].is_empty(): continue
			
			# Choix de l'asset
			var asset_path = assets_db[category].pick_random()
			
			if not processing_queue.has(asset_path):
				processing_queue[asset_path] = []
				
			# Création Transform
			var t = Transform3D()
			t.origin = Vector3(jx, height, jz)
			
			# Randoms
			var s = rng.randf_range(0.8, 1.3)
			t = t.scaled(Vector3(s,s,s))
			t = t.rotated(Vector3.UP, rng.randf_range(0, TAU))
			
			# Alignement au sol (Normal) ?
			# Pour l'instant vertical, sauf si on calcule la normale.
			# Terrain3D a des helpers pour ça mais on est en tool script pur data.
			# On laisse vertical pour les arbres, c'est mieux.
			
			processing_queue[asset_path].append(t)

	# Instanciation
	_commit_multimeshes(processing_queue)
	print("🌳 Placement terminé !")

func _commit_multimeshes(queue: Dictionary):
	for path in queue:
		var transforms = queue[path]
		if transforms.is_empty(): continue
		
		var mmi = _create_mmi(path)
		if not mmi: continue
		
		# Setup MultiMesh
		mmi.multimesh.instance_count = transforms.size()
		for i in range(transforms.size()):
			mmi.multimesh.set_instance_transform(i, transforms[i])
			
		add_child(mmi)
		mmi.owner = get_tree().edited_scene_root
		_created_multimeshes.append(mmi)

func _create_mmi(path: String) -> MultiMeshInstance3D:
	var loaded = load(path)
	if not loaded: return null
	
	var mesh_res = null
	if loaded is PackedScene:
		var state = loaded.instantiate()
		mesh_res = _find_mesh(state)
		state.queue_free()
	elif loaded is Mesh:
		mesh_res = loaded
		
	if not mesh_res: return null
	
	var mmi = MultiMeshInstance3D.new()
	mmi.name = "MMI_" + path.get_file().get_basename()
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.multimesh.mesh = mesh_res
	return mmi

func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D: return node.mesh
	for child in node.get_children():
		var res = _find_mesh(child)
		if res: return res
	return null

func _clear_multimeshes():
	for n in _created_multimeshes:
		if is_instance_valid(n): n.queue_free()
	_created_multimeshes.clear()
	# Nettoyage orphelins
	for c in get_children():
		if c is MultiMeshInstance3D: c.queue_free()
