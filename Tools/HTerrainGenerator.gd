@tool
extends Node

# --- CONFIGURATION HTerrain ---
@export_category("HTerrain Generator")
@export var button_generate: bool = false : set = _on_button_generate
@export var button_force_reset: bool = false : set = _on_button_force_reset
@export var folder_assets: String = "res://Assets/"
@export var map_size: int = 2049 # 513, 1025, 2049, 4097
@export var height_scale: float = 200.0

# TEXTURE PATHS (10 Biomes)
# These are now just for reference/legacy, actual textures are set directly below
const TEX_PATHS = [
	"res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/Textures/PathRocks_Diffuse.png", # ID 0: Grass Main (TEST ROCK)
	"res://Assets/3D/Nature/Rock023_1K-JPG/Rock023_1K-JPG_Color.jpg", # ID 1: Cliff Moss
	"res://Assets/3D/Nature/Ground068_1K-JPG/Ground068_1K-JPG_Color.jpg", # ID 2: Beach
	"res://Assets/3D/Nature/Ground054_1K-JPG/Ground054_1K-JPG_Color.jpg", # ID 3: Dunes
	"res://Assets/3D/Nature/Rock030_1K-JPG/Rock030_1K-JPG_Color.jpg", # ID 4: Cliff (Was Grass Main)
	"res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/Textures/Flowers.png", # ID 5: Grass Wild (Flowers)
	"res://Assets/3D/Nature/Gravel040_1K-JPG/Gravel040_1K-JPG_Color.jpg", # ID 6: Forest
	"res://Assets/3D/Nature/Gravel040_1K-JPG/Gravel040_1K-JPG_Color.jpg", # ID 7: Mountain Base
	"res://Assets/3D/Nature/Snow003_1K-JPG/Snow003_1K-JPG_Color.jpg", # ID 8: Snow
	"res://Assets/3D/Nature/PavingStones055_1K-JPG/PavingStones055_1K-JPG_Color.jpg" # ID 9: Mud
]

# Ensure we have 10 textures in logic, re-using if file missing

var _ui_instance = null
var loading_screen_scene = preload("res://UI/LoadingScreen.tscn")
static var _generating_lock = false

func _ready():
	print("✅ HTerrainGenerator Node READY and script ALIVE! Path: ", get_path(), " | ID: ", get_instance_id())
	if not Engine.is_editor_hint():
		# Auto-generate on game start for user convenience
		# WAIT longer to ensure all systems (AutoLoads, Window) are stable
		await get_tree().create_timer(1.0).timeout 
		if is_inside_tree():
			_start_generation()

func _exit_tree():
	_generating_lock = false # Safety reset


func _on_button_generate(val):
	if not val: return # PREVENT RECURSION
	if is_inside_tree():
		_start_generation()
	button_generate = false # Reset toggle in inspector

func _on_button_force_reset(val):
	if val:
		_generating_lock = false
		print("🔓 Generation Lock FORCED RESET. You can now generate again.")
		button_force_reset = false # Toggle back off

