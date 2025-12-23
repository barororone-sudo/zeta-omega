@tool
extends Node

# --- CONFIGURATION SÉCURISÉE ---
@export_group("Setup")
@export var terrain_node: Terrain3D
@export var loading_screen_scene: PackedScene = preload("res://UI/LoadingScreen.tscn")

@export_group("Style: Hyrule & Teyvat")
@export var biome_scale: float = 0.0015 # Plus large
@export var height_scale: float = 240.0 # Plus haut
@export var terrace_height: float = 8.0 # Marches plus fines
@export var cliff_steepness: float = 0.95 # Falaises très nettes
@export var noise_seed: int = 42

@export_group("Actions")
@export var force_reset: bool = false # Cochez pour régénérer le monde
@export var generer_en_douceur: bool = false : set = _on_button_generate
@export var folder_assets: String = "res://Assets/"

# UI Instance
var _ui_instance = null

func _ready():
	# Si on est dans l'éditeur, on ne fait rien automatiquement
	if Engine.is_editor_hint(): return
	
	print("\n✅ LIVE V2: SafeGenerator Ready (Double-Reset Fix)")
	
	if not terrain_node:
		# Auto-détection
		var t = get_parent().find_child("Terrain3D", true, false)
		if t: terrain_node = t
		else: print("⚠️ Terrain3D non trouvé automatiquement. Assurez-vous qu'il est dans la scène !")

	# Vérifier sauvegarde (Priorité user:// car c'est là qu'on écrit si res:// échoue)
	# IMPORTANT: On utilise .res (BINAIRE) au lieu de .tres (TEXTE) pour éviter le lag monstrueux au chargement
	var save_path_res = "res://Assets/Terraindata/GeneratedStorage_AirWorld.res"
	var save_path_user = "user://GeneratedStorage_AirWorld.res"
	var path_to_load = ""
	
	# Compatibilité arrière : Si un .tres existe, on ignore ou on le supprime (car trop lent)
	if FileAccess.file_exists("user://GeneratedStorage.tres"):
		print("⚠️ Vieux fichier .tres détecté. Ignoré pour performance.")
		# DirAccess.remove_absolute("user://GeneratedStorage.tres") 
	
	if FileAccess.file_exists(save_path_user):
		path_to_load = save_path_user
	elif FileAccess.file_exists(save_path_res):
		path_to_load = save_path_res
	
	# Gestion du Reset Force
	if force_reset:
		print("♻️ RESET DEMANDÉ. Nettoyage physique des fichiers...")
		if FileAccess.file_exists(save_path_user): DirAccess.remove_absolute(save_path_user)
		if FileAccess.file_exists(save_path_res):  DirAccess.remove_absolute(save_path_res)
		path_to_load = "" 
	
	if path_to_load != "":
		print("💾 Sauvegarde BINAIRE trouvée (" + path_to_load + ").")
		_load_existing_world(path_to_load)
	else:
		print("✨ Nouveau monde requis. Démarrage de la séquence ASYNC sécurisée.")
		_start_safe_generation_sequence()

func _load_existing_world(path):
	_show_loading_screen()
	_update_ui("Lecture du disque (Binaire)...", 0)
	
	# LOAD THREADED pour ne pas freezer le PC
	ResourceLoader.load_threaded_request(path)
	
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# On laisse respirer le thread principal
		await get_tree().process_frame
		_update_ui("Chargement des données...", 50)
		
	var status = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var data = ResourceLoader.load_threaded_get(path)
		if terrain_node and data:
			_update_ui("Envoi vers GPU...", 80)
			await get_tree().process_frame
			
			terrain_node.set("data", data)
			terrain_node.set("storage", data)
			
			if terrain_node.has_method("notify_property_list_changed"):
				terrain_node.notify_property_list_changed()
				
			print("✅ Chargement terminé.")
	else:
		print("❌ Erreur chargement threaded. Fallback regeneration.")
		_start_safe_generation_sequence()
		return

	_update_ui("Préparation...", 100)
	await get_tree().create_timer(0.2).timeout
	_hide_loading_screen()
	_teleport_player()

func _print_debug_state():
	print("\n🔍 --- DEBUT ANALYSE DIAGNOSTIQUE (Deep Analysis) ---")
	if not terrain_node:
		print("❌ ERREUR: terrain_node est NULL.")
		return

	print("📍 Noeud: " + str(terrain_node.get_path()))
	print("❓ Visible: " + str(terrain_node.visible))
	
	# Check Storage
	var d = terrain_node.get("data")
	if not d: d = terrain_node.get("storage")
	
	if d:
		print("✅ Data/Storage Object: " + str(d))
		if d.has_method("get_region_count"):
			print("   📊 Regions Count: " + str(d.get_region_count()))
		if d.has_method("get_regions_active"):
			print("   📍 Active Regions: " + str(d.get_regions_active()))
	else:
		print("❌ ERREUR: Data/Storage est NULL !")

	# Check Assets
	var a = terrain_node.assets
	if a:
		print("✅ Assets Object: " + str(a))
		if a.has_method("get_texture_count"):
			var tc = a.get_texture_count()
			print("   🎨 Textures Count: " + str(tc))
			if tc == 0:
				print("   ⚠️ AVERTISSEMENT: 0 Textures ! Le terrain sera invisible/noir.")
	else:
		print("❌ ERREUR: Assets est NULL !")
		
	print("🔍 --- FIN ANALYSE ---\n")

