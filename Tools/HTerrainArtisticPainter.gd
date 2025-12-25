@tool
extends Node

# HTerrain Artistic Painter
# "Making it look like Genshin Impact, mathematically."

const CHANNEL_WEIGHTS = 7
const CHANNEL_INDEX = 6

# Texture IDs corresponding to the descriptions
const ID_CLIFF = 4 # Swapped with Grass
const ID_CLIFF_MOSS = 1
const ID_BEACH = 2
const ID_DUNES = 3
const ID_GRASS_MAIN = 0 # Swapped with Cliff (Default = 0)
const ID_GRASS_WILD = 5

const ID_FOREST_FLOOR = 6
const ID_MOUNTAIN_BASE = 7
const ID_SNOW = 8
const ID_MUD = 9

func paint_terrain(terrain, data, tex_paths: Array):
	print("🎨 Starting Artistic Painting (MultiSplat16)...")
	
	# 1. SETUP TEXTURE ARRAYS (Crucial for >4 textures)
	_setup_texture_arrays(terrain, tex_paths)
	
	# 2. PREPARE NOISE
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.002 # 🌍 BETTER VARIETY (More local biomes)


	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	
	var noise_chaos = FastNoiseLite.new()
	noise_chaos.seed = randi() + 1
	noise_chaos.frequency = 0.005 # Chaos/Temperature
	
	# 3. GET IMAGES
	var res = data.get_resolution()
	var img_height = data.get_image(0)
	var img_normal = data.get_image(1) 
	
	# We need to construct the SPLAT Maps (Channel 2)
	# MultiSplat16 uses standard RGBA maps.
	var splat_maps = []
	for i in range(3): # Texture 0-11
		# Verify existence
		while data.get_map_count(2) <= i: # CHANNEL_SPLAT = 2
			data._edit_add_map(2)
			
		var img = data.get_image(2, i)
		img.fill(Color(0,0,0,0)) # Wipe
		splat_maps.append(img)

	print("🖌️ Painting Splatmaps (Channel 2) on " + str(res*res) + " pixels...")
	
	for z in range(res):
		if z % 5 == 0 and is_inside_tree(): await get_tree().process_frame
		for x in range(res):
			var h = img_height.get_pixel(x, z).r
			var normal = HT_Util_decode_normal(img_normal.get_pixel(x, z))
			var slope = rad_to_deg(acos(normal.dot(Vector3.UP)))
			
			# ELEMENTAL MAP
			# Chaos: -1 (Order/Cold) to 1 (Chaos/Fire)
			var chaos = noise_chaos.get_noise_2d(x, z) 
			var distinct = noise.get_noise_2d(x, z)
			
			# --- AAA BIOME RULES (Genshin/Zelda Style) ---
			
			# IDs Mapping:
			# 0: Grass (Main)
			# 1: Cliff Moss (Sem-Steep)
			# 2: Beach (Sand)
			# 3: Dunes (Desert - Unused here, specific zone?)
			# 4: Cliff (Steep Rock)
			# 5: Flowers (Wild Grass)
			# 6: Gravel (Forest)
			# 7: Mountain Base (Gravel)
			# 8: Snow (Peaks)
			# 9: Paving/Mud (Underwater)

	# 1. BASE LAYER (Grass)
			var chosen_id = 0 
			
			# 2. ALTITUDE RULES
			if h < 2.0: # Underwater / Swamp
				chosen_id = 9 # Paving/Mud
			elif h < 8.0: # Beach
				if slope < 20.0:
					chosen_id = 2 # Sand
				else:
					chosen_id = 1 # Mossy Rock (Coastal cliffs)
					
			elif h > 120.0: # Mountain Peaks
				if slope < 40.0:
					chosen_id = 8 # Snow
				else:
					chosen_id = 4 # Cliff Rock (Too steep for snow)
					
			elif h > 90.0: # Mountain Transition (Sub-Alpine)
				if slope > 30.0:
					chosen_id = 4 # Rock
				else:
					# Mix of Grass and Gravel/Snow
					if chaos > 0.2: chosen_id = 7 # Gravel
					else: chosen_id = 0 # Grass
			
			# 3. SLOPE RULES (Overrides Altitude)
			elif slope > 45.0:
				chosen_id = 4 # Hard Rock Cliff
			elif slope > 30.0:
				if h < 20.0: chosen_id = 1 # Mossy Rock (Low)
				else: chosen_id = 4 # Rock (High)
				
			# 4. FLAT LAND VARIATION (Noise Based)
			else:
				# Plains / Forests
				if distinct > 0.5:
					chosen_id = 6 # Forest Floor / Gravel patch
				elif distinct < -0.4:
					chosen_id = 5 # Flowers / Wild Grass patch
				elif chaos > 0.7:
					chosen_id = 3 # Dunes/Dried patch
					
			# Debug Print (Throttle)
			if x == 0 and z % 100 == 0:
				pass # print("  🎨 Painting Row " + str(z))

			
			# APPLY
			# APPLY TO SPLATMAPS
			var map_idx = chosen_id / 4
			var channel_idx = chosen_id % 4
			
			if map_idx < splat_maps.size():
				var img = splat_maps[map_idx]
				var c = img.get_pixel(x, z)
				
				# Set specific channel to 1.0
				if channel_idx == 0: c.r = 1.0
				elif channel_idx == 1: c.g = 1.0
				elif channel_idx == 2: c.b = 1.0
				elif channel_idx == 3: c.a = 1.0
				
				img.set_pixel(x, z, c)

			
	# NOTIFY UPDATE
	for i in range(splat_maps.size()):
		data.notify_region_change(Rect2(0, 0, res, res), 2, i) # CHANNEL_SPLAT = 2

	print("✅ Painting Complete.")