# --- GENERATION LOGIC ---
func _start_generation():
	# 1. LOCK CHECK (Prevent Duplicate Execution)
	if _generating_lock:
		print("⚠️ GENERATION REJECTED: Already in progress. If stuck, click 'Button Force Reset' in the inspector!")
		return
	_generating_lock = true
	
	GameManager.terrain_node = null # Detach immediately to prevent invalid access
	
	print("🔒 Generator Locked. Starting Sequence...")

	# 1. CHECK PLUGIN (Robust Check)
	# ... (Plugin check code normally here, assumed unchanged) ...

	# 2. CLEANUP (Destroy Old Nodes)
	# Find by group AND by name to be sure
	var nodes_to_burn = get_tree().get_nodes_in_group("ActiveTerrain")
	if get_tree().current_scene:
		var named_node = get_tree().current_scene.find_child("HTerrain_Active", true, false)
		if named_node and not named_node in nodes_to_burn:
			nodes_to_burn.append(named_node)
	
	for node in nodes_to_burn:
		if is_instance_valid(node):
			print("🔥 Burning Ghost Node: ", node.name)
			node.queue_free()
			# Don't immediate free, physics server dislikes it.
	
	print("⏳ Waiting for cleanup...")
	await get_tree().process_frame
	await get_tree().process_frame # Double yield for physics frame

	var hterrain_script = load("res://addons/zylann.hterrain/hterrain.gd")
	var hterrain_data_script = load("res://addons/zylann.hterrain/hterrain_data.gd")
	
	if not hterrain_script or not hterrain_data_script:
		printerr("❌ ERREUR: Scripts HTerrain introuvables dans 'res://addons/zylann.hterrain/'.")
		_generating_lock = false; return
		
	# 1.5 CLEANUP LEGACY & GHOST NODES (Nuclear Option)
	var root = get_tree().root
	# 1.5 NUCLEAR CLEANUP: Completely destroy old terrain to force fresh generation
	var old_terrain = null
	if get_tree().current_scene:
		old_terrain = get_tree().current_scene.find_child("HTerrain", true, false)
	elif get_tree().edited_scene_root:
		old_terrain = get_tree().edited_scene_root.find_child("HTerrain", true, false)

	if old_terrain:
		print("☢️ Nuclear Cleanup: Destroying old HTerrain node...")
		old_terrain.name = "HTerrain_TRASH" # Rename to avoid conflict
		old_terrain.queue_free() # Destroy entirely
	
	_cleanup_recursive(root)
	# WAIT FOR CLEANUP TO FINISH (queue_free happens at frame end)
	print("⏳ Waiting for cleanup...")
	if is_inside_tree(): await get_tree().process_frame
	if is_inside_tree(): await get_tree().process_frame
	
	# 2. UI
	_show_loading_screen()
	if is_inside_tree(): await get_tree().process_frame
	
	# DEBUG: PRINT SCENE TREE TO FIND GHOSTS
	print("🌳 SCENE TREE DUMP (Finding hidden trees):")
	_print_tree_recursive(get_parent())
	
	print("⏳ Post-Cleanup Wait...")
	await get_tree().create_timer(0.5).timeout # Explicit timer wait
	print("🚀 Starting Generation Sequence...")
	
	_update_ui("Préparation HTerrain...", 10)
	
	# 3. SETUP TERRAIN NODE
	var terrain_node = hterrain_script.new() # Instantiate from script
	terrain_node.name = "HTerrain_Active"
	if is_inside_tree(): await get_tree().process_frame # Yield
	terrain_node.add_to_group("ActiveTerrain")
	terrain_node.scale = Vector3(1, 1, 1) # FORCE NO SCALE

	terrain_node.transform.basis = Basis() # FORCE NO ROTATION
	
	# CRITICAL: Add to Main Scene (AutoStart) NOT WorldGenerator to persist
	var parent_node = get_tree().current_scene
	if not parent_node:
		parent_node = get_tree().root
	parent_node.add_child(terrain_node)
	# In running game, owner should be the scene root or null.
	terrain_node.owner = parent_node
	terrain_node.transform.origin = Vector3(0, 0, 0)

		
	# 4. SETUP DATA
	terrain_node.centered = false
	terrain_node.map_scale = Vector3(1, 1, 1)
	terrain_node.scale = Vector3(1, 1, 1) # Double safety
	terrain_node.transform.basis = Basis() # Triple safety
	
	var data = terrain_node.get("data")
	print("🔗 LINKING TERRAIN TO GAME MANAGER (ID: ", GameManager.get_instance_id(), ")")
	GameManager.terrain_node = terrain_node
	# GameManager.terrain_data will be assigned after data creation
	print("🔗 LINK SUCCESS: ", GameManager.terrain_node)
	
	# ENABLE COLLISION EARLY (Critical for Physics)
	if terrain_node.has_method("set_collision_enabled"):
		terrain_node.set_collision_enabled(true)
		print("🧱 HTerrain Collision ENABLED (Early Init).")
	else:
		print("⚠️ HTerrain 'set_collision_enabled' not found!")
	
	# DETECT CORRUPTION / LEGACY DATA
	var needs_reset = false
	if not data: needs_reset = true
	elif button_force_reset: needs_reset = true
	elif "Terraindata" in data.resource_path: # Detect old folder
		print("⚠️ Legacy/Corrupted Data path detected: " + data.resource_path)
		needs_reset = true
	
	if needs_reset:
		print("📦 Creating new HTerrainData (Forcing Fresh Start)...")
		data = hterrain_data_script.new() # RESTORED
		# Trace
		if is_inside_tree(): await get_tree().process_frame # Yield before resize
		data.resize(map_size) # Valid sizes: 513, 1025...
		if is_inside_tree(): await get_tree().process_frame # Yield after resize
		
		if terrain_node.has_method("set_data"):
			terrain_node.set_data(data)
		else:
			terrain_node.set("data", data)
			terrain_node.set("terrain_data", data)

			
		# Set Resource Path for saving
		var save_path = "res://Assets/HTerrainData"
		if not DirAccess.dir_exists_absolute(save_path):
			DirAccess.make_dir_recursive_absolute(save_path)
		
		var full_path = save_path + "/data.hterrain"
		print("💾 Saving Terrain Data to: ", full_path)
		
		# CRITICAL: Use take_over_path to avoid cyclic/empty path errors
		data.take_over_path(full_path)
		# var err = ResourceSaver.save(data, full_path)
		# if err != OK:
		# 	printerr("❌ Failed to save HTerrainData: ", err)

			
	# CRITICAL: Now that data is created/assigned, link it globally
	GameManager.terrain_data = data
	print("🔗 LINKED NEW DATA to GameManager.")
	
	# 5. TURBO PERFORMANCE & SHADER
	terrain_node.set_lod_scale(2.0) # Optimized for large scale
	terrain_node.map_scale = Vector3(4, 1, 4) # 🌍 HUGE WORLD (2048 * 4 = 8km)
	
	# FORCE MULTISPLAT16 SHADER FOR ARTISTIC PAINTING (10 TEXTURES)
	# FORCE MULTISPLAT16 SHADER FOR ARTISTIC PAINTING (10 TEXTURES)
	if terrain_node.get_shader_type() != "MultiSplat16":
		print("🎨 Switching to MultiSplat16 Shader for Artistic Painting...")
		terrain_node.set_shader_type("MultiSplat16")
		
	# LAPTOP OPTIMIZATION (As requested)
	print("💻 Applying Laptop Optimizations (View Distance: 60, Wind: On)...")
	terrain_node.set("detail_view_distance", 60.0) # Reduce draw distance
	terrain_node.set("ambient_wind", 0.5) # Wind Speed
	# Some versions use a specific method or property for enabling wind

	
	# Wait for data assignment
	await get_tree().process_frame
	
	# 5. SCULPTURE
	_update_ui("Sculpture du Monde...", 30)
	await _sculpt_hterrain(terrain_node, data)
	
	# 6. TEXTURES
	_update_ui("Peinture Artistique (Genshin Style)...", 60)
	await _paint_hterrain(terrain_node, data)
	
	# 7. DETAILS (Grass Blades)
	_update_ui("Semis de l'Herbe...", 70)
	_paint_details(terrain_node, data)
	
	# 8. DECORATION (Trees/Rocks - AAA)
	_update_ui("Plantation Détaillée (Arbres, Rochers)...", 80)
	# CRITICAL FIX: Force collider update before placing physical decor
	if terrain_node.has_method("update_collider"): terrain_node.update_collider()
	for i in range(10): await get_tree().physics_frame 
	
	await _place_decorations(terrain_node, data)
	var assets = {} # Legacy compat if structure needs it
	
	# 8. OCEAN
	_update_ui("Remplissage Océan...", 85)
	_add_ocean()
	
	# 9. CIVILIZATION (AAA)
	_update_ui("Construction des Villes...", 88)
	_add_structures(terrain_node, data, assets)

	
	# 10. DAY/NIGHT CYCLE
	_update_ui("Allumage du Soleil...", 90)
	_setup_daynight()
	
	# 11. TELEPORT POINTS
	_update_ui("Génération des Points de Téléportation...", 92)
	var tp_gen_script = load("res://Tools/TeleportGenerator.gd")
	if tp_gen_script:
		var tp_gen = tp_gen_script.new()
		# Clean old points first? TeleportGenerator creates a container "TeleportPoints".
		# TeleportGenerator doesn't seem to clean up.
		# Let's clean up here.
		var old_tp = get_parent().find_child("TeleportPoints", true, false)
		if old_tp: old_tp.queue_free()
		
		tp_gen.generate_points(get_parent(), terrain_node)
		print("✅ Teleport Points Sequence Complete.")

	# 12. TELEPORT PLAYER
	_update_ui("Placement du Joueur...", 95)
	_teleport_player(terrain_node, data)
	
	# 13. FINISH
	_update_ui("Terminé !", 100)
	await get_tree().create_timer(1.0).timeout
	_hide_loading_screen()
	print("✅ Génération HTerrain Terminée.")
	_generating_lock = false

func _setup_daynight():
	var cycle = get_parent().find_child("DayNightCycle", true, false)
	if cycle: return # Already exists
	
	print("☀️ Adding Day/Night Cycle...")
	cycle = Node3D.new()
	cycle.name = "DayNightCycle"
	cycle.set_script(load("res://Tools/DayNightCycle.gd"))
	get_parent().add_child(cycle)
	cycle.owner = get_tree().edited_scene_root