func _start_safe_generation_sequence():
	_show_loading_screen()
	await get_tree().process_frame
	_print_debug_state()

	
	# 1. SETUP
	_update_ui("Initialisation...", 5)
	
	# MASQUER LE MONDE PENDANT LA GÉNÉRATION
	var world = get_parent().find_child("GameWorld", true, false)
	if world: world.visible = false
	
	_ensure_lighting()
	_ensure_theme_assets()
	var data = _ensure_data()
	
	_print_debug_state() # Déplacé APRES le setup pour voir les textures
	
	if not data: return # Erreur grave
	
	# Force Collision (Removed invalid property)
	# if terrain_node:
	#	terrain_node.call("update_collision") # Tentative alternative safe

	
	# 2. SCULPTURE DOUCE
	await _sculpt_terrain_async(data)
	
	# 3. DÉCORATION DOUCE
	await _decorate_terrain_async(data)
	_spawn_towers(data)
	
	# 4. SAUVEGARDE & FIN
	_update_ui("Sauvegarde...", 95)
	await get_tree().process_frame
	
	# IMPORTANT: Sauvegarde en BINAIRE (.res) pour rapidité
	var save_path = "res://Assets/Terraindata/GeneratedStorage_AirWorld.res"
	var dir = save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	
	# Sauvegarde Permissive
	if data and data is Resource:
		print("💾 Démarrage Sauvegarde... Objet: ", data, " Type: ", data.get_class())
		var err = ResourceSaver.save(data, save_path)
		if err == OK:
			print("✅ Monde sauvegardé (BINARY) : " + save_path)
		else:
			print("⚠️ Erreur sauvegarde principale (" + str(err) + ") - Tentative User...")
			# Fallback User
			ResourceSaver.save(data, "user://GeneratedStorage_AirWorld.res")
	else:
		print("❌ DATA INVALIDE (Null ou pas une Resource). Sauvegarde annulée.")
	# 5. ULTIMATE SYNC (Rafraîchissement GPU)
	if terrain_node:
		print("☢️ ULTIMATE SYNC : Tentative de rafraîchissement GPU...")
		# On évite le null qui crash sur certaines versions
		terrain_node.set("storage", data)
		
		if terrain_node.has_method("notify_property_list_changed"):
			terrain_node.notify_property_list_changed()
		print("☢️ ULTIMATE SYNC : Signal envoyé.")
	
	_teleport_player()
	
	# 5. SPAWN ENEMIES (ASYNC)
	_spawn_enemies_async(data)

	# RÉ-AFFICHER LE MONDE
	var world_end = get_parent().find_child("GameWorld", true, false)
	if world_end: world_end.visible = true
	
	_hide_loading_screen()

# --- COEUR ASYNCHRONE ---

