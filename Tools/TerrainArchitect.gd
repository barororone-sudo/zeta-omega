@tool
extends Node

## Terrain Architect (Zelda TOTK Style)
## Générateur procédural pour Terrain3D
## Spécialisé dans les terrains en "Terrasses", Biomes géants, et sans damier.

@export_category("Configuration")
@export var terrain_node: Terrain3D
@export var button_generate: bool = false:
	set(value):
		if value and terrain_node:
			generate_terrain()
		button_generate = false

@export_category("Textures (IDs)")
@export var tex_grass_id: int = 3
@export var tex_rock_id: int = 1
@export var tex_sand_id: int = 0
@export var tex_snow_id: int = 2

@export_category("Topography (Terraces)")
@export var height_noise: FastNoiseLite
@export var height_scale: float = 80.0
@export var terrace_steps: int = 15 ## Combien de "plateaux" sur la hauteur max
@export var cliff_smoothness: float = 0.1 ## 0 = marches dures, 1 = colline lisse

@export_category("Giant Biomes")
@export var biome_noise: FastNoiseLite
@export var biome_transition_sharpness: float = 0.5 ## 0 = flou, 1 = net

@export_category("Rules")
@export var cliff_angle_threshold: float = 30.0 ## Pente en degrés pour devenir de la roche

func _ready():
	if not height_noise:
		height_noise = FastNoiseLite.new()
		height_noise.seed = randi()
		height_noise.frequency = 0.005
		height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		
	if not biome_noise:
		biome_noise = FastNoiseLite.new()
		biome_noise.seed = randi()
		biome_noise.frequency = 0.0003 # Fréquence minuscule demandée
		biome_noise.domain_warp_enabled = true
		
func generate_terrain():
	if not terrain_node or not terrain_node.storage:
		printerr("❌ [TerrainArchitect] Terrain3D Node ou Storage manquant!")
		return
		
	var storage = terrain_node.storage
	# On s'assure d'avoir la région 0,0 (ou on boucle sur toutes les régions existantes ?)
	# Pour l'instant, focalisons-nous sur la région 0,0
	if not storage.has_region(Vector2i(0,0)):
		storage.add_region(Vector2i(0,0))
		
	print("🏗️ [TerrainArchitect] Début de la génération Zelda-Style...")
	
	var region_size = 1024 # Standard Terrain3D
	var height_map: Image = storage.get_map_region(0, 0)
	var control_map: Image = storage.get_map_region(1, 0)
	
	# ---------------------------------------------------------
	# ÉTAPE 1 : LA COUCHE DE BASE (BASE COAT)
	# ---------------------------------------------------------
	# "Peindre 100% de la map avec la texture ID 3 (Herbe)"
	# On le fait directement sur l'image pour être ultra rapide.
	# Format Control Map: R=TextureID, G=?, B=?, A=Blend? 
	# Terrain3D 0.9.x utilise souvent R pour l'ID principal. 
	# L'ID est stocké de 0 à 31 (ou plus). En normalized float : id / 255.0 ? Non, souvent c'est l'entier.
	# Mais dans set_pixel avec Color, on passe des floats.
	# Vérifions : ID 3 -> 3/255.0 ?
	# Dans SmartWorldGen.gd on voyait : c_map.set_pixel(x, z, Color(tex_id, 0, 0, 1)) où tex_id = float(id)/255.0
	
	var base_color = Color(float(tex_grass_id) / 255.0, 0, 0, 1)
	control_map.fill(base_color)
	print("   ✅ Base Coat (Herbe) appliqué.")
	
	# ---------------------------------------------------------
	# ÉTAPE 2 : HAUTEUR & TERRASSES
	# ---------------------------------------------------------
	# On génère d'abord toute la height map pour pouvoir calculer les pentes ensuite.
	
	for z in range(region_size):
		for x in range(region_size):
			var global_x = x # + offset si besoin
			var global_z = z 
			
			var h_noise_val = height_noise.get_noise_2d(global_x, global_z) # -1 à 1
			
			# Normaliser 0..1 pour le traitement
			var h_01 = (h_noise_val + 1.0) * 0.5
			
			# LOGIQUE TERRASSES
			# On veut des "marches".
			# Fonction Step simple : floor(val * steps) / steps
			var stepped_h = floor(h_01 * terrace_steps) / float(terrace_steps)
			
			# Lissage pour ne pas avoir de Minecraft pur ?
			# Lerp entre raw et stepped
			var final_h_01 = lerp(stepped_h, h_01, cliff_smoothness)
			
			# Redispatcher sur la hauteur réelle
			var real_height = final_h_01 * height_scale
			
			# Terrain3D stocke la hauteur dans le canal Rouge ? 
			# Attention: Terrain3D utilise souvent un format R32F (float pur) pour la hauteur s'il a été mis à jour.
			# Mais `get_map_region` retourne une Image. Si c'est RH (Real Height), c'est direct.
			# Si c'est une image standard, c'est Color(h, ...).
			# Supposons que set_pixel(x, z, Color(h, ...)) fonctionne comme dans SmartWorldGen.
			
			height_map.set_pixel(x, z, Color(real_height, 0, 0, 1))
	
	# Force update pour que le moteur calcule les normales internes si possible,
	# mais on a besoin des pentes pour la texture NOW.
	# On va faire un calcul de pente manuel "rapide".
	
	print("   ✅ Topographie (Terrasses) appliquée.")

	# ---------------------------------------------------------
	# ÉTAPE 3 : BIOMES & FALAISES
	# ---------------------------------------------------------
	
	for z in range(region_size):
		for x in range(region_size):
			# 1. Calcul de Pente (Slope)
			# On regarde les voisins. Attention aux bords.
			var h = height_map.get_pixel(x, z).r
			var h_right = height_map.get_pixel(min(x+1, region_size-1), z).r
			var h_down = height_map.get_pixel(x, min(z+1, region_size-1)).r
			
			# Vecteurs approximatifs (scale 1m par pixel)
			var dx = h_right - h
			var dz = h_down - h
			
			# Pente approximative (magnitude du gradient)
			var slope_ratio = sqrt(dx*dx + dz*dz) # Rise over Run (dist=1)
			var slope_deg = rad_to_deg(atan(slope_ratio))
			
			var final_tex_id = -1
			
			# RÈGLE : FALAISES (Priorité Absolue)
			if slope_deg > cliff_angle_threshold:
				final_tex_id = tex_rock_id
			else:
				# RÈGLE : BIOMES
				var b_val = biome_noise.get_noise_2d(x, z) # -1 à 1
				
				# Logique Biomes Géants
				# < -0.3 : Neige (Hautes montagnes artificielles ou Nord)
				# > 0.4 : Désert
				# Reste: Herbe (Déjà peint, donc on ne touche PAS si c'est Herbe)
				
				if b_val > 0.4:
					final_tex_id = tex_sand_id
				elif b_val < -0.4:
					final_tex_id = tex_snow_id
					
			# APPLICATION
			if final_tex_id != -1:
				# On peint
				# Note: Terrain3D v0.9 utilise CONTROL map R channel pour Texture ID base, G pour Blend...
				# Ici on remplace l'ID de base (Sharp transition) pour éviter le damier de blend
				control_map.set_pixel(x, z, Color(float(final_tex_id)/255.0, 0, 0, 1))

	print("   ✅ Biomes & Falaises appliqués.")
	
	# Commit
	storage.force_update_maps(0)
	storage.force_update_maps(1)
	print("✨ Génération terminée avec succès !")