func _add_ocean():
	# Simple Ocean Plane
	var ocean = get_parent().find_child("OceanPlane", true, false)
	if ocean: ocean.queue_free()
	
	var mesh = PlaneMesh.new()
	var scale_factor = 4.0 # Match terrain map_scale
	mesh.size = Vector2(map_size*scale_factor*2, map_size*scale_factor*2) # Infinite Ocean
	
	var mat = ShaderMaterial.new()
	mat.shader = load("res://Assets/Shaders/StylizedWater.gdshader")
	mat.set_shader_parameter("albedo", Color(0.0, 0.4, 0.9))
	mat.set_shader_parameter("albedo_deep", Color(0.0, 0.1, 0.4))
	mat.set_shader_parameter("metallic", 0.1)
	mat.set_shader_parameter("roughness", 0.02)
	mat.set_shader_parameter("specular", 0.5)
	mesh.material = mat
	
	var ocean_node = MeshInstance3D.new()
	ocean_node.name = "OceanPlane"
	ocean_node.mesh = mesh
	ocean_node.position.y = 2.5 # Water Level
	
	get_parent().add_child(ocean_node)
	ocean_node.owner = get_tree().edited_scene_root
	print("🌊 Ocean added at height 2.5")

func _teleport_player(_terrain, data):
	var player = get_parent().find_child("Player", true, false)
	if not player: return
	
	var res = data.get_resolution()
	var img_idx = data.get_image(6)
	
	var spawn_pos = Vector2(res / 2, res / 2)
	var found_grass = false
	
	# FIND A GRASS BIOME (Scan in a spiral or grid)
	if img_idx:
		print("🔍 Searching for Grass spawn (ID 4 or 5)...")
		# 1st Pass: Center 50%
		var step = int(res / 32.0)
		for pass_idx in range(2):
			var start = int(res * 0.25) if pass_idx == 0 else 0
			var end = int(res * 0.75) if pass_idx == 0 else res
			if pass_idx == 1: 
				print("🔍 Deep Dive Search (Whole Map)...")
				step = int(res / 16.0)
			
			for z in range(start, end, step):
				for x in range(start, end, step):
					var b_id = int(img_idx.get_pixel(x, z).r * 255.0)
					if b_id == 4 or b_id == 5: # ID_GRASS_MAIN or ID_GRASS_WILD
						spawn_pos = Vector2(x, z)
						found_grass = true
						break
				if found_grass: break
			if found_grass: break

	
	# GET WORLD POSITION
	var wx = spawn_pos.x * _terrain.map_scale.x
	var wz = spawn_pos.y * _terrain.map_scale.z
	var h = data.get_height_at(int(spawn_pos.x), int(spawn_pos.y)) * _terrain.map_scale.y
	player.global_position = Vector3(wx, h + 5.0, wz) # +5m Safety Drop
	
	# IDENTIFY BIOME
	var biome_names = ["Grass", "CliffMoss", "Beach", "Dunes", "Cliff", "WildGrass", "Forest", "Mountain", "Snow", "Mud"]
	if img_idx:
		var b_id = int(img_idx.get_pixel(int(spawn_pos.x), int(spawn_pos.y)).r * 255.0)
		var b_name = biome_names[b_id] if b_id < biome_names.size() else "Unknown"
		print("📍 PLAYER SPAWN: Biome [" + str(b_id) + ": " + b_name + "] at " + str(player.global_position))
		if found_grass: print("✨ Found a nice grass spot for you!")
		else: print("ℹ️  No grass found in center, spawning at Map Center.")
	else:
		print("📍 Player teleported to: " + str(player.global_position))


func _sculpt_hterrain(node, data):
	var img = data.get_image(0) # 0 = HEIGHT
	if not img: return
	
	# HTerrain uses R channel float
	var w = img.get_width()
	var h = img.get_height()
	
	print("⛰️ Sculpting AAA MASTERPIECE (Zelda/Genshin Hybrid) " + str(w) + "x" + str(h) + "...")
	
	# 1. MACRO GEOGRAPHY (The "Handcrafted" Feel)
	# Defines where the continents, oceans, and soaring mountain ranges are.
	var noise_geo = FastNoiseLite.new()
	noise_geo.seed = randi()
	noise_geo.frequency = 0.001
	noise_geo.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_geo.fractal_octaves = 2
	
	# 2. MOUNTAIN ARCHITECTURE (Sharp, Dangerous, Epic)
	var noise_mtn = FastNoiseLite.new()
	noise_mtn.seed = randi() + 1
	noise_mtn.frequency = 0.003
	noise_mtn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_mtn.fractal_octaves = 5 # Detailed ridges
	
	# 3. PLAINS ARCHITECTURE (Playable Terraces)
	var noise_plain = FastNoiseLite.new()
	noise_plain.seed = randi() + 2
	noise_plain.frequency = 0.005
	noise_plain.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_plain.fractal_octaves = 3
	
	for y in range(h):
		if y % 50 == 0: await get_tree().process_frame
		for x in range(w):
			# A. Geography Mask: -1 (Ocean) -> 0 (Plains) -> 1 (High Mountains)
			var geo = noise_geo.get_noise_2d(x, y) 
			
			# B. Calculate Raw Heights
			var h_mtn = abs(noise_mtn.get_noise_2d(x, y)) # 0..1 Ridged
			h_mtn = pow(h_mtn, 2.0) * 1.5 # Sharpen peaks significantly
			
			var h_plain = noise_plain.get_noise_2d(x, y) * 0.5 + 0.5 # 0..1 Smooth
			h_plain *= 0.15 # Low amplitude (max 15%)
			
			# C. Apply TERRACING (The "Zelda" look)
			# Only terrace the plains to make them walkable/buildable
			var steps = 15.0
			var h_plain_terraced = round(h_plain * steps) / steps
			
			# D. Blending (The "Artist's Touch")
			var final_h = 0.0
			
			if geo < -0.2:
				final_h = 0.0 # Ocean Floor
			elif geo < 0.3:
				# PLAINS (Terraced)
				# Smooth blend from water to plains
				var t = inverse_lerp(-0.2, 0.3, geo)
				# Lerp from Sea Level to Terraced Plains
				final_h = lerp(0.01, h_plain_terraced, t)
			else:
				# MOUNTAINS (Sharp Ridges)
				# Transition from Plains to Mountains
				var t = inverse_lerp(0.3, 0.8, geo)
				# Use smoothstep for organic transition
				t = smoothstep(0.0, 1.0, t)
				final_h = lerp(h_plain, h_mtn, t)
			
			var pixel_val = final_h * 600.0 # Force 600m Scale here regardless of variable
			if pixel_val < 0: pixel_val = 0
			
			img.set_pixel(x, y, Color(pixel_val, 0, 0, 1))
			
	data.notify_region_change(Rect2(0, 0, w, h), 0) # Update Height
	
	# CRITICAL: Force Normal Map Update (HTerrain usually does this on notify, but let's be safe)
	# No explicit method on data, but let's wait a frame
	await get_tree().process_frame
	
	# CRITICAL: Force Collider and Visual Update
	if node.has_method("update_collider"):
		node.update_collider()
	
	# Force Global Transform Update
	node.force_update_transform()

func _paint_hterrain(node, data):
	_update_ui("Peinture Artistique (Genshin Style)...", 60)
	
	# Load and use the Artistic Painter Tool
	var painter = load("res://Tools/HTerrainArtisticPainter.gd").new()
	if painter:
		painter.paint_terrain(node, data, TEX_PATHS)
		# Force shader update to ensure MultiSplat16 is active
		node.set_shader_type("MultiSplat16")
	else:
		printerr("❌ Failed to load HTerrainArtisticPainter!")