func _sculpt_terrain_async(data):
	print("⛰️ Début Sculpture Async...")
	_update_ui("Sculpture du terrain...", 10)
	
	# Noise Setup
	var noise_base = FastNoiseLite.new(); noise_base.seed = noise_seed; noise_base.frequency = biome_scale
	var noise_mount = FastNoiseLite.new(); noise_mount.seed = noise_seed+1; noise_mount.frequency = biome_scale * 2.5
	var noise_warp = FastNoiseLite.new(); noise_warp.seed = noise_seed+2; noise_warp.frequency = 0.01

	var active_regions = []
	if data.has_method("get_regions_active"):
		active_regions = data.get_regions_active()
	
	if active_regions.is_empty():
		# Fallback si vraiment rien (mais normalement _ensure_data a créé 0,0)
		active_regions = [Vector2i(0,0)]
	
	# 3. SCULPTURE DIRECTE SUR IMAGE (Bypass API Lookup)
	var processed_regions = 0
	
	for region in active_regions:
		processed_regions += 1
		
		# Identifier la position de la région
		var rx = 0
		var ry = 0
		if region is Vector2i:
			rx = region.x
			ry = region.y
			# Si c'est un Vector2i, on ne peut pas éditer l'image directement sans récupérer l'objet...
			# Mais active_regions devrait retourner des Objets maintenant.
			if data.has_method("get_region"):
				region = data.get_region(region) 
		
		if not is_instance_valid(region) or not region.has_method("get_location"):
			print("⚠️ Région invalide ou API inconnue, skip.")
			continue
			
		var loc = region.get_location()
		rx = loc.x
		ry = loc.y
		
		if not region.get("height_map"): continue
		
		# DUPLICATION FORCÉE : Pour garantir que 'region.height_map = h_map' déclenche le setter
		var h_map: Image = region.height_map.duplicate()
		var c_map: Image = region.control_map.duplicate()
		
		if not h_map or not c_map:
			print("⚠️ Maps manquantes pour la région " + str(loc))
			continue
			
		var r_size = h_map.get_width()
		var start_x_world = rx * r_size # Offset Global
		var start_z_world = ry * r_size
		
		print("🎨 Sculpture Région " + str(loc) + " (Direct Image Access)")
		
		# Boucle Pixels (Local Space 0..1024)
		print("🔍 Image Format (H): " + str(h_map.get_format()) + " (Expect 5/RF or 9/RGF)")
		
		for x in range(0, r_size):
			
			if x % 100 == 0: 
				_update_ui("Sculpture R" + str(loc) + " " + str(int(float(x)/r_size*100)) + "%...", 20.0 + (float(processed_regions)/active_regions.size() * 30.0))
				await get_tree().process_frame
			
			for y in range(0, r_size): # Y est Z en 3D
				# Coordonnées Globales pour le Bruit
				var wx = start_x_world + x
				var wz = start_z_world + y
				
				# Ajout warping léger
				var ns_x = wx + noise_warp.get_noise_2d(wx, wz) * 50.0
				var ns_z = wz + noise_warp.get_noise_2d(-wx, wz) * 50.0
				
				# Calcul Hauteur
				var base_h = noise_base.get_noise_2d(ns_x, ns_z) 
				var mount_h = noise_mount.get_noise_2d(ns_x, ns_z)
				
				# SUPER BOOST (Pour être sûr à 100% de voir des collines)
				var final_h = base_h * 150.0 # Augmenté de 50 à 150
				if base_h > 0.0:
					final_h += mount_h * 200.0 * smoothstep(0.0, 0.5, base_h)
				
				# Terrasses (Zelda Style)
				var steps = final_h / terrace_height
				var i_step = floor(steps)
				var f_step = steps - i_step
				var t = clamp((f_step - 0.5) / (1.0 - cliff_steepness) + 0.5, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t) 
				var aesthetic_h = (i_step + t) * terrace_height
				
				# --- 10 BIOMES SPLATTING ---
				# --- 10 BIOMES SPLATTING (NOUVELLE LOGIQUE) ---
				# 0:Forest, 1:Fire, 2:Ice, 3:Jungle, 4:Lightning, 5:Desert, 6:Lava, 7:Gold, 8:Crystal, 9:SnowHigh
				# 0:Forest, 1:Fire, 2:Ice, 3:Jungle, 4:Lightning, 5:Desert, 6:Lava, 7:Gold, 8:Crystal, 9:SnowHigh
				var tex_id = 0 # DEBUG: FORCE LAVA EVERYWHERE
				
				# Simuler des zones climatiques avec le bruit de base en X/Z
				var temp = noise_base.get_noise_2d(wx * 0.5, wz * 0.5) # Temperature
				var humid = noise_mount.get_noise_2d(wz * 0.5, wx * 0.5) # Humidité
				
				# ALTITUDE PRIORITY (MODIFIED: AIR WORLD)
				if aesthetic_h > height_scale * 0.8: 
					# AIR WORLD VARIATION
					var slope_factor = abs(aesthetic_h - final_h)
					if slope_factor > 2.0: 
						tex_id = 4 # Lightning Gravel (Dark Cliffs)
					elif randf() > 0.6: 
						tex_id = 1 # Fire Rock (Red Test - To Prove change)
					else:
						tex_id = 6 # Lava (Red Test - To Prove change)
						
				elif aesthetic_h > height_scale * 0.65: 
					tex_id = 0 # Forest Floor
				elif aesthetic_h < -15.0: tex_id = 6 # Lava (Deep)
				elif aesthetic_h < -2.0: tex_id = 5 # Water/Sand (Sea Level)
				
				# SLOPE PRIORITY
				elif abs(aesthetic_h - final_h) > 5.0: # Falaise
					if temp > 0.5: tex_id = 1 # Fire Rock (Hot cliff)
					else: tex_id = 4 # Lightning/Gravel (Cold cliff)
					
				# BIOME ZONES (Temperature/Humidity)
				elif temp > 0.4: # HOT ZONES
					if humid > 0.0: tex_id = 3 # Jungle (Hot & Wet)
					else: tex_id = 5 # Desert (Hot & Dry)
				elif temp < -0.4: # COLD ZONES
					tex_id = 2 # Ice
				elif humid < -0.3: # DRY ZONES
					tex_id = 4 # Lightning/Gravel (Wasteland)
				else:
					# TEMPERATE
					if randf() > 0.995: tex_id = 7 # Gold (Rare deposits)
					elif randf() > 0.995: tex_id = 8 # Crystal (Rare deposits)
					elif aesthetic_h < 10.0: tex_id = 0 # Forest Floor
					else: tex_id = 3 # Jungle/Grass
				
				# --- MASSIVE PROOF-OF-LIFE PILLAR at (0,0) ---
				# SUPPRIMÉ : Le terrain fonctionne, on laisse la nature reprendre ses droits.
				# --------------------------------------------
				
				# Écriture Directe Pixel (Hauteur)
				h_map.set_pixel(x, y, Color(aesthetic_h, 0, 0, 1))
				
				c_map.set_pixel(x, y, Color(float(tex_id)/255.0, 0, 0, 1))
		
		# DÉTACHEMENT FINAL POUR FORCER LE RE-UPLOAD GPU
		# On s'assure que le format est RF (32-bit float) pour les hauteurs
		if h_map.get_format() != Image.FORMAT_RF:
			h_map.convert(Image.FORMAT_RF)
			
		region.height_map = h_map
		region.control_map = c_map
		
		# UPDATE CPU CACHE (Crucial pour get_height() et la collision)
		if data.has_method("import_images"):
			# API Terrain3D attend un Array[Image] : [0:Height, 1:Control, 2:Color]
			var images: Array[Image] = []
			images.resize(3)
			images[0] = h_map # Terrain3DRegion.TYPE_HEIGHT
			images[1] = c_map # Terrain3DRegion.TYPE_CONTROL
			
			data.import_images(images, Vector3(rx * r_size, 0, ry * r_size))
		
		print("💾 Region " + str(loc) + " : Synchronisation CPU/GPU effectuée.")
		
	print("✅ Sculpture terminée (Mémoire). Envoi GPU...")
	
	# DEBUG: Vérifier si l'image a bien été écrite
	if not active_regions.is_empty():
		# On check la première région
		var _check_h: Image = active_regions[0].height_map if active_regions[0] is Object else null
		# Si active_regions[0] est Vector2i, il faut récupérer l'objet... (compliqué ici)
		# Bref, on fait confiance au script précédent.
		# On va juste print un message confirmant qu'on passe à l'update.
	
	# FORCE SYNC NUKE (GPU RE-UPLOAD)
	if terrain_node: 
		# Rattachement explicite
		terrain_node.set("storage", data)
		
		# Forcer la reconstruction complète du mesh et des textures
		if data.has_method("force_update_terrain"):
			print("☢️ GPU REBUILD: force_update_terrain(7)...")
			data.force_update_terrain(7) # 7 = Everything
		elif data.has_method("update_heights"):
			data.update_heights()
			data.update_control()
		
		if terrain_node.has_method("request_mesh_update"):
			terrain_node.request_mesh_update()
			
		terrain_node.notify_property_list_changed()
		print("☢️ SYNC COMPLETE: Mesh rebuild triggered.")
		
	await get_tree().process_frame

