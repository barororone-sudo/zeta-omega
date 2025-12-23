@tool
extends Node

# --- CONFIGURATION ---
@export_group("Setup")
@export var terrain_node: Terrain3D

@export_group("Style: Hyrule & Teyvat")
@export var biome_scale: float = 0.002 # Échelle des continents
@export var height_scale: float = 120.0 # Hauteur max des montagnes
@export var terrace_height: float = 12.0 # Hauteur d'un étage de falaise
@export var cliff_steepness: float = 0.5 # 0 = Collines douces, 1 = Falaises abruptes
@export var noise_seed: int = 42

@export_group("Actions")
@export var button_generate_epic_terrain: bool = false : set = _on_gen_epic
@export var button_generate_smart_decor: bool = false : set = _on_gen_decor
@export var folder_assets: String = "res://Assets/"

# --- CODE PRINCIPAL ---
var _loading_ui = null

func _ready():
	if Engine.is_editor_hint(): return
	
	print("\n🌍 [PERSISTANCE] Démarrage du monde persistant...")
	
	# Afficher l'écran de chargement
	var loading_scn = load("res://UI/LoadingScreen.tscn")
	if loading_scn:
		_loading_ui = loading_scn.instantiate()
		get_tree().root.call_deferred("add_child", _loading_ui)
	
	await get_tree().process_frame # Laisser l'UI s'afficher
	
	var save_path = "res://Assets/Terraindata/GeneratedStorage.tres"
	if FileAccess.file_exists(save_path):
		_update_loading("Chargement de la sauvegarde...", 0.1)
		await get_tree().create_timer(0.5).timeout
		
		var data = load(save_path)
		if terrain_node:
			terrain_node.set("data", data)
			terrain_node.set("storage", data)
			
		_update_loading("Préparation du joueur...", 0.9)
		await get_tree().create_timer(0.5).timeout
		_teleport_player_safe()
	else:
		_update_loading("Initialisation d'un nouveau monde...", 0.0)
		_ensure_region_0_0_exists()
		_ensure_lighting_and_env()
		
		# Async Calls
		await _gen_epic_async()
		await _gen_decor_async()
		
		# Save
		_update_loading("Sauvegarde finale...", 0.95)
		var data = terrain_node.get("data"); if not data: data = terrain_node.get("storage")
		if data: ResourceSaver.save(data, save_path)
		
		_teleport_player_safe()

	if _loading_ui: 
		_loading_ui.queue_free()

func _update_loading(text: String, percent: float):
	if _loading_ui: _loading_ui.update_status(text, percent * 100.0)
	await get_tree().process_frame

func _ensure_lighting_and_env():
	# 1. Directional Light (Soleil)
	var sun = get_parent().find_child("DirectionalLight3D", true, false)
	if not sun:
		print("   + Création du Soleil (DirectionalLight3D)...")
		sun = DirectionalLight3D.new()
		sun.name = "Sun_Auto"
		get_parent().add_child(sun)
		sun.owner = get_tree().edited_scene_root
		sun.rotation_degrees = Vector3(-45, 150, 0)
		sun.shadow_enabled = true
		
	# 2. World Environment (Ciel & Lumière Ambiante)
	var env_node = get_parent().find_child("WorldEnvironment", true, false)
	if not env_node:
		print("   + Création de l'Environnement (WorldEnvironment)...")
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnv_Auto"
		get_parent().add_child(env_node)
		env_node.owner = get_tree().edited_scene_root
		
		var env = Environment.new()
		env.background_mode = Environment.BG_SKY
		var sky = Sky.new()
		var mat = ProceduralSkyMaterial.new()
		mat.sky_top_color = Color("3877be") # Zelda Blue
		mat.ground_bottom_color = Color("1a4a15") # Zelda Green
		sky.sky_material = mat
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.ssao_enabled = true # Ambient Occlusion pour le relief
		env.glow_enabled = true
		
		env_node.environment = env

