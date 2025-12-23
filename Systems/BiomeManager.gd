extends Node
## BiomeManager.gd (Autoload)
## Central system for biome logic and environmental atmosphere

enum BiomeType { FOREST, JUNGLE, ICE, DESERT, LAVA, FIRE, WATER, LIGHTNING, CRYSTAL, GOLD_CITY }

@export_group("Noise Settings")
var biome_noise: FastNoiseLite
var humidity_noise: FastNoiseLite

# Biome Visual Config
const ASSET_PATH = "res://Assets/3D/Nature/Stylized Nature MegaKit[Standard]/glTF/"

const BIOME_DATA = {
	BiomeType.FOREST: { 
		"color": Color(0.2, 0.5, 0.1), 
		"fog": Color(0.3, 0.4, 0.3), 
		"assets": ["CommonTree_1.gltf", "CommonTree_2.gltf", "Bush_Common.gltf", "Grass_Common_Tall.gltf"] 
	},
	BiomeType.JUNGLE: { 
		"color": Color(0.05, 0.3, 0.05), 
		"fog": Color(0.1, 0.2, 0.1), 
		"assets": ["Fern_1.gltf", "Plant_1_Big.gltf", "Plant_1.gltf", "Mushroom_Laetiporus.gltf"] 
	},
	BiomeType.ICE: { 
		"color": Color(0.8, 0.9, 1.0), 
		"fog": Color(0.7, 0.8, 1.0), 
		"assets": ["DeadTree_1.gltf", "Pebble_Round_1.gltf", "Rock_Medium_2.gltf"] 
	},
	BiomeType.DESERT: { 
		"color": Color(0.9, 0.7, 0.4), 
		"fog": Color(0.8, 0.6, 0.4), 
		"assets": ["Rock_Medium_1.gltf", "Pebble_Round_4.gltf", "DeadTree_5.gltf"] 
	},
	BiomeType.LAVA: { 
		"color": Color(0.2, 0.1, 0.1), 
		"fog": Color(0.4, 0.1, 0.0), 
		"assets": ["DeadTree_2.gltf", "Rock_Medium_3.gltf", "Pebble_Square_1.gltf"] 
	},
	BiomeType.FIRE: { 
		"color": Color(0.3, 0.1, 0.0), 
		"fog": Color(0.5, 0.2, 0.0), 
		"assets": ["TwistedTree_1.gltf", "DeadTree_3.gltf", "Rock_Medium_1.gltf"] 
	},
	BiomeType.WATER: { 
		"color": Color(0.1, 0.3, 0.6), 
		"fog": Color(0.1, 0.2, 0.4), 
		"assets": ["Plant_7_Big.gltf", "Pebble_Round_2.gltf", "RockPath_Round_Wide.gltf"] 
	},
	BiomeType.LIGHTNING: { 
		"color": Color(0.2, 0.1, 0.4), 
		"fog": Color(0.3, 0.2, 0.5), 
		"assets": ["TwistedTree_4.gltf", "Rock_Medium_2.gltf", "TwistedTree_5.gltf"] 
	},
	BiomeType.CRYSTAL: { 
		"color": Color(0.4, 0.1, 0.6), 
		"fog": Color(0.5, 0.2, 0.7), 
		"assets": ["Rock_Medium_1.gltf", "Rock_Medium_2.gltf", "Mushroom_Common.gltf"] 
	},
	BiomeType.GOLD_CITY: { 
		"color": Color(0.8, 0.6, 0.1), 
		"fog": Color(0.6, 0.5, 0.2), 
		"assets": ["RockPath_Square_Wide.gltf", "RockPath_Square_Thin.gltf", "Pebble_Square_5.gltf"] 
	}
}

var current_player_biome: BiomeType = BiomeType.FOREST

func _ready() -> void:
	biome_noise = FastNoiseLite.new()
	biome_noise.seed = 12345
	biome_noise.frequency = 0.0005 # Large biome distribution

	humidity_noise = FastNoiseLite.new()
	humidity_noise.seed = 54321
	humidity_noise.frequency = 0.0004
	
func get_biome_at(pos: Vector3) -> BiomeType:
	var b_val = biome_noise.get_noise_2d(pos.x, pos.z) # -1 to 1
	var h_val = humidity_noise.get_noise_2d(pos.x, pos.z) # -1 to 1
	
	# Mapping Noise to Biomes (Simplified Grid)
	if b_val < -0.6: return BiomeType.ICE
	if b_val < -0.3:
		return BiomeType.WATER if h_val > 0 else BiomeType.DESERT
	if b_val < 0.1:
		return BiomeType.FOREST if h_val > -0.2 else BiomeType.JUNGLE
	if b_val < 0.4:
		return BiomeType.LIGHTNING if h_val > 0.3 else BiomeType.CRYSTAL
	if b_val < 0.7:
		return BiomeType.FIRE if h_val > 0 else BiomeType.LAVA
	
	return BiomeType.GOLD_CITY

func _process(_delta: float) -> void:
	var player = get_tree().get_first_node_in_group("Player")
	if not player: return
	
	var new_biome = get_biome_at(player.global_position)
	if new_biome != current_player_biome:
		current_player_biome = new_biome
		_update_atmosphere(new_biome)

func _update_atmosphere(type: BiomeType) -> void:
	var env = get_viewport().get_camera_3d().get_world_3d().fallback_environment
	if not env:
		var we = get_tree().get_first_node_in_group("WorldEnvironment")
		if we: env = we.environment
	
	if env:
		var target_fog = BIOME_DATA[type].fog
		# Smooth transition via tween
		var tween = create_tween()
		tween.tween_property(env, "fog_light_color", target_fog, 2.0)
		# Update Sky color if using ProceduralSkyMaterial is too complex, we stick to fog/ambient
		tween.parallel().tween_property(env, "ambient_light_color", target_fog.lerp(Color.WHITE, 0.5), 2.0)
		print("🌍 Transition vers le biome : ", BiomeType.keys()[type])