func _decorate_terrain_async(data):
	print("🌲 Début Décoration Async...")
	_update_ui("Analyse des assets...", 50)
	await get_tree().create_timer(0.1).timeout
	
	var assets = _scan_assets_safe(folder_assets)
	if assets["tree"].is_empty() and assets["rock"].is_empty():
		print("⚠️ Aucun asset trouvé dans " + folder_assets)
		return

	# Nettoyage
	for c in get_children():
		c.queue_free()
	
	var forest_noise = FastNoiseLite.new(); forest_noise.seed = noise_seed + 99
	var region_size = 1024
	if data.has_method("get_region_size"): region_size = data.get_region_size()
	var active_regions = []
	if data.has_method("get_regions_active"): active_regions = data.get_regions_active()
	
	if active_regions.is_empty():
		print("⚠️ Aucune région à décorer.")
		return
	
	var batch = {} # { "path": [Transforms...] }
	var total_lines = active_regions.size() * (region_size / 4) # Step 4
	var processed_lines = 0
	
	for region in active_regions:
		var rx = 0
		var ry = 0
		
		if region is Vector2i:
			rx = region.x
			ry = region.y
		elif region.has_method("get_location"):
			var l = region.get_location()
			rx = l.x
			ry = l.y
		else:
			continue
		
		var start_x = rx * region_size
		var start_z = ry * region_size
		
		# Pas de 4 pour perf
		for x in range(start_x + 8, start_x + region_size - 8, 4):
			# ANTI-FREEZE
			# ANTI-FREEZE
			if processed_lines % 2 == 0: # Yield toutes les 2 lignes (environ)
				await get_tree().process_frame
				var p = 50.0 + (float(processed_lines)/total_lines) * 40.0 # 50% -> 90%
				_update_ui("Végétation...", p)
			processed_lines += 1
			
			for z in range(start_z + 8, start_z + region_size - 8, 4):
				var h = data.get_height(Vector3(x, 0, z))
				if is_nan(h): continue
				
				# Pente
				var norm = data.get_normal(Vector3(x, h, z))
				var slope = norm.angle_to(Vector3.UP)
				
				var type = ""
				var f_val = forest_noise.get_noise_2d(x, z)
				
				if slope > 0.6: # Forte pente
					if randf() > 0.9: type = "rock"
				else:
					if f_val > 0.2: # Forêt
						if randf() < (f_val + 0.2): type = "tree"
					else: # Plaine (Ou Neige)
						# VARIATION NEIGE : Plus de cailloux en haute altitude
						if h > height_scale * 0.7:
							if randf() > 0.95: type = "rock"
						elif randf() > 0.99: type = "rock"
				
				if type != "" and not assets[type].is_empty():
					# AIR WORLD SPECIFIC FILTERING
					var is_high_altitude = (h > height_scale * 0.7)
					var chosen_path = ""
					
					if is_high_altitude:
						# Filter for "Twisted" trees or "Round" rocks for Air World
						var air_candidates = []
						for p in assets[type]:
							var lower_p = p.to_lower()
							if type == "tree" and "twisted" in lower_p: air_candidates.append(p)
							if type == "rock" and "round" in lower_p: air_candidates.append(p)
						
						if not air_candidates.is_empty():
							chosen_path = air_candidates.pick_random()
						else:
							chosen_path = assets[type].pick_random() # Fallback
					else:
						chosen_path = assets[type].pick_random()

					if not batch.has(chosen_path): batch[chosen_path] = []
					
					# Transform
					var t = Transform3D()
					t.origin = Vector3(x, h, z)
					
					# FLOATING ROCKS LOGIC
					if is_high_altitude and type == "rock":
						if randf() > 0.3: # 70% chance to float
							t.origin.y += randf_range(5.0, 25.0) # Float between 5m and 25m
							t.basis = t.basis.scaled(Vector3.ONE * randf_range(2.0, 5.0)) # Giant floating rocks
							# Random Rotation for floating look
							t.basis = t.basis.rotated(Vector3.UP, randf()*TAU).rotated(Vector3.RIGHT, randf()*TAU)

					var up = Vector3.UP.lerp(norm, 0.5 if type == "tree" else 0.9).normalized()
					var right = up.cross(Vector3.FORWARD).normalized()
					var fwd = right.cross(up).normalized()
					
					# Apply base rotation if not already floated crazy
					if not (is_high_altitude and type == "rock"):
						if right.length_squared() > 0.01:
							t.basis = Basis(right, up, fwd)
						t = t.rotated(up, randf() * TAU)
						t = t.scaled(Vector3.ONE * randf_range(0.8, 1.5))
					
					batch[chosen_path].append(t)
	
	# Instanciation par batch (avec await)
	_update_ui("Instanciation des objets...", 90)
	await get_tree().process_frame
	
	var keys = batch.keys()
	for i in range(keys.size()):
		var path = keys[i]
		_create_multimesh(path, batch[path])
		if i % 2 == 0: await get_tree().process_frame # Pause tous les 2 types
		