func _ensure_region_0_0_exists():
	if not terrain_node: return
	var data = terrain_node.get("data")
	if not data: data = terrain_node.get("storage")
	
	# Si pas de data, on en crée une
	if not data:
		print("   + Création nouvelle Data Terrain3D...")
		data = ClassDB.instantiate("Terrain3DData") # Ou Terrain3DStorage
		if not data: data = ClassDB.instantiate("Terrain3DStorage")
		terrain_node.set("data", data)
		terrain_node.set("storage", data)
		
	# Vérif région
	var regions = []
	if data.has_method("get_regions_active"): regions = data.get_regions_active()
	
	if regions.is_empty():
		print("   + Initialisation Région (0,0)...")
		if data.has_method("add_region"):
			data.add_region(Vector3(0,0,0)) # Version avec Vector3?
		else:
			# Fallback: On espère que l'outil a des méthodes, sinon on simule
			# Hack pour Terrain3D 1.0 : Importation d'une region vide ?
			# Si on ne peut pas créer via script facilement, on prie pour que l'user ait suivi le tuto
			printerr("⚠️ Impossible de créer la région automatiquement. Assurez-vous d'avoir une région (0,0) !")

func _teleport_player_safe():
	var player = get_tree().get_first_node_in_group("Player")
	if not player: 
		# Recherche manuelle
		player = get_parent().find_child("Player", true, false)
		
	if player:
		# On le place au centre, en haut
		var data = terrain_node.get("data")
		if not data: data = terrain_node.get("storage")
		
		var h = 20.0
		if data: h = data.get_height(Vector3(0, 0, 0)) + 5.0
		
		print("📍 Téléportation Joueur à (0, ", h, ", 0)")
		player.global_position = Vector3(0, h, 0)
	else:
		print("⚠️ Joueur non trouvé pour TP.")

# --- ASYNC VERSIONS ---

# --- 1. GÉNÉRATION DU TERRAIN (LOGIQUE PARTAGÉE) ---
func _generate_terrain_logic(is_async: bool):
	print("\n✨ [GEN] Sculpture Terrain (Async: " + str(is_async) + ")")
	if is_async: _update_loading("Sculpture des Montagnes...", 0.1)
	
	if not terrain_node: return
	var data = terrain_node.get("data"); if not data: data = terrain_node.get("storage")
	if not data: return

	var noise_base = FastNoiseLite.new(); noise_base.seed = int(noise_seed); noise_base.frequency = biome_scale
	var noise_mount = FastNoiseLite.new(); noise_mount.seed = int(noise_seed)+1; noise_mount.frequency = biome_scale * 2.5
	var noise_warp = FastNoiseLite.new(); noise_warp.seed = int(noise_seed)+2; noise_warp.frequency = 0.01
	
	var active_regions = []
	if data.has_method("get_regions_active"): active_regions = data.get_regions_active()
	var region_size = 1024
	if data.has_method("get_region_size"): region_size = data.get_region_size()
	
	var total_regions = active_regions.size()
	var current_r = 0
	
	for region in active_regions:
		current_r += 1
		var rx = 0; var ry = 0
		if typeof(region) == TYPE_VECTOR2I: rx = region.x; ry = region.y
		elif region is Object: var l=region.get("location"); if l: rx=l.x; ry=l.y
		else: var loc=region.get("location"); if loc: rx=loc.x; ry=loc.y
		
		if is_async: _update_loading("Sculpture Région " + str(rx) + "," + str(ry), 0.1 + (float(current_r)/total_regions)*0.4)
		else: print("   -> Région ", rx, ",", ry)
		
		var start_x = rx * region_size; var start_z = ry * region_size
		var margin = 8
		
		for x in range(start_x + margin, start_x + region_size - margin):
			if is_async and x % 32 == 0: await get_tree().process_frame
			
			for z in range(start_z + margin, start_z + region_size - margin):
				var wx = x + noise_warp.get_noise_2d(x, z) * 50.0
				var wz = z + noise_warp.get_noise_2d(-x, z) * 50.0
				var base_h = noise_base.get_noise_2d(wx, wz) 
				var mount_h = noise_mount.get_noise_2d(wx, wz)
				var final_h = base_h * 40.0
				if base_h > 0.1:
					var mask = smoothstep(0.1, 0.4, base_h)
					final_h += mount_h * height_scale * mask
				
				var steps = final_h / terrace_height
				var i_step = floor(steps)
				var f_step = steps - i_step
				var t = clamp((f_step - 0.5) / (1.0 - cliff_steepness) + 0.5, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t) 
				var aesthetic_h = (i_step + t) * terrace_height
				
				data.set_height(Vector3(x, 0, z), aesthetic_h)
				
				var diff = abs(aesthetic_h - final_h)
				var tex_id = 3
				if aesthetic_h > height_scale * 0.8: tex_id = 2
				elif diff > 2.0: tex_id = 1
				elif aesthetic_h < -5.0: tex_id = 0
				data.set_control(Vector3(x, 0, z), tex_id)
				
	terrain_node.notify_property_list_changed()
	if not is_async: print("✅ Terrain généré (Editeur).")