func _paint_details(terrain, data):
	var grass_tex_path = "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/Textures/Grass.png"
	var grass_tex = load(grass_tex_path)
	if not grass_tex:
		print("⚠️ Grass texture not found. Skipping details.")
		return

	# 1. Setup Detail Texture Set (Modern Way)
	var detail_layer
	var layers = terrain.get_detail_layers()
	if layers.size() > 0:
		detail_layer = layers[0]
	else:
		print("✨ Creating new Detail Layer node...")
		var layer_script = load("res://addons/zylann.hterrain/hterrain_detail_layer.gd")
		if layer_script:
			detail_layer = layer_script.new()
			detail_layer.name = "GrassLayer"
			detail_layer.layer_index = 0
			terrain.add_child(detail_layer)
			detail_layer.owner = terrain.owner
			
	if detail_layer:
		detail_layer.texture = grass_tex
		print("🌿 Grass Texture Set on Layer 0.")
		
		# AUTOMATIC INTERACTIVE GRASS SHADER
		var grass_shader = load("res://Assets/Shaders/InteractiveGrass.gdshader")
		if grass_shader:
			# Use exposed property 'custom_shader' instead of material_override
			detail_layer.custom_shader = grass_shader
			print("✅ Interactive Grass Shader applied.")
	else:
		print("⚠️ Failed to create/find Detail Layer.")
	
	# 2. Get Detail Map (Type 9 corresponds to CHANNEL_DETAIL usually, checking logic...)
	# Zylann HTerrain: CHANNEL_DETAIL = 10? No.
	# Let's try to access the map by index.
	# map_type is defined in HTerrainData.
	# Let's use the safer `get_image(channel)` where channel is likely 9? 
	# Actually, let's look at how we got height (0).
	
	# Safe bet: We assume the detail map exists or we create it.
	# Standard HTerrain usually has Detail 0 enabled by default if configured?
	# Let's try adding it.
	
	# Map Type ID for Detail 0 is actually tricky without constants. 
	# Let's guess 8 (Splat) or something.
	# WAIT! We can iterate pixels of the Index Map (We know that exists) and existing detail map?
	
	# Let's brute force valid map types? No.
	# Let's rely on `data` being `HTerrainData`.
	# It has `CHANNEL_DETAIL = 3` in some versions, or `CHANNEL_SPLAT`...
	
	# ALTERNATIVE: Use the `get_image` with specific integer.
	# Based on common versions:
	# 0: Height
	# 1: Normal
	# 2: Color
	# 3: Splat
	# ...
	# 9 or 10: Detail?
	
	# Let's use a robust approach:
	# Assume index map (6) tells us where grass is.
	# We need to write to Detail Map 0.
	
	# Let's check if we can `call` a method on data to get the type id.
	# `data.CHANNEL_DETAIL` might work if it's a static const on the script specific, but data is an instance.
	# `load("res://addons/zylann.hterrain/hterrain_data.gd").CHANNEL_DETAIL` -> This is the way.
	
	var hterrain_data_script = load("res://addons/zylann.hterrain/hterrain_data.gd")
	var channel_detail = hterrain_data_script.CHANNEL_DETAIL # Usually 4 or similar
	
	var img_detail = data.get_image(channel_detail)
	if not img_detail:
		print("✨ Adding Detail Map...")
		data._edit_add_map(channel_detail)
		img_detail = data.get_image(channel_detail)
		
	if not img_detail:
		print("❌ Could not get Detail Map.")
		return
		
	var w = img_detail.get_width()
	var h = img_detail.get_height()
	
	# We interpret Index Map (Channel 6)
	var img_index = data.get_image(6)
	if not img_index: return
	
	# Resize logic if maps differ (Detail map often matches resolution)
	var w_idx = img_index.get_width()
	var scale_factor = float(w_idx) / float(w)
	
	print("🌿 Planting Grass Blades on " + str(w*h) + " pixels...")
	
	for y in range(h):
		if y % 50 == 0: await get_tree().process_frame
		for x in range(w):
			# Sample Index Map
			var ix = int(x * scale_factor)
			var iy = int(y * scale_factor)
			
			var pixel = img_index.get_pixel(ix, iy)
			var biome = int(pixel.r * 255.0)
			
			# Grass Biomes: 4 (Main), 5 (Wild), 6 (Forest)
			if biome == 4 or biome == 5 or biome == 6:
				# Paint density (0..1)
				# 0.5 to 1.0 for variety
				var density = randf_range(0.5, 1.0)
				# HTerrain detail map stores density in R channel (usually)
				img_detail.set_pixel(x, y, Color(density, 0, 0, 1))
			else:
				img_detail.set_pixel(x, y, Color(0, 0, 0, 0))
				
	data.notify_region_change(Rect2(0,0,w,h), channel_detail)
	print("✅ Grass Planted.")

	data.notify_region_change(Rect2(0,0,w,h), channel_detail)
	print("✅ Grass Planted.")


# --- DECORATION (Chunked for Performance) ---
# Each chunk is a Node3D containing MultiMeshes. This allows Frustum Culling.
const CHUNK_SIZE = 512.0 # Single massive chunk for 513 maps to minimize draw calls