# --- UTILS ---

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
				if file_name.ends_with(".glb") or file_name.ends_with(".gltf") or file_name.ends_with(".tscn"):
					var lower = file_name.to_lower()
					var full_path = path + "/" + file_name
					if "tree" in lower or "palm" in lower or "sapling" in lower:
						res["tree"].append(full_path)
					elif "rock" in lower or "stone" in lower or "pebble" in lower:
						res["rock"].append(full_path)
			file_name = dir.get_next()

func _create_multimesh(path, transforms):
	if transforms.is_empty(): return
	var scene = load(path)
	if not scene: return
	
	# Mesh extraction (simplifié)
	var mesh = null
	var temp = scene.instantiate()
	var mesh_inst = temp.find_child("MeshInstance3D", true, false)
	# Si c'est un GLB direct, parfois le root est un Node3D
	if not mesh_inst and temp is MeshInstance3D: mesh_inst = temp
	
	if mesh_inst:
		mesh = mesh_inst.mesh
	temp.free()
	
	if not mesh: return
	
	var mmi = MultiMeshInstance3D.new()
	mmi.name = "MMI_" + path.get_file().get_basename()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	mmi.multimesh = mm
	
	add_child(mmi)
	mmi.owner = get_tree().edited_scene_root # Pour sauvegarde scène
	
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

