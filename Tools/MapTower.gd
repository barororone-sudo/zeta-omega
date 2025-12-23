extends Node3D

@export var tower_id: String = "tower_1"
@export var reveal_radius: float = 500.0

var is_activated = false
@onready var anim = $AnimationPlayer
@onready var mesh = $MeshInstance3D

func _ready() -> void:
	# Enregistrer la tour pour la map
	GameManager.register_tower(global_position, tower_id)

func _on_interact_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player") and not is_activated:
		_activate_tower()

func _activate_tower():
	if is_activated: return
	is_activated = true
	print("🗼 Tour activée : ", tower_id)
	
	# 1. Unlock dans GameManager
	# On convertit la pos 3D (X, Z) en pos 2D carte
	var pos_2d = Vector2(global_position.x, global_position.z)
	GameManager.unlock_region(pos_2d, reveal_radius)
	
	# 2. Feedback Visuel
	if anim: anim.play("Activate")
	
	# 3. Changement couleur
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0.5, 1.0) # Bleu Sheikah
	mat.emission_enabled = true
	mat.emission = Color(0, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