func _decorate_hterrain(terrain, data):
	var assets = await _scan_assets(folder_assets)
	if assets["tree"].is_empty() and assets["rock"].is_empty():
		print("❌ No assets found in folders!")
		return assets
	print("✅ Loaded: " + str(assets["tree"].size()) + " trees and " + str(assets["rock"].size()) + " rocks.")
		
	# 1. CLEANUP ALL OLD VEGETATION (Loop to catch duplicates)
	while true:
		var old_veg = get_parent().find_child("Vegetation", true, false)
		if old_veg: 
			old_veg.name = "Vegetation_Deleted" # Rename to avoid conflict
			old_veg.queue_free()
		else:
			break
	
	var veg_root = Node3D.new()
	veg_root.name = "Vegetation"
	# PARENT TO SCENE ROOT TO PERSIST
	get_tree().current_scene.add_child(veg_root)
	veg_root.owner = get_tree().edited_scene_root
	veg_root.transform = Transform3D() 
	
	var noise_density = FastNoiseLite.new()
	noise_density.frequency = 0.01 
	
	var resolution = data.get_resolution()
	var chunk_count = ceil(float(resolution) / CHUNK_SIZE)
	
	print("🌳 Planting vegetation in " + str(chunk_count*chunk_count) + " chunks...")
	print("📏 Terrain Scale: " + str(terrain.map_scale)) 
	
	# FORCE COLLIDER UPDATE (Just in case)
	if terrain.has_method("update_collider"): terrain.update_collider()
	
	# READ CORRECT CHANNELS
	var img_index = data.get_image(6) 
	var img_weight = data.get_image(7)
	
	if not img_index:
		print("❌ Error: No Index Map (Channel 6) found! Decorator cannot run.")
		return
	
	# 🧱 PHYSICS SETUP
	print("🧱 Enabling Terrain Collision for Raycasting...")
	terrain.set_collision_enabled(true)
	await get_tree().physics_frame
	await get_tree().physics_frame 
	
	if not is_instance_valid(terrain):
		print("❌ Error: Terrain instance lost during physics wait!")
		return
		
	var world = terrain.get_world_3d()
	if not world:
		print("❌ Error: Terrain not in tree (No World3D)!")
		return
		
	var space_state = world.direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1 
	
	var count_biome_fail = 0
	var count_density_fail = 0
	var count_spawned = 0
	
	for cz in range(chunk_count):
		for cx in range(chunk_count):
			var chunk_node = Node3D.new()
			chunk_node.name = "Chunk_" + str(cx) + "_" + str(cz)
			chunk_node.position = Vector3(0,0,0)
			veg_root.add_child(chunk_node)
			chunk_node.owner = get_tree().edited_scene_root 
			
			var chunk_batch = {} 
			
			# Scan this chunk
			for z in range(cz * CHUNK_SIZE, min((cz + 1) * CHUNK_SIZE, resolution), 4): 
				for x in range(cx * CHUNK_SIZE, min((cx + 1) * CHUNK_SIZE, resolution), 4):
					var h = data.get_height_at(x, z) 
					if h < 4.5: continue
					
					var pixel_idx = img_index.get_pixel(x, z)
					var biome_id = int(pixel_idx.r * 255.0)
					
					if randf() < 0.0001: print("🔍 Biome at " + str(x) + "," + str(z) + " = " + str(biome_id))
					
					var is_grass = (biome_id == 4 or biome_id == 5)
					var is_forest = (biome_id == 6) # Forest Floor
					var is_rock = (biome_id == 0 or biome_id == 1 or biome_id == 8) # Include Lightning Rock
					
					# RELAXED RULES: ALLOW SPAWN ALMOST EVERYWHERE FOR DEBUG
					# if not is_grass and not is_forest and not is_rock: 
						# count_biome_fail += 1
						# continue
					
					# DENSITY CHECK - RELAXED
					var density = noise_density.get_noise_2d(x, z)
					if density < -0.4: # Very permissive
						count_density_fail += 1
						continue
					
					var wx = x * terrain.map_scale.x
					var wz = z * terrain.map_scale.z
					
					var ray_origin = Vector3(wx, 1000, wz)
					var ray_end = Vector3(wx, -500, wz)
					query.from = ray_origin
					query.to = ray_end
					var result = space_state.intersect_ray(query)
					
					var world_pos = Vector3()
					if result:
						world_pos = result.position
						world_pos.y -= 0.3 
					else:
						var final_h = h * terrain.map_scale.y
						world_pos = Vector3(wx, final_h - 10.0, wz)
					
					var final_basis = Basis().rotated(Vector3.UP, randf() * TAU)
					var final_scale = randf_range(0.8, 1.2)
					final_basis = final_basis.scaled(Vector3(final_scale, final_scale, final_scale))
					var world_t = Transform3D(final_basis, world_pos)
					
					# LOGIC: Trees in Forest/Grass, Rocks elsewhere
					# FORCE TREES ON LIGHTNING ROCK (ID 8) FOR USER REQUEST
					if (biome_id == 8 or is_forest or is_grass) and not assets["tree"].is_empty():
						var chance = 0.05
						if is_forest: chance = 0.3
						if biome_id == 8: chance = 0.02 # Occasional dead tree on lightning peak
						
						if randf() < chance:
							var path = assets["tree"].pick_random()
							if not path in chunk_batch: chunk_batch[path] = []
							chunk_batch[path].append(world_t)
							count_spawned += 1
					
					# Rocks
					if not assets["rock"].is_empty():
						if randf() > 0.95: # Rare rocks everywhere
							var path = assets["rock"].pick_random()
							if not path in chunk_batch: chunk_batch[path] = []
							chunk_batch[path].append(world_t)
			
			# Create MultiMeshes for this chunk (Visuals)
			for path in chunk_batch:
				var mmi = _create_multimesh(path, chunk_batch[path], chunk_node)
				if mmi:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			
			# GENERATE COLLISION (Physics)
			_generate_chunk_colliders(chunk_batch, chunk_node)
			
		# Yield every row of chunks to prevent freeze
		await get_tree().process_frame
		_update_ui("Décoration " + str(int(float(cz)/chunk_count*100)) + "%...", 80 + int(float(cz)/chunk_count * 20))
	
	print("📊 Vegetation Report:")
	print("  - Spawned: " + str(count_spawned))
	print("  - Biome Rejected: " + str(count_biome_fail))
	print("  - Density Rejected: " + str(count_density_fail))
	
	return assets
	
func _get_transform(_lx, _h, _lz) -> Transform3D:
	return Transform3D() # OBSOLETE


func _scan_assets(path):
	var assets = {"tree": [], "rock": [], "ruin": []}
	var stack = [path]
	var processed_count = 0
	
	# Add specific new paths if they exist
	stack.append("res://Assets/3D/Nature/")
	stack.append("res://Assets/3D/Dungeon/")
	
	while not stack.is_empty():
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
					var full = dir_path + file_name
					
					if lower.ends_with(".tscn") or lower.ends_with(".glb") or lower.ends_with(".gltf") or lower.ends_with(".fbx"):
						# Categorization Logic
						if "tree" in lower or "pine" in lower or "birch" in lower or "palm" in lower:
							assets["tree"].append(full)
						elif "rock" in lower or "stone" in lower or "boulder" in lower:
							assets["rock"].append(full)
						elif "ruin" in lower or "dungeon" in lower or "arch" in lower or "column" in lower or "grave" in lower:
							assets["ruin"].append(full)
							
				file_name = dir.get_next()
		
		processed_count += 1
		if processed_count % 50 == 0: 
			await get_tree().process_frame
			_update_ui("Scan des assets (" + str(processed_count) + " folders)...", 15)
			
	print("✅ Scan Results: " + str(assets["tree"].size()) + " trees, " + str(assets["rock"].size()) + " rocks, " + str(assets["ruin"].size()) + " ruins.")
	return assets

# PRE-MADE STRUCTURES (AAA Quality)
const POI_PATHS = [
	"res://Assets/3D/Build/KayKit Medieval Builder Pack 1.0/Models/objects/gltf/castle.gltf.glb",
	"res://Assets/3D/Build/KayKit Medieval Builder Pack 1.0/Models/objects/gltf/watchtower.gltf.glb", 
	"res://Assets/3D/Build/KayKit Medieval Builder Pack 1.0/Models/objects/gltf/house.gltf.glb",
	"res://Assets/3D/Build/KayKit Medieval Builder Pack 1.0/Models/objects/gltf/lumbermill.gltf.glb",
	"res://Assets/3D/Build/KayKit Medieval Builder Pack 1.0/Models/objects/gltf/market.gltf.glb", 
	"res://Assets/3D/Build/KayKit Medieval Builder Pack 1.0/Models/objects/gltf/well.gltf.glb"
]