func _ensure_data():
	if not terrain_node: return null
	
	# Si Reset forcé, on ignore ce qui est chargé dans la scène
	# Si Reset forcé, on ignore ce qui est chargé dans la scène
	if force_reset:
		print("♻️ RESET FORCÉ : On détache les anciennes données...")
		terrain_node.set("data", null)
		terrain_node.set("storage", null)
		force_reset = false # <--- FIX: Empêche le reset multiple (ex: lors du TP)
		
	var d = terrain_node.get("data")
	if not d: d = terrain_node.get("storage")
	
	if not d:
		print("✨ Création nouvelles données...")
		# Tenter Terrain3DData d'abord (Version récente)
		d = ClassDB.instantiate("Terrain3DData")
		if not d:
			# Fallback (Version ancienne)
			d = ClassDB.instantiate("Terrain3DStorage") 
		
		if d:
			print("✨ Données créées : ", d.get_class())
			terrain_node.set("data", d)
			terrain_node.set("storage", d)
		else:
			print("❌ IMPOSSIBLE D'INSTANCIER Terrain3DData ou Storage !")
			return null
		
		# 1. RÉCUPÉRER OU CRÉER
	var active_regions = []
	if d.has_method("get_regions_active"):
		active_regions = d.get_regions_active()
		
	# Fallback creation (0,0)
	if active_regions.is_empty():
		print("⚠️ Aucune région. Création forcée de 0,0 avec maps...")
		if d.has_method("add_region"):
			var new_reg = ClassDB.instantiate("Terrain3DRegion")
			if new_reg:
				new_reg.set("location", Vector2i(0,0))
				
				# ALLOCATION DES MAPS (CRUCIAL POUR ÉVITER LES ERREURS)
				var r_size = 1024
				if d.has_method("get_region_size"): r_size = d.get_region_size()
				
				# 1. Height Map (Float 32)
				var img_h = Image.create(r_size, r_size, false, Image.FORMAT_RF)
				if "height_map" in new_reg: new_reg.height_map = img_h
				else: new_reg.set("height_map", img_h)
				
				# 2. Control Map (RGBA 8)
				var img_c = Image.create(r_size, r_size, false, Image.FORMAT_RGBA8)
				img_c.fill(Color(0,0,0,1)) # Init transparent/base
				if "control_map" in new_reg: new_reg.control_map = img_c
				else: new_reg.set("control_map", img_c)
				
				d.add_region(new_reg)
				print("✅ Région (0,0) et Maps allouées.")
			else:
				# Fallback old API
				d.call("add_region", Vector3(0,0,0))
				
	# Refresh
	if d.has_method("get_regions_active"): active_regions = d.get_regions_active()
			
	# VÉRIFICATION CRITIQUE
	if active_regions.is_empty():
		print("❌ ERREUR CRITIQUE: Echec création région.")
		return null
	
	# FORCE ASSIGNMENT TO NODE
	if terrain_node:
		terrain_node.show_checkered = false
		if terrain_node.material:
			terrain_node.material.show_checkered = false
			
		terrain_node.set("data", d)
		terrain_node.set("storage", d)
		if terrain_node.has_method("set_storage"): terrain_node.set_storage(d)
		print("🔗 Data connectée & Checkerboard OFF.")
		
	return d

func _ensure_lighting():
	# 1. NETTOYAGE AGGRESSIF (Éviter les conflits)
	var nodes_to_clean = []
	
	# Chercher partout dans AutoStart et ses enfants (GameWorld, etc.)
	# Chercher partout dans AutoStart et ses enfants (GameWorld, etc.)
	var _root = get_tree().root
	if is_inside_tree():
		# On cherche dans la branche courante
		var st = get_parent()
		for c in st.get_children():
			if c is WorldEnvironment or c.name == "Sun_Gen":
				nodes_to_clean.append(c)
			elif c.name == "GameWorld":
				for cc in c.get_children():
					if cc is WorldEnvironment or cc is DirectionalLight3D:
						nodes_to_clean.append(cc)

	for n in nodes_to_clean:
		print("🗑️ (Lighting) Nettoyage ancien noeud: " + n.name)
		n.queue_free()
	
	# 2. SOLEIL
	var sun = DirectionalLight3D.new()
	sun.name = "Sun_Gen"
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	get_parent().add_child(sun)
	
	# 3. ENVIRONNEMENT (Zelda Sky)
	var env = WorldEnvironment.new()
	env.name = "Env_Gen_Zelda"
	
	var e = Environment.new()
	e.background_mode = Environment.BG_SKY
	
	var mat = ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.35, 0.65, 0.95) # Plus bleu
	mat.sky_horizon_color = Color(0.65, 0.85, 0.95)
	mat.ground_bottom_color = Color(0.2, 0.1, 0.0) # Terre sombre
	
	var sky_obj = Sky.new()
	sky_obj.sky_material = mat
	e.sky = sky_obj
	
	# Ambience
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	# e.tonemap_mode = 0 # Désactivé pour compatibilité
	
	env.environment = e
	get_parent().add_child(env)
	
	print("☀️ Zelda Sky & Lighting déployés (Environnement unique forcé).")
	
