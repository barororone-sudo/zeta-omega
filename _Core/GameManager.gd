extends Node
## GameManager - Singleton principal du jeu
## Gère l'état global du RPG Open World
## Accessible via: GameManager (autoload)

# SAFE INITIALIZATION
var unlocked_regions: Array = []
var all_towers: Array = [] 
var unlocked_points: Array = [] 
var terrain_node: Node = null
var terrain_data = null

const SAVE_PATH = "user://savegame.json"

func _ready() -> void:
	print("✅ GameManager Ready.")
	load_game()

func is_point_unlocked(id: String) -> bool:
	return id in unlocked_points

func unlock_point(id: String):
	if not id in unlocked_points:
		unlocked_points.append(id)
		save_game()

func is_zone_revealed(pos: Vector3) -> bool:
	for region in unlocked_regions:
		# region.position is Vector3(x, z, radius) stored in save, or Vector2?
		# Original save likely stored Dict or Object. Let's assume Dict from load_game.
		# Check load_game logic to be safe, but usually we iterate dicts.
		# Wait, unlocked_regions is populated by MapTower. 
		# MapTower code: GameManager.unlocked_regions.append({"position": Vector2(x,z), "radius": ...})
		var r_pos = region.position
		if typeof(r_pos) == TYPE_VECTOR3: r_pos = Vector2(r_pos.x, r_pos.y) # Handle potential mismatch
		
		if Vector2(pos.x, pos.z).distance_to(r_pos) < region.radius:
			return true
	return false

func save_game():
	var data = {
		"unlocked_regions": unlocked_regions,
		"towers": all_towers,
		"unlocked_points": unlocked_points
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		print("💾 Game Saved.")
	else:
		printerr("❌ Failed to save game.")

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		print("⚠️ No save file found. Starting fresh.")
		return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	
	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	if error == OK:
		var data = json.data
		if "unlocked_regions" in data: unlocked_regions = data["unlocked_regions"]
		if "towers" in data: 
			# Restore tower states?
			# Actually towers are nodes, we might need to sync them if they exist
			all_towers = data["towers"]
		if "unlocked_points" in data: unlocked_points = data["unlocked_points"]
		print("📂 Game Loaded.")
	else:
		printerr("❌ Corrupted save file.")

func register_tower(pos: Vector3, id: String):
	for t in all_towers:
		if t.id == id: return # Déjà connue
	
	# Check if this ID was activated in saved data (handled by load, but if registering late...)
	var is_active = false
	# (Logic simplified: load_game restores state after registration or before?)
	# Load happens in ready. Registration happens when tower spawns.
	# We need to re-apply load data to this new tower instance if strictly needed.
	# Actually, usually we rely on the Tower checking GameManager.
	
	all_towers.append({"position": pos, "id": id, "activated": is_active})
	print("📡 Tour enregistrée : ", id)

func is_region_unlocked(pos: Vector2) -> bool:
	for reg in unlocked_regions:
		if pos.distance_to(reg.position) < reg.radius:
			return true
	return false

func unlock_region(pos: Vector2, radius: float) -> void:
	# Avoid duplicates close by
	for reg in unlocked_regions:
		if reg.position.distance_to(pos) < 50.0: return
		
	unlocked_regions.append({"position": pos, "radius": radius})
	
	# Update status in all_towers
	for t in all_towers:
		var t_pos_2d = Vector2(t.position.x, t.position.z)
		if t_pos_2d.distance_to(pos) < 100.0: # Tolerance increased
			t.activated = true
			
	print("🔓 Nouvelle région débloquée : ", pos, " r=", radius)
	get_tree().call_group("Minimap", "refresh_fog")
	save_game() # Auto-save on unlock

func _process(_delta):
	# Update Global Shader Parameter for Interactive Grass
	var player = get_tree().get_first_node_in_group("Player")
	if is_instance_valid(player):
		RenderingServer.global_shader_parameter_set("player_position", player.global_position)