func _setup_texture_arrays(terrain, file_paths: Array):
	print("🎞️ Building Texture Arrays from " + str(file_paths.size()) + " images...")
	
	if file_paths.size() == 0: return

	# Setup Texture Set mode
	var tex_set = terrain.get_texture_set()
	if tex_set.get_mode() != 1: # MODE_TEXTURE_ARRAYS
		tex_set.set_mode(1)
	
	# Create Albedo Array
	var albedo_arr = Texture2DArray.new()
	var arr_images = []
	
	var width = 512
	var height = 512
	
	for i in range(file_paths.size()):
		var path = file_paths[i]
		var img = Image.new()
		
		# ROBUST LOAD FROM FILE (Bypasses Resource Cache)
		print("📂 Loading Texture ", i, ": ", path)
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
		else:
			print("❌ File not found: ", path)
			img = null
		
		# Removed Debug Yellow/Magenta logic for cleaner production code
		if not img:
			print("⚠️ Creating placeholder for missing texture: ", path)
			img = Image.create(width, height, false, Image.FORMAT_RGBA8)
			img.fill(Color.GREEN) # Fallback to Green
			
		# Checks if compressed and decompresses if true
		if img.is_compressed():
			img.decompress()
			
		# Resize safely and convert
		if img.get_width() != width or img.get_height() != height:
			img.resize(width, height)
			
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
			
		arr_images.append(img)

			
	albedo_arr.create_from_images(arr_images)
	
	# Save Albedo Array
	var albedo_path = "res://Assets/Generated/TerrainAlbedoArray_FIX5.tres"
	DirAccess.make_dir_recursive_absolute("res://Assets/Generated/")
	ResourceSaver.save(albedo_arr, albedo_path)
	albedo_arr = load(albedo_path) # Reload to ensure resource integrity
	
	# Assign to slot 0 (Correct Albedo)
	tex_set.set_texture_array(0, albedo_arr)
	
	# Create Normal Array (Generic) - RESTORED
	var normal_arr = Texture2DArray.new()
	var norm_images = []
	var flat_norm = Image.create(width, height, false, Image.FORMAT_RGBA8)
	flat_norm.fill(Color(0.5, 0.5, 1.0)) # Standard Normal Blue
	
	for i in range(arr_images.size()): 
		norm_images.append(flat_norm)
	
	normal_arr.create_from_images(norm_images)
	
	# Save Normal Array
	var normal_path = "res://Assets/Generated/TerrainNormalArray_FIX5.tres"
	ResourceSaver.save(normal_arr, normal_path)
	normal_arr = load(normal_path)
	
	# Assign to slot 1 (Correct Normal)
	tex_set.set_texture_array(1, normal_arr) 
	
	print("✅ Texture Arrays Saved & Assigned. (Albedo: " + str(arr_images.size()) + " layers)")
	
	# FORCE REFRESH: Toggle shader type (best way to force update)
	print("🌍 Forcing Global Map Refresh via Shader Toggle...")
	if terrain.is_inside_tree():
		terrain.set_shader_type("Classic4Lite") # Toggle away
		
		# Safe wait
		var tree = terrain.get_tree()
		if tree:
			await tree.create_timer(0.1).timeout
			
		if terrain and terrain.is_inside_tree():
			terrain.set_shader_type("MultiSplat16") # Toggle back
	
	print("✅ Texture Arrays assigned.")

# Helper to decode normal from RGB
func HT_Util_decode_normal(c: Color) -> Vector3:
	var n = Vector3(c.r, c.g, c.b)
	return (n * 2.0 - Vector3.ONE).normalized()