func _spawn_towers(data):
	print("🗼 Spawning Sheikah Towers...")
	var region_size = 1024
	if data.has_method("get_region_size"): region_size = data.get_region_size()
	
	# On place 1 tour par "Zone implicite" de 500x500m
	var tower_scene = load("res://Tools/MapTower.tscn")
	if not tower_scene: return
	
	var active_regions = []
	if data.has_method("get_regions_active"): active_regions = data.get_regions_active()
	
	# SPAWN TOWER NEAR PLAYER (DEBUG/CONVENIENCE)
	var t_near = tower_scene.instantiate()
	var h_near = data.get_height(Vector3(50, 0, 50))
	if not is_nan(h_near):
		t_near.position = Vector3(50, h_near, 50)
		t_near.tower_id = "Tower_Spawn_Near"
		add_child(t_near)
		t_near.owner = get_tree().edited_scene_root
		print("🗼 Tour 'Proche' placée en (50, 50)")

	for region in active_regions:
		var rx = region.x if region is Vector2i else region.get_location().x
		var ry = region.y if region is Vector2i else region.get_location().y
		
		var center_x = rx * region_size + region_size / 2.0
		var center_z = ry * region_size + region_size / 2.0
		
		# Place 1 tower exactly in the center of the region for now
		var tx = center_x
		var tz = center_z
		var h = data.get_height(Vector3(tx, 0, tz))
		if is_nan(h): continue
		
		var t = tower_scene.instantiate()
		t.position = Vector3(tx, h, tz)
		t.tower_id = "Tower_" + str(rx) + "_" + str(ry)
		add_child(t)
		t.owner = get_tree().edited_scene_root
		print("🗼 Tower placed at: ", t.position)

func _ensure_theme_assets():
	if not terrain_node: return
	# FIX: Ne pas return si les assets existent mais sont vides !
	# FORCE RELOAD ASSETS (User reports white textures)
	# if terrain_node.assets and terrain_node.assets.get_texture_count() > 0: 
	# 	print("🎨 Assets déjà chargés (" + str(terrain_node.assets.get_texture_count()) + "). Skip.")
	# 	return 
	
	print("🎨 (Re)Chargement des Textures Zelda...")
	
	var assets_res = ClassDB.instantiate("Terrain3DAssets")
	if not assets_res:
		print("⚠️ Impossible d'instancier Terrain3DAssets")
		return

	# Helper pour créer une texture avec échelle UV
	var _create_tex = func(tex_name, path_color, scale = 0.5):
		print("🔍 Tentative création texture: " + tex_name)
		var tex = ClassDB.instantiate("Terrain3DTextureAsset")
		if not tex: 
			print("❌ ECHEC Instantiation Terrain3DTextureAsset")
			return null
		
		tex.name = tex_name
		tex.albedo_color = Color.WHITE
		tex.uv_scale = scale
		
		if ResourceLoader.exists(path_color):
			var t = load(path_color)
			if t:
				print("   ✅ Image chargée: " + path_color + " (" + t.get_class() + ")")
				tex.albedo_texture = t
				
				# Verify assignment
				if tex.albedo_texture != t:
					print("   ❌ ECHEC Assignation albedo_texture ! Property missing?")
			else:
				print("   ❌ ÉCHEC load(): " + path_color)
			
			# Auto-détection normal map
			var path_normal = path_color.replace("_Color", "_NormalGL")
			if not ResourceLoader.exists(path_normal):
				path_normal = path_color.replace("_Color", "_Normal")
			
			if ResourceLoader.exists(path_normal):
				var n = load(path_normal)
				if n: tex.normal_texture = n
		else:
			print("⚠️ Fichier manquant: " + path_color)
			
		return tex

	var list = []
	var tex_data = [
		# Nom, Path, Scale (Plus grand = Plus de répétition = Moins lisse)
		["DEBUG_LAVA_WORLD", "res://Assets/3D/Nature/Lava004_1K-JPG/Lava004_1K-JPG_Color.jpg", 0.5], # 0 IS LAVA
		# ["Fire_Rock", "res://Assets/3D/Nature/Rock030_1K-JPG/Rock030_1K-JPG_Color.jpg", 0.5], # 1
		# ["Ice", "res://Assets/3D/Nature/Ice002_1K-JPG/Ice002_1K-JPG_Color.jpg", 0.8], # 2
		# ["Jungle_Grass", "res://Assets/3D/Nature/Grass001_1K-JPG_Color.jpg", 0.3], # 3
		# ["Lightning_Gravel", "res://Assets/3D/Nature/Gravel040_1K-JPG/Gravel040_1K-JPG_Color.jpg", 0.5], # 4
		# ["Desert_Sand", "res://Assets/3D/Nature/Ground054_1K-JPG/Ground054_1K-JPG_Color.jpg", 0.4], # 5
		# ["Lava", "res://Assets/3D/Nature/Lava004_1K-JPG/Lava004_1K-JPG_Color.jpg", 0.5], # 6
		# ["Gold_Paving", "res://Assets/3D/Nature/PavingStones055_1K-JPG/PavingStones055_1K-JPG_Color.jpg", 1.0], # 7 (Petit pavage)
		# ["Crystal_Rock", "res://Assets/3D/Nature/Rock023_1K-JPG/Rock023_1K-JPG_Color.jpg", 0.5], # 8
		# ["Snow_High", "res://Assets/3D/Nature/Snow003_1K-JPG/Snow003_1K-JPG_Color.jpg", 4.0] # 9 (NEIGE TRES GRANULEUSE/DÉTAILLÉE)
	]
	
	for entry in tex_data:
		var t = _create_tex.call(entry[0], entry[1], entry[2])
		if t: list.append(t)
	
	# API SAFE ASSIGNMENT
	if assets_res.has_method("set_textures"):
		assets_res.call("set_textures", list)
	elif "texture_list" in assets_res:
		assets_res.texture_list = list
	else:
		assets_res.set("textures", list)
		
	terrain_node.assets = assets_res
	print("✅ 10 Textures Biomes appliquées.")
	
	# ON SCREEN DEBUG
	var canvas = CanvasLayer.new()
	var lbl = Label.new()
	lbl.text = "Texture Count: " + str(list.size()) + "\nFirst Tex: " + str(list[0].name)
	lbl.position = Vector2(100, 100)
	lbl.modulate = Color.RED
	lbl.scale = Vector2(2,2)
	canvas.add_child(lbl)
	get_parent().add_child(canvas)


