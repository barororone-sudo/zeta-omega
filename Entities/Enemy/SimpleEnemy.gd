extends CharacterBody3D

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var timer: Timer = $Timer

var speed = 3.0
var health = 50.0
var target: Node3D = null

func _ready():
	timer.timeout.connect(_on_timer_timeout)
	# Find player (assuming group "Player" exists as per project norms)
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		target = players[0]

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= 20.0 * delta # Gravity
	
	if nav_agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	else:
		var next_path_pos = nav_agent.get_next_path_position()
		var dir = global_position.direction_to(next_path_pos)
		dir.y = 0
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		
		# Rotate towards direction
		if dir.length() > 0.1:
			var look_target = global_position + dir
			look_at(look_target, Vector3.UP)
	
	move_and_slide()
	
	# Attack Logic
	if target and global_position.distance_to(target.global_position) < 1.5:
		print("Pif Paf")

func _on_timer_timeout():
	if is_instance_valid(target):
		nav_agent.target_position = target.global_position

func take_damage(amount):
	health -= amount
	if health <= 0:
		queue_free()
