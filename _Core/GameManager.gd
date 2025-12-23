extends Node
## GameManager - Singleton principal du jeu
## Gère l'état global du RPG Open World
## Accessible via: GameManager (autoload)

var unlocked_regions: Array = []
var all_towers: Array = [] # {position: Vector3, id: String, activated: bool}

func _ready() -> void:
	# TODO: Charger depuis sauvegarde disque
	pass

func register_tower(pos: Vector3, id: String):
	for t in all_towers:
		if t.id == id: return # Déjà connue
	all_towers.append({"position": pos, "id": id, "activated": false})
	print("📡 Tour enregistrée : ", id)

func is_region_unlocked(pos: Vector2) -> bool:
	for reg in unlocked_regions:
		if pos.distance_to(reg.position) < reg.radius:
			return true
	return false

func unlock_region(pos: Vector2, radius: float) -> void:
	unlocked_regions.append({"position": pos, "radius": radius})
	
	# Update status in all_towers
	for t in all_towers:
		var t_pos_2d = Vector2(t.position.x, t.position.z)
		if t_pos_2d.distance_to(pos) < 10.0: # C'est cette tour
			t.activated = true
			
	print("🔓 Nouvelle région débloquée : ", pos, " r=", radius)
	# Notification globale pour la Minimap
	get_tree().call_group("Minimap", "refresh_fog")
