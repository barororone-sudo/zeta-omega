extends CharacterBody3D
class_name Player

## Player Controller - ZETA OMEGA
## Gère Mouvement, Attaque, Saut et Chargement Dynamique d'Animations

# === EXPORT VARIABLES ===
@export_group("Movement")
@export var move_speed: float = 5.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 20.0
@export var jump_force: float = 8.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.003

# === NODES ===
@onready var camera_pivot: Node3D = $CameraPivot
@onready var visuals: Node3D = $Visuals
# Ces références seront trouvées dynamiquement
var animation_player: AnimationPlayer = null
var skeleton: Skeleton3D = null

# === INTERNAL STATE ===
var is_attacking: bool = false
var _head_bone_idx: int = -1
var _neck_bone_idx: int = -1

# === ANIMATION PATHS ===
const ANIM_PATHS = {
	"Idle": "res://Assets/Animations/Sword_And_Shield_Idle.fbx",
	"Run": "res://Assets/Animations/Sword_And_Shield_Run.fbx",
	"Walk": "res://Assets/Animations/Sword_And_Shield_Walk.fbx",
	"Jump": "res://Assets/Animations/Jumping.fbx",
	"Attack": "res://Assets/Animations/Sword_And_Shield_Slash.fbx"
}

func _ready() -> void:
	# 1. SETUP MOUSE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# 2. SETUP INPUTS (AUTO-CONFIG)
	_setup_inputs_automatically()
	
	# 3. FIND NODES
	_find_animation_nodes()
	
	# 4. LOAD ANIMATIONS & SETUP BONES
	if skeleton:
		_setup_bones()
	
	if animation_player:
		_load_animations_from_files()
		_setup_animation_signals()

func _setup_inputs_automatically() -> void:
	# Ajoute l'action "attack" si elle n'existe pas
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		InputMap.action_add_event("attack", ev)
		print("✅ Input 'attack' créé automatiquement (Clic Gauche)")

func _setup_bones() -> void:
	# Trouve les os pour le fix Mixamo
	_head_bone_idx = skeleton.find_bone("mixamorig_Head")
	_neck_bone_idx = skeleton.find_bone("mixamorig_Neck")
	if _head_bone_idx == -1: _head_bone_idx = skeleton.find_bone("Head")
	if _neck_bone_idx == -1: _neck_bone_idx = skeleton.find_bone("Neck")