# --- 2. DÉCORATION (LOGIQUE PARTAGÉE) ---
func _generate_decor_logic(is_async: bool):
	print("\n🌲 [GEN] Décoration (Async: " + str(is_async) + ")")
	if is_async: _update_loading("Plantation...", 0.5)
	
	if not terrain_node: return
	var data = terrain_node.get("data"); if not data: data = terrain_node.get("storage")
	
	var assets = _scan_assets(folder_assets)
	if assets.is_empty(): return
	
	for c in get_children(): c.free() # Free immédiat en éditeur
	
	var forest_noise = FastNoiseLite.new(); forest_noise.seed = int(noise_seed) + 55; forest_noise.frequency = 0.015
	var active_regions = []
	if data.has_method("get_regions_active"): active_regions = data.get_regions_active()
	var region_size = 1024
	if data.has_method("get_region_size"): region_size = data.get_region_size()
	
	var batch = {}
	var total_regions = active_regions.size()
	var current_r = 0
	
	for region in active_regions:
		current_r += 1
		if is_async: _update_loading("Végétation " + str(current_r) + "/" + str(total_regions), 0.5 + (float(current_r)/total_regions)*0.4)
		
		var rx = 0; var ry = 0;
		if typeof(region) == TYPE_VECTOR2I: rx = region.x; ry = region.y
		elif region is Object: var l=region.get("location"); if l: rx=l.x; ry=l.y
		else: var loc=region.get("location"); if loc: rx=loc.x; ry=loc.y
		
		var start_x = rx * region_size; var start_z = ry * region_size
		
		for x in range(start_x + 8, start_x + region_size - 8, 4):
			if is_async and x % 64 == 0: await get_tree().process_frame
			
			for z in range(start_z + 8, start_z + region_size - 8, 4):
				var h = data.get_height(Vector3(x, 0, z))
				if is_nan(h): continue
				var norm = data.get_normal(Vector3(x, h, z)); var slope = norm.angle_to(Vector3.UP)
				var type = ""; var forest_val = forest_noise.get_noise_2d(x, z)
				
				if slope > 0.6: 
					if randf() > 0.85: type = "rock"
				else:
					if forest_val > 0.2:
						if randf() < (forest_val + 0.3): type = "tree"
						elif randf() > 0.9: type = "rock"
					else: if randf() > 0.98: type = "rock"
						
				if type == "" or assets[type].is_empty(): continue
				var path = assets[type].pick_random()
				if not batch.has(path): batch[path] = []
				
				var t = Transform3D(); t.origin = Vector3(x, h, z)
				var align = 0.0; if type == "rock": align = 0.8
				var up = Vector3.UP.lerp(norm, align).normalized(); var right = up.cross(Vector3.FORWARD).normalized(); var fwd = right.cross(up).normalized()
				t.basis = Basis(right, up, fwd)
				t = t.rotated(up, randf() * TAU); t = t.scaled(Vector3(1,1,1) * randf_range(0.8, 1.3))
				batch[path].append(t)

	if is_async: 
		_update_loading("Instanciation...", 0.9)
		await get_tree().process_frame
	
	for path in batch:
		_create_multimesh(path, batch[path])
		if is_async: await get_tree().process_frame
		
	if not is_async: print("✅ Décor généré (Editeur).")

# --- WRAPPERS ASYNC/SYNC ---

func _gen_epic_async():
	await _generate_terrain_logic(true)

func _gen_decor_async():
	await _generate_decor_logic(true)

func _on_gen_epic(val):
	if val: _generate_terrain_logic(false) # Sync for Editor

func _on_gen_decor(val):
	if val: _generate_decor_logic(false) # Sync for Editor