func _teleport_player():
	var p = get_tree().get_first_node_in_group("Player")
	if not p:
		p = get_parent().find_child("Player", true, false)
	
	if p:
		# FIX: Ne pas rappeler _ensure_data() qui pourrait trigger un reset !
		var d = terrain_node.get("data")
		if not d: d = terrain_node.get("storage")
		
		var h = height_scale + 10.0 # Default safe height
		if d and d.has_method("get_height"): 
			var ground_h = d.get_height(Vector3(0, 0, 0))
			if not is_nan(ground_h) and ground_h > -500:
				h = ground_h + 2.0
				
		p.global_position = Vector3(0, h, 0)
		print("📍 Player TP: " + str(p.global_position))

# --- UI MANAGMENT ---

func _show_loading_screen():
	if _ui_instance: return
	if loading_screen_scene:
		_ui_instance = loading_screen_scene.instantiate()
		get_tree().root.call_deferred("add_child", _ui_instance)

func _hide_loading_screen():
	if _ui_instance:
		_ui_instance.queue_free()
		_ui_instance = null

func _update_ui(text, val):
	if _ui_instance and _ui_instance.has_method("update_status"):
		_ui_instance.update_status(text, val)

# --- EDITOR BUTTON ---
func _on_button_generate(val):
	if val and is_inside_tree():
		_start_safe_generation_sequence()

func _spawn_enemies_async(data):
	print("⚔️ Spawning Enemies...")
	var region_size = 1024
	if data.has_method("get_region_size"): region_size = data.get_region_size()
	
	var script_enemy = load("res://Entities/Enemies/Enemy.gd")
	var scene_skeleton = load("res://Assets/3D/Monsters/Monster Pack Animated by Quaternius/FBX/Skeleton.fbx")
	var scene_slime = load("res://Assets/3D/Monsters/Monster Pack Animated by Quaternius/FBX/Slime.fbx")
	
	if not script_enemy or not scene_skeleton:
		print("⚠️ Missing Enemy assets via Load")
		return

	var active_regions = []
	if data.has_method("get_regions_active"): active_regions = data.get_regions_active()

	for region in active_regions:
		var rx = region.x if region is Vector2i else region.get_location().x
		var ry = region.y if region is Vector2i else region.get_location().y
		
		var start_x = rx * region_size
		var start_z = ry * region_size
		
		# Density: 1 enemy every ~50m
		for i in range(20): # 20 enemies per region
			var x = start_x + randf() * region_size
			var z = start_z + randf() * region_size
			var h = data.get_height(Vector3(x, 0, z))
			
			if is_nan(h): continue
			
			# Don't spawn under water or too high
			if h < 0: continue 
			
			# Choose Type
			var is_slime = randf() > 0.5
			var model_scene = scene_slime if is_slime else scene_skeleton
			if not model_scene: model_scene = scene_skeleton
			
			# CONSTRUCT ENEMY
			var enemy = CharacterBody3D.new()
			enemy.name = "Enemy_Reg" + str(rx) + "_" + str(i)
			enemy.set_script(script_enemy)
			
			# Stats Scaler based on distance
			var dist = Vector2(x, z).length()
			var lvl = 1 + int(dist / 200.0) # +1 Level every 200m
			enemy.level = lvl
			enemy.enemy_name = "Slime" if is_slime else "Skeleton"
			
			# Visuals
			var vis = model_scene.instantiate()
			vis.name = "Visuals"
			enemy.add_child(vis)
			
			# Scale Model (FBX are often small/large)
			vis.scale = Vector3.ONE * 1.5 
			
			# Collider
			var col = CollisionShape3D.new()
			var cap = CapsuleShape3D.new()
			cap.radius = 0.5
			cap.height = 1.8
			col.shape = cap
			col.position.y = 0.9
			enemy.add_child(col)
			
			# 3D UI (Billboard Health)
			var label = Label3D.new()
			label.name = "HealthLabel"
			label.text = "Lvl " + str(lvl) + " " + enemy.enemy_name
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position.y = 2.2
			label.font_size = 32
			label.outline_render_priority = 0
			enem