func _setup_animation_signals() -> void:
	# Connecte le signal de fin d'animation
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	
	# Config Attack Loop Mode = NONE
	if animation_player.has_animation("Attack"):
		var attack_anim = animation_player.get_animation("Attack")
		attack_anim.loop_mode = Animation.LOOP_NONE
		print("✅ Mode boucle 'Attack' forcé à NONE")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# 1. GRAVITY
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1 # Petite force vers le bas pour garder le contact au sol
	
	# 2. JUMP
	if is_on_floor() and Input.is_action_just_pressed("ui_accept") and not is_attacking:
		print("🚀 SAUT DÉCLENCHÉ PAR TOUCHE !")
		velocity.y = jump_force
		# Lance l'animation TOUT DE SUITE pour 0 délai
		if animation_player and animation_player.has_animation("Jump"):
			animation_player.play("Jump", 0.05) # Transition quasi-instantanée
	if is_on_floor() and Input.is_action_just_pressed("attack") and not is_attacking:
		_start_attack()
	
	# 4. MOVEMENT
	if is_attacking:
		# Stop movement during attack
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)
	else:
		# Standard Movement
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var direction := Vector3.ZERO
		
		# Fallback to UI inputs if custom ones failing (just in case)
		if input_dir == Vector2.ZERO:
			input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
			
		if input_dir != Vector2.ZERO:
			var cam_basis = camera_pivot.global_basis
			var forward = -cam_basis.z
			var right = cam_basis.x
			forward.y = 0; right.y = 0
			forward = forward.normalized(); right = right.normalized()
			
			direction = (forward * -input_dir.y + right * input_dir.x).normalized()
		
		if direction.length() > 0.01:
			velocity.x = lerp(velocity.x, direction.x * move_speed, acceleration * delta)
			velocity.z = lerp(velocity.z, direction.z * move_speed, acceleration * delta)
			var target_rot = atan2(direction.x, direction.z)
			visuals.rotation.y = lerp_angle(visuals.rotation.y, target_rot, rotation_speed * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
			velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
	
	move_and_slide()
	
	# 5. ANIM UPDATE
	_update_animations()



# === COMBO VARIABLES ===
var combo_step: int = 0 # 0=None, 1=Hit1, 2=Hit2, 3=Hit3
var next_attack_queued: bool = false
const COMBO_TIMINGS = [1.2, 2.4, 3.6] # Fin théorique de chaque coup

func _start_attack() -> void:
	if not animation_player or not animation_player.has_animation("Attack"): return
	
	if not is_attacking:
		# Premier coup
		print("⚔️ COMBO 1 START")
		is_attacking = true
		combo_step = 1
		velocity = Vector3.ZERO
		animation_player.play("Attack", 0.1)
		animation_player.seek(0.0, true) # Force début
	else:
		# On essaie d'enchaîner
		if combo_step < 3:
			print("⚔️ COMBO QUEUED (Next step: ", combo_step + 1, ")")
			next_attack_queued = true

var _debug_timer: float = 0.0
func _process(delta: float) -> void:
	# 1. GESTION COMBO
	if is_attacking and animation_player.current_animation == "Attack":
		var t = animation_player.current_animation_position
		
		# Fin du Coup 1 -> Vers Coup 2 ?
		if combo_step == 1 and t >= 1.2:
			if next_attack_queued:
				print("⚔️ COMBO 2 EXECUTE")
				combo_step = 2
				next_attack_queued = false
			else:
				print("⚔️ COMBO 1 END")
				_stop_attack()
				
		# Fin du Coup 2 -> Vers Coup 3 ?
		elif combo_step == 2 and t >= 2.4:
			if next_attack_queued:
				print("⚔️ COMBO 3 EXECUTE")
				combo_step = 3
				next_attack_queued = false
			else:
				print("⚔️ COMBO 2 END")
				_stop_attack()
				
	# 2. DEBUG Logger
	_debug_timer += delta
	if _debug_timer > 1.0:
		_debug_timer = 0.0
		var current_anim = "None"
		if animation_player: current_anim = animation_player.current_animation
		# print("🔍 DEBUG: OnFloor=", is_on_floor(), " VelY=", snapped(velocity.y, 0.01), " Anim=", current_anim)

	# 3. FIX MIXAMO HEAD
	if skeleton:
		if _head_bone_idx != -1: skeleton.set_bone_pose_rotation(_head_bone_idx, Quaternion.IDENTITY)
		if _neck_bone_idx != -1: skeleton.set_bone_pose_rotation(_neck_bone_idx, Quaternion.IDENTITY)

func _stop_attack() -> void:
	is_attacking = false
	combo_step = 0
	next_attack_queued = false
	animation_player.stop() # Arrêt immédiat pour passer à Idle/Run

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "Attack":
		_stop_attack()

func _update_animations() -> void:
	if not animation_player: return
	
	# PRIORITY 1: ATTACK
	if is_attacking:
		if animation_player.current_animation != "Attack":
			animation_player.play("Attack")
		return
		
	# PRIORITY 2: JUMP / FALL
	if not is_on_floor():
		if animation_player.has_animation("Jump"):
			if animation_player.current_animation != "Jump":
				animation_player.play("Jump", 0.3)
		return
	
	# PRIORITY 3: RUN / WALK / IDLE
	var h_speed = Vector2(velocity.x, velocity.z).length()
	var target_anim = "Idle"
	
	if h_speed > 3.0: target_anim = "Run"
	elif h_speed > 0.1: target_anim = "Walk"
	
	if animation_player.has_animation(target_anim):
		if animation_player.current_animation != target_anim:
			animation_player.play(target_anim, 0.2)

# === ANIMATION LOADER (PRESERVED) ===
func _load_animations_from_files() -> void:
	for anim_name in ANIM_PATHS:
		_load_single_animation(anim_name, ANIM_PATHS[anim_name])

func _load_single_animation(target_name: String, path: String) -> void:
	var packed = load(path)
	if not packed: return
	var instance = packed.instantiate()
	var ext_player = _find_node_recursive(instance, "AnimationPlayer")
	if ext_player:
		var list = ext_player.get_animation_list()
		if list.size() > 0:
			var anim_resource = ext_player.get_animation(list[0])
			var source_anim_name = list[0] # Get the actual animation name from the FBX
			
			# FORCE LOOP MODES
			if target_name in ["Idle", "Run", "Walk"]: 
				anim_resource.loop_mode = Animation.LOOP_LINEAR
			else:
				anim_resource.loop_mode = Animation.LOOP_NONE
			
			if not animation_player.has_animation(target_name):
				animation_player.get_animation_library("").add_animation(target_name, anim_resource)
				print("✅ Animation ajoutée : " + target_name + " (source: " + source_anim_name + ") | Durée: " + str(anim_resource.length))
	instance.queue_free()

func _find_animation_nodes() -> void:
	animation_player = _find_node_recursive(visuals, "AnimationPlayer")
	skeleton = _find_node_recursive(visuals, "Skeleton3D")

func _find_node_recursive(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name: return root
	for c in root.get_children():
		var f = _find_node_recursive(c, type_name)
		if f: return f
	return null