func _add_structures(terrain, data, assets):
	print("🏰 Spawning Civilizations...")
	var resolution = data.get_resolution()
	
	# CLEANUP ALL OLD STRUCTURES
	while true:
		var old_struct = get_parent().find_child("Structures", true, false)
		if old_struct: 
			old_struct.name = "Structures_Deleted"
			old_struct.queue_free()
		else:
			break
	
	var structures_node = Node3D.new()
	structures_node.name = "Structures"
	get_parent().add_child(structures_node)
	structures_node.owner = get_tree().current_scene
	
	var count = 0
	var attempts = 0

	var max_structures = 100 # Increased density

	
	if not is_instance_valid(terrain):
		print("❌ Error: Terrain instance lost before spawning structures!")
		return
		
	# PHYSICS SETUP
	var world = terrain.get_world_3d()
	if not world:
		print("❌ Error: Terrain not in world (No World3D)!")
		return
		
	var space_state = world.direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1 # ONLY HIT TERRAIN
	
	# 1. ELEMENTAL TOWER SYSTEM (1 per Biome)
	var tower_positions = []
	print("🗼 Spawning Elemental Towers (1 per Biome)...")
	var img_index = data.get_image(6)
	if img_index:
		var w_idx = img_index.get_width()
		var scale_factor = float(w_idx) / float(resolution)
		
		# Biome Names for ID 0-9 (Corrected)
		var biome_names = ["Grass", "CliffMoss", "Beach", "Dunes", "Cliff", "WildGrass", "Forest", "Mountain", "Snow", "Mud"]

		
		for b_id in range(10): # 0 to 9
			var placed_count = 0
			var b_attempts = 0
			while placed_count < 3 and b_attempts < 500: # increased density: 3 towers per biome
				b_attempts += 1
				var tx = randi_range(100, resolution - 100)
				var ty = randi_range(100, resolution - 100)
				
				# Check Biome using Index Map
				var ix = int(tx * scale_factor)
				var iy = int(ty * scale_factor)
				var pixel = img_index.get_pixel(ix, iy)
				var current_biome = int(pixel.r * 255.0)
				
				if current_biome != b_id: continue
				
				# Valid biome found. Check placement constraints.
				var h = data.get_height_at(tx, ty)
				if h < 2.0: continue # Not underwater
				
				# World Coords
				var wx = tx * terrain.map_scale.x
				var wz = ty * terrain.map_scale.z
				
				var too_close = false

				for tpos in tower_positions:
					if Vector2(wx, wz).distance_to(tpos) < 200.0: too_close = true; break # Reduced from 600 to 200
				if too_close: continue

				
				# Place Tower
				var scene = load("res://Tools/MapTower.tscn")
				var instance = scene.instantiate()
				structures_node.add_child(instance)
				
				var tower_name = "Tower_" + biome_names[b_id] + "_" + str(placed_count)
				instance.name = tower_name
				if "tower_id" in instance: instance.tower_id = tower_name
				
				# REGISTER TO GAMEMANAGER (For Minimap)
				# Note: We need to do this defered or ensuring GameManager exists in editor context? 
				# Actually this script runs in editor. GameManager autoload might not be active/valid the same way.
				# BUT visual script execution allows accessing singletons if tool.
				# To be safe, we will just set the property and let the Tower itself register on _ready().
				# Wait, MapTower registers via MapPoint._ready -> MapManager.
				# MapManager usually tracks points. GameManager tracks TOWERS specifically for minimap drawing.
				# Let's verify MapPoint.gd registration again.
				# MapPoint registers to MapManager. MapManager has `register_point`.
				# But Minimap reads `GameManager.all_towers`.
				# So we NEED to register specifically to GameManager or have MapManager sync.
				# Let's add explicit registration here for the save file mainly.
				if GameManager:
					GameManager.register_tower(Vector3(wx, h * terrain.map_scale.y, wz), tower_name)

				
				# Align to Ground
				query.from = Vector3(wx, 1000, wz)
				query.to = Vector3(wx, -500, wz)
				var result = space_state.intersect_ray(query)
				if result: instance.global_position = result.position
				else: instance.global_position = Vector3(wx, h * terrain.map_scale.y, wz)
				
				instance.scale = Vector3(2.0, 2.0, 2.0) # BIG VISIBLE TOWERS
				_add_collision_recursive(instance)
				_flatten_terrain_at(data, tx, ty, 20, h)
				
				tower_positions.append(Vector2(wx, wz))
				print("  🗼 Built " + tower_name + " (Biome: " + str(b_id) + ") at " + str(instance.global_position))
				placed_count += 1
			
			if placed_count == 0:
				print("⚠️ WARNING: Could not place ANY tower for Biome " + str(b_id) + " (" + biome_names[b_id] + ") after " + str(b_attempts) + " attempts.")
				# Retry with relaxed constraints?


			
	# 2. RANDOM CIVILIZATION
	print("🏘️ Spawning Villages...")
	while count < max_structures and attempts < 1000:
		attempts += 1
		# Choose random spot
		var rx = randi_range(100, resolution - 100)
		var rz = randi_range(100, resolution - 100)
		
		# World Coords
		var wx = rx * terrain.map_scale.x
		var wz = rz * terrain.map_scale.z
		
		var h = data.get_height_at(rx, rz) * terrain.map_scale.y
		# Avoid Towers
		var near_tower = false
		for tpos in tower_positions:
			if Vector2(wx, wz).distance_to(tpos) < 100.0: near_tower = true; break
		if near_tower: continue
		
		# Check Constraints
		# h is already calculated above as World Height.
		# But for constraints logic, we might want raw height?
		# No, h above is world height.
		if h < 5.0: continue # No underwater castles
		if h > 300.0: continue # No sky castles (Adjusted for scale)
		
		# Check Slope (Flat ground needed)
		var h_r = data.get_height_at(min(rx+5, resolution-1), rz) * terrain.map_scale.y
		var h_d = data.get_height_at(rx, min(rz+5, resolution-1)) * terrain.map_scale.y
		var slope = max(abs(h - h_r), abs(h - h_d))
		if slope > 8.0: continue # Relaxed slope constraint
		
		var path = ""
		# 30% Chance for Ancient Ruin/Dungeon if available
		if assets.has("ruin") and not assets["ruin"].is_empty() and randf() < 0.3:
			path = assets["ruin"].pick_random()
		else:
			path = POI_PATHS.pick_random()

		if "watchtower" in path: continue # Skip towers in random pass (Already placed)
		
		var scene = load(path)
		if scene:
			var instance = scene.instantiate()
			structures_node.add_child(instance)
			
			# WORLD POSITION (Physics Raycast)
			query.from = Vector3(wx, 1000, wz)
			query.to = Vector3(wx, -500, wz)
			var result = space_state.intersect_ray(query)
			
			if result:
				instance.global_position = result.position
			else:
				instance.global_position = Vector3(wx, h * terrain.map_scale.y, wz)
			instance.rotation.y = randf() * TAU
			# Make Villages MASSIVE but Towers Normal
			instance.scale = Vector3(5, 5, 5) 
			
			# Align to ground nicely
			count += 1
			print("  ➕ Built " + instance.name + " at " + str(instance.position))
			
			# GENERATE COLLISION (Fix Falling Through)
			_add_collision_recursive(instance)
			
			# Flatten terrain under structure (Micro-Terraform)
			_flatten_terrain_at(data, rx, rz, 10, h)
			
	print("🏰 Built " + str(count) + " village structures.")

