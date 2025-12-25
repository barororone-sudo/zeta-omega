@tool
extends Node

# CONFIGURATION
@export var plant_grass: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_plant_grass()

@export var grass_texture_index: int = 0 # The texture ID representing Grass in Splatmap
@export var noise_threshold: float = 0.2
@export var density_multiplier: float = 1.0

func _plant_grass():
	print("🌿 GRASS PAINTER: Starting Analysis...")
	
	# FIND HTERRAIN
	var terrain = _find_hterrain(get_tree().edited_scene_root)
	if not terrain:
		printerr("❌ HTerrain node not found in scene.")
		return
		
	var data = terrain.get_data()
	if not data:
		printerr("❌ HTerrain Data is missing.")
		return
		
	# 1. SETUP NOISE (Clustering)
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.05
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM # Simplex removed in 4.x
	
	# 2. GET MAPS
	# We need the Splatmap (Index Map usually channel 6, or Weight Map channel 2/3 depending on shader).
	# Standard HTerrain (Splat16) uses an INDEX map (Channel 6) + WEIGHT map (Channel 7).
	# Or simple Splat4 uses Channel 2 (Color/Splat).
	
	# Assuming MultiSplat16 (Index Map):
	var use_index_map = true
	var img_splat = data.get_image(6) # Channel 6 = INDEX
	
	if not img_splat:
		# Fallback to Splat4 (Color)
		use_index_map = false
		img_splat = data.get_image(2) # Channel 2 = TYPE_COLOR (Splat)
		
	if not img_splat:
		printerr("❌ Could not find Splatmap or Index Map.")
		return
		
	var w = img_splat.get_width()
	var h = img_splat.get_height()
	
	# 3. GET/CREATE DETAIL MAP
	# Usually Detail Map 0 is mapped to Channel 10? Or just "Detail 0".
	# Use Zylann API constant if possible, or guess.
	# HTerrainData.CHANNEL_DETAIL = 9?
	# Let's use the helper if available, or just map type.
	# Channel 10 is usually the first detail map.
	var detail_channel = 10 
	
	var img_detail = data.get_image(detail_channel)
	if not img_detail:
		print("✨ Creating Detail Map 0...")
		data._edit_add_map(detail_channel)
		img_detail = data.get_image(detail_channel)
	
	if not img_detail:
		printerr("❌ Failed to access Detail Map.")
		return
		
	var wd = img_detail.get_width()
	var hd = img_detail.get_height()
	
	# Scale factor if resolutions differ
	var scale_x = float(w) / float(wd)
	var scale_y = float(h) / float(hd)
	
	print("🌿 Planting on " + str(wd) + "x" + str(hd) + " grid (Optimization: Clustering)...")
	
	# 4. ITERATE AND PAINT
	var planted_count = 0
	
	for y in range(hd):
		for x in range(wd):
			# Sample Splatmap
			var sx = int(x * scale_x)
			var sy = int(y * scale_y)
			
			var is_grass = false
			
			if use_index_map:
				# Index map stores ID in Red channel (0..1 scaled 0..255)
				var pixel = img_splat.get_pixel(sx, sy)
				var id = int(pixel.r * 255.0 + 0.5)
				if id == grass_texture_index: is_grass = true
				# Also check similar grass textures? (e.g. 1=Dark Grass)
				if id == 4 or id == 5: is_grass = true # Expanded IDs for Forest/Wild
			else:
				# Splat4 stores weights in RGBA
				var pixel = img_splat.get_pixel(sx, sy)
				if (grass_texture_index == 0 and pixel.r > 0.5) or \
				   (grass_texture_index == 1 and pixel.g > 0.5) or \
				   (grass_texture_index == 2 and pixel.b > 0.5):
					is_grass = true

			if is_grass:
				# NOISE CLUSTERING
				var n_val = noise.get_noise_2d(x, y)
				if n_val > noise_threshold:
					# Plant!
					img_detail.set_pixel(x, y, Color(1, 0, 0, 1)) # R=Density
					planted_count += 1
				else:
					# Clear (Clearings)
					img_detail.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				# Not grass terrain -> Remove grass
				img_detail.set_pixel(x, y, Color(0, 0, 0, 0))
				
	# 5. COMMIT
	data.notify_region_change(Rect2(0, 0, wd, hd), detail_channel)
	print("✅ Done! Planted " + str(planted_count) + " grass blades.")

func _find_hterrain(node):
	if node.has_method("get_data"): return node
	for c in node.get_children():
		var res = _find_hterrain(c)
		if res: return res
	return null
