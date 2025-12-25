@tool
extends Node

## World Environment Setup (Anime/Zelda Style)
## "One-Click Beautifier" pour transformer la scène.

@export var button_apply_visuals: bool = false:
	set(value):
		if value:
			if not is_inside_tree():
				printerr("❌ [WorldSetup] Le nœud doit être dans l'arbre de scène pour fonctionner.")
				button_apply_visuals = false
				return
			setup_environment()
			setup_light()
		button_apply_visuals = false

func setup_environment():
	print("🎨 [WorldSetup] Configuration du WorldEnvironment...")
	
	var env_node = _get_or_create_node("WorldEnvironment", WorldEnvironment)
	
	# Création de la ressource Environment si besoin
	var env = env_node.environment
	if not env:
		env = Environment.new()
		env_node.environment = env
		
	# 1. SKY (Ciel Azure/Anime)
	env.background_mode = Environment.BG_SKY
	
	var sky = env.sky
	if not sky:
		sky = Sky.new()
		env.sky = sky
		
	var sky_mat = sky.sky_material
	if not sky_mat or not (sky_mat is ProceduralSkyMaterial):
		sky_mat = ProceduralSkyMaterial.new()
		sky.sky_material = sky_mat
		
	# Couleurs Style Zelda/Ghibli
	sky_mat.sky_top_color = Color("0077ff") # Bleu Azur Profond
	sky_mat.sky_horizon_color = Color("aaccff") # Bleu très clair / Blanc
	sky_mat.ground_bottom_color = Color("404050") # Sol légèrement bleuté (Ambient boost)
	sky_mat.ground_horizon_color = Color("aaccff")
	
	# Soleil dans le ciel
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.05
	
	# 2. FOG (Volumetric)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012 # Légèrement plus dense
	env.volumetric_fog_albedo = Color("ddeeff") 
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_detail_spread = 2.0 
	
	# Désactiver le brouillard standard pour éviter le conflit ou le double emploi
	env.fog_enabled = false 
	
	# 3. POST-PROCESS
	
	# Tonemap (Vital pour les couleurs)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1 # Plus lumineux
	
	# SSAO (Ombres de contact)
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 5.0 # Pop des détails
	env.ssao_power = 1.5
	
	# Glow (Bloom)
	env.glow_enabled = true
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.glow_intensity = 0.5
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	
	# SDFGI (Optionnel, gourmand) - On laisse désactivé par défaut pour perf
	# env.sdfgi_enabled = true
	
	print("   ✅ Environment configuré (Sky, Fog, SSAO, Glow).")
	
	# Hack: Force update editor
	env_node.notify_property_list_changed()


func setup_light():
	print("☀️ [WorldSetup] Configuration de la DirectionalLight...")
	
	var sun = _get_or_create_node("DirectionalLight3D", DirectionalLight3D)
	
	# Position/Rotation
	sun.rotation_degrees = Vector3(-45, 30, 0)
	
	# Ombres
	sun.shadow_enabled = true
	# Paramètres d'ombres pour éviter le "peter panning" ou artefacts
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 200.0 # Assez pour voir loin, mais garder la résolution
	
	# Couleur
	sun.light_color = Color("fff8e0") # Blanc légèrement chaud
	sun.light_energy = 1.6 # Un peu plus fort pour l'effet "éclatant"
	
	print("   ✅ Soleil configuré.")

func _get_or_create_node(node_name: String, type):
	var root = get_tree().edited_scene_root
	if not root:
		root = get_parent() # Fallback si pas en mode editeur
		
	if not root:
		printerr("❌ Impossible de trouver la racine de la scène.")
		return null

	var node = root.find_child(node_name, true, false) # Recursive=true pour trouver n'importe où ? Non, restons simple.
	# Si on est dans WorldenvironmentSetup enfant de root, on cherche dans root.
	
	if not node:
		node = type.new()
		node.name = node_name
		root.add_child(node)
		node.owner = root
		print("   + Créé node : ", node_name)
	else:
		print("   . Trouvé node : ", node_name)
		
	return node