func _add_collision_recursive(root_node):
	for child in root_node.get_children():
		if child is MeshInstance3D:
			# Check if already has collision
			if child.get_child_count() == 0 or not child.get_child(0) is StaticBody3D:
				child.create_trimesh_collision()
		_add_collision_recursive(child)

func _flatten_terrain_at(_data, _cx, _cy, _radius, _height):
	# TODO: Implement local flattening for better placement
	pass

func _create_multimesh(path, transforms, parent) -> MultiMeshInstance3D:
	var scn = load(path)
	if not scn: return null
	var mesh = null
	if scn is PackedScene:
		var state = scn.get_state()
		for i in range(state.get_node_count()):
			if state.get_node_type(i) == "MeshInstance3D":
				for j in range(state.get_node_property_count(i)):
					if state.get_node_property_name(i, j) == "mesh":
						mesh = state.get_node_property_value(i, j); break
				if mesh: break
	elif scn is Mesh: mesh = scn
	if not mesh: return null

	var mmi = MultiMeshInstance3D.new()
	mmi.name = "MMI_" + path.get_file().get_basename()
	parent.add_child(mmi)
	mmi.owner = get_tree().edited_scene_root
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	mm.mesh = mesh
	for i in range(transforms.size()): mm.set_instance_transform(i, transforms[i])
	mmi.multimesh = mm
	return mmi

func _generate_chunk_colliders(batch, parent):
	if batch.is_empty(): return

	var static_body = StaticBody3D.new()
	static_body.name = "Chunk_Collision"
	parent.add_child(static_body)
	# static_body.owner = get_tree().edited_scene_root # Optional, but good for debug
	
	for path in batch:
		var transforms = batch[path]
		var shape = null
		var offset = Vector3.ZERO
		
		# Auto-Detect Shape based on Path Name
		var lower = path.to_lower()
		if "tree" in lower or "pine" in lower or "palm" in lower or "birch" in lower:
			# Cylinder (Tree Trunk)
			var cap = CylinderShape3D.new()
			cap.height = 5.0
			cap.radius = 0.5
			shape = cap
			offset = Vector3(0, 2.5, 0) # Center up
		elif "rock" in lower or "stone" in lower:
			# Box (Rock) - Rough approximation
			var box = BoxShape3D.new()
			box.size = Vector3(2.5, 2.0, 2.5) 
			shape = box
			offset = Vector3(0, 0.5, 0)
			
		if shape:
			for t in transforms:
				var col = CollisionShape3D.new()
				col.shape = shape
				col.transform = t
				# Adjust for pivot (Model pivot is usually bottom)
				# We move the shape UP along the instance's UP axis
				col.position += t.basis.y * offset.y
				static_body.add_child(col)

# --- UI HELPER ---
func _show_loading_screen():
	# CRITICAL: DO NOT show fullscreen UI in Editor Mode (Blocks interface)
	if Engine.is_editor_hint(): return
	
	if _ui_instance: return
	if loading_screen_scene: 
		_ui_instance = loading_screen_scene.instantiate()
		get_tree().root.add_child(_ui_instance)
		
		# FAILSAFE: Force remove after 45s (prevent eternal freeze)
		get_tree().create_timer(45.0).timeout.connect(func(): 
			print("⏰ WATCHDOG: Force-closing Loading Screen (Timeout).")
			_hide_loading_screen()
		)

func _hide_loading_screen():
	if _ui_instance: _ui_instance.queue_free(); _ui_instance = null

# Robust channel check to prevent the index 6 crash
func _ensure_channels(data):
	var maps = data.get("_maps")
	if maps == null: return
	
	print("🛡️ Verifying Terrain Data Channels (Size: " + str(maps.size()) + ")...")
	
	# If size is less than 8, HTerrain might crash when MultiSplat16 is used
	# Index 6: Splatmap Index
	# Index 7: Splatmap Weight
	for channel in range(maps.size(), 8):
		print("🛠️ Expanding Terrain Data to " + str(channel + 1) + " channels...")
		data.call("_edit_add_map", channel)
	
	# Ensure the existing channels (6 and 7) are not empty arrays
	maps = data.get("_maps") # Refresh reference
	for channel in [6, 7]:
		if channel < maps.size() and maps[channel].is_empty():
			print("🛠️ Initializing empty channel " + str(channel) + "...")
			data.call("_edit_add_map", channel)

func _update_ui(t, v):
	if _ui_instance and _ui_instance.has_method("update_status"): _ui_instance.update_status(t, v)

# --- DEBUG & CLEANUP TOOLS ---
func _cleanup_recursive(node):
	var count = 0
	for child in node.get_children():
		# PROTECT SELF: Do not delete the generator script node itself!
		if child == self: continue
		
		var lower = child.name.to_lower()
		# DO NOT delete "chunk_" blindly, as it breaks active HTerrain if we didn't kill it.
		# But since we kill HTerrain above, we just want to catch *other* ghosts.
		if "vegetation" in lower or "multimesh" in lower or "worldgenerator" in lower or "biomemanager" in lower:
			print("🔥 Burning Ghost Node: " + child.name)
			child.queue_free()
			count += 1
			if count % 10 == 0 and is_inside_tree(): await get_tree().process_frame # Yield safely
		else:
			_cleanup_recursive(child)

func _print_tree_recursive(node, depth=0):
	var prefix = ""
	for i in range(depth): prefix += "  "
	print(prefix + "📄 " + node.name + " (" + node.get_class() + ")")
	for child in node.get_children():
		_print_tree_recursive(child, depth + 1)
	print("✅ Grass Planted.")

# --- DECORATION PLACEMENT (Trees, Rocks, etc.) ---
func _place_decorations(terrain, data):
	print("🌲 Placing 3D Decorations (MultiMesh) - AAA Quality...")
	_update_ui("Plantation Détaillée (Arbres, Rochers, Champignons)...", 80)
	
	# 1. Clean up old decorations
	if terrain.has_node("Decorations"):
		terrain.get_node("Decorations").free() # Force free immediately to clear memory
		await get_tree().process_frame
		
	var root_decor = Node3D.new()
	root_decor.name = "Decorations"
	terrain.add_child(root_decor)
	root_decor.owner = terrain.owner # Persist in scene
	
	# 2. Rich Asset Database
	var assets = {
		# TREES
		"Pine": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/Pine_1.gltf",
		"PineSmall": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/Pine_5.gltf",
		"Tree": "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/CommonTree_1.gltf",
		"TreeVar": "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/CommonTree_3.gltf",
		"Birch": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/BirchTree_1.gltf",
		"Maple": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/MapleTree_1.gltf",
		"MapleRed": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/MapleTree_4.gltf",
		"DeadTree": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/DeadTree_1.gltf",
		"DeadTreeTwist": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/DeadTree_5.gltf",
		
		# ROCKS
		"Rock": "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/Rock_Medium_1.gltf",
		"RockSmall": "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/Rock_Medium_3.gltf",
		"Pebble": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/Pebble_Round_1.gltf",
		
		# UNDERGROWTH
		"Bush": "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/Bush_Common.gltf",
		"BushFlower": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/Bush_Flowers.gltf",
		"Flower": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/Flower_1_Clump.gltf",
		"FlowerRed": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/Flower_5_Clump.gltf",
		"Mushroom": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/Mushroom_Common.gltf",
		"MushroomRed": "res://Assets/3D/Nature/Ultimate Stylized Nature Pack/glTF/Mushroom_Laetiporus.gltf",
		"Fern": "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/Fern_1.gltf",
		"Clover": "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/Clover_1.gltf"
	}
	
	# Prepare Collections
	var collections = {}
	for k in assets.keys(): collections[k] = []
	
	var w = data.get_resolution()
	var h = data.get_resolution()
	var map_scale = terrain.map_scale
	
	var noise_chaos = FastNoiseLite.new()
	noise_chaos.seed = 1337
	noise_chaos.frequency = 0.005
	
	var noise_cluster = FastNoiseLite.new()
	noise_cluster.seed = 999
	noise_cluster.frequency = 0.02 # For clustering mushrooms/flowers
	
	var stride = 4 
	
	var img_normal = data.get_image(1) # CHANNEL_NORMAL
	
	for z in range(0, h, stride):
		if z % 100 == 0: await get_tree().process_frame
		for x in range(0, w, stride):
			if randf() > 0.45: continue # 55% empty
			
			var height = data.get_height_at(x, z)
			if height < 1.0: continue # Skip underwater strict
			
			# DECODE NORMAL (Packed RGB)
			var n_col = img_normal.get_pixel(x, z)
			var normal = Vector3(n_col.r * 2.0 - 1.0, n_col.g * 2.0 - 1.0, n_col.b * 2.0 - 1.0)
			var slope = rad_to_deg(acos(normal.dot(Vector3.UP)))
			var chaos = noise_chaos.get_noise_2d(x, z)
			var cluster = noise_cluster.get_noise_2d(x, z)
			
			var global_pos = terrain.global_position + Vector3(x * map_scale.x, height, z * map_scale.z)
			
			# DETERMINE BIOME (Synced with Painter Logic)
			var biome_id = 0
			if height < 8.0: biome_id = 2 # Beach
			elif height > 120.0: biome_id = 8 # Snow
			elif height > 90.0: biome_id = 7 # Mountain Base
			elif slope > 30.0: biome_id = 4 # Cliff
			else:
				# Reuse Painter Noise logic approximation
				if chaos > 0.2: biome_id = 6 # Forest
				elif chaos < -0.3: biome_id = 5 # Flowers
				else: biome_id = 0 # Grass
			
			if height < 3.0: biome_id = 9 # Mud/Swamp edge
			
			# --- DISTRIBUTION RULES ---
			var item = ""
			var scale_range = Vector2(0.8, 1.2)
			
			# FOREST (ID 6) - Dense, mixed
			if biome_id == 6: 
				if randf() < 0.03: item = "Maple" if randf() < 0.3 else "Tree"
				elif randf() < 0.02: item = "Birch"
				elif randf() < 0.05: item = "Bush"
				elif randf() < 0.02: item = "Fern"
				elif randf() < 0.02: item = "Mushroom" if cluster > 0.2 else ""
				scale_range = Vector2(1.2, 2.0)
				
			# MOUNTAIN BASE (ID 7) - Pines, Rocks
			elif biome_id == 7:
				if randf() < 0.05: item = "Pine"
				elif randf() < 0.05: item = "Rock"
				elif randf() < 0.02: item = "DeadTree"
				
			# SNOW (ID 8) - Sparse
			elif biome_id == 8:
				if randf() < 0.01: item = "PineSmall"
				elif randf() < 0.02: item = "Rock"
				
			# CLIFFS (ID 4)
			elif biome_id == 4:
				if randf() < 0.05: item = "RockSmall"
				elif randf() < 0.02: item = "DeadTreeTwist"
				
			# FLOWER FIELDS (ID 5) - Lush
			elif biome_id == 5:
				var density_bonus = 1.5 if cluster > 0.0 else 0.5
				if randf() < 0.15 * density_bonus: item = "Flower" if randf() < 0.7 else "FlowerRed"
				elif randf() < 0.03: item = "BushFlower"
				elif randf() < 0.02: item = "Clover"
				
			# SWAMP/MUD (ID 9)
			elif biome_id == 9:
				if randf() < 0.05: item = "DeadTree"
				elif randf() < 0.05: item = "MushroomRed"
				elif randf() < 0.05: item = "Fern"
				
			# BEACH (ID 2)
			elif biome_id == 2:
				if randf() < 0.01: item = "Pebble"
				
			# GRASS PLAINS (ID 0)
			else:
				if randf() < 0.005: item = "TreeVar" # Very sparse trees
				elif randf() < 0.02: item = "Bush"
				elif randf() < 0.01: item = "RockSmall"
				
			# ADD TO COLLECTION
			if item != "":
				var t = Transform3D()
				t.origin = global_pos
				t = t.rotated(Vector3.UP, randf() * TAU)
				var s = randf_range(scale_range.x, scale_range.y)
				t = t.scaled(Vector3.ONE * s)
				collections[item].append(t)
				
	# 3. BUILD MULTIMESHES
	for name in collections:
		var positions = collections[name]
		if positions.is_empty(): continue
		
		var path = assets[name]
		
		# Robust Check
		if not FileAccess.file_exists(path):
			print("❌ Asset NOT FOUND: " + path)
			continue
			
		var scene = load(path)
		if not scene:
			print("⚠️ Failed to load Resource: " + path)
			continue
			
		var mesh_res = null
		var mat_res = null
		
		# Helper to extract mesh
		var extract_mesh = func(n):
			if n is MeshInstance3D: return n
			for c in n.get_children():
				if c is MeshInstance3D: return c
			return null
			
		var instance = scene.instantiate()
		var mesh_node = extract_mesh.call(instance)
		if mesh_node:
			mesh_res = mesh_node.mesh
			mat_res = mesh_node.get_surface_override_material(0)
			# Fallback to mesh surface material
			if not mat_res: mat_res = mesh_res.surface_get_material(0)
		instance.free()
		
		if not mesh_res: continue
			
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh_res
		mm.instance_count = positions.size()
		
		for i in range(positions.size()):
			mm.set_instance_transform(i, positions[i])
			
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "MM_" + name
		if mat_res: mmi.material_override = mat_res 
		
		root_decor.add_child(mmi)
		mmi.owner = terrain.owner
		
	print("✅ Complete Decoration Set Placed.")
