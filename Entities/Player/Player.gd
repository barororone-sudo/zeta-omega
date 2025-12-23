extends CharacterBody3D
class_name Player

## Player Controller - ZETA OMEGA (Final Version + Exploration Update)
## Features: Jump Snappy, Combo 3-Hit, Mixamo Fix, STAMINA, CLIMBING, GLIDING

# === EXPORT VARIABLES ===
@export_group("Movement")
@export var move_speed: float = 5.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 20.0
@export var jump_force: float = 8.0
@export var visual_offset: Vector3 = Vector3(0, -0.15, 0) # Fix Floating (Lower visuals)

@export_group("Exploration")
@export var max_stamina: float = 100.0
@export var stamina_regen_rate: float = 20.0
@export var climb_speed: float = 3.0
@export var climb_stamina_cost: float = 10.0 # Per second
@export var climb_jump_cost: float = 25.0 # Flat cost
@export var glide_speed: float = 8.0
@export var glide_fall_speed: float = 1.5
@export var glide_stamina_cost: float = 5.0 # Per second

@export_group("Camera")
@export var mouse_sensitivity: float = 0.003

@export_group("Animations")
@export var anim_climb_idle: String = "Climbing Idle"
@export var anim_climb_up: String = "Climbing Up"
@export var anim_climb_down: String = "Climbing Down"
@export var anim_climb_left: String = "Climbing Left" # BONUS
@export var anim_climb_right: String = "Climbing Right" # BONUS
@export var anim_glide: String = "Glider Hang" # ou "Falling Idle"

# === NODES ===
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var visuals: Node3D = $Visuals
@onready var skeleton: Skeleton3D # Sera récupéré dynamiquement
var animation_player: AnimationPlayer = null # Needed for runtime reference

# DYNAMIC NODES (Created in code)
var wall_cast: RayCast3D
var stamina_bar: TextureProgressBar
var glider_mesh: Node3D

# --- ANIMATION SETTINGS ---
var anim_dir = "res://Assets/Animations/Pro Sword and Shield Pack/"
var anim_library: AnimationLibrary
var _head_bone_idx: int = -1
var _neck_bone_idx: int = -1

# --- WEAPON SETTINGS ---
# Utilisation de l'alternative (potentiellement plus courte ou différente)
var weapon_scene = preload("res://Assets/3D/Items/Ultimate RPG Items Bundle-glb/Sword-9lLmH8Et4K.glb")
var current_weapon_node: Node3D = null

# === INTERNAL STATE ===
enum State { NORMAL, CLIMB, GLIDE }
var current_state: State = State.NORMAL

var is_attacking: bool = false
var jump_delay_timer: float = 0.0
var current_stamina: float = 100.0

# === COMBO SYSTEM VARIABLES (Zelda BOTW/TOTK Style) ===
var combo_count: int = 0          # 0 = Pas de combo, 1-6 = Coup actuel
var input_buffered: bool = false  # Si le joueur a cliqué pendant l'attaque
var combo_cooldown: float = 0.0   # Cooldown après la fin du combo
const COMBO_MAX_HITS = 6          # Nombre max de coups dans un combo
const COMBO_COOLDOWN_TIME = 0.3   # Temps avant de pouvoir recommencer un combo
const MIN_CHAIN_TIME = 0.35         # Temps minimum avant de pouvoir enchaîner

# === RPG STATS ===
var level: int = 1
var current_xp: int = 0
var xp_to_next_level: int = 100
var max_hp: float = 100.0
var current_hp: float = 100.0
var attack_damage: float = 10.0

# === ROOT MOTION VARIABLES ===
var last_hips_pos: Vector3 = Vector3.ZERO
var root_motion_accum: Vector3 = Vector3.ZERO
var _hips_bone_idx: int = -1

func _ready() -> void:
	add_to_group("Player")
	_initialize_player()
	
	# SETUP EXPLORATION
	_setup_wall_detector()
	_setup_stamina_ui()
	_setup_glider_visuals()
	
	_setup_stamina_ui()
	_setup_glider_visuals()
	
	current_stamina = max_stamina
	current_hp = max_hp
	_update_rpg_ui()
	
	# Snap to Terrain on Start
	call_deferred("_snap_to_terrain")

func _initialize_player() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# _setup_inputs_automatically() # Moved to _enter_tree
	_find_animation_nodes()
	
	# Apply Visual Offset
	visuals.position = visual_offset
	if skeleton: _setup_bones()
	if animation_player: 
		_load_animations_from_files()
		# Pas besoin de signal animation_finished pour le combo time-sliced, mais utile pour cleanup
		if not animation_player.animation_finished.is_connected(_on_animation_finished):
			animation_player.animation_finished.connect(_on_animation_finished)

func _setup_wall_detector():
	wall_cast = RayCast3D.new()
	wall_cast.name = "WallDetector"
	# Position: Hauteur du torse (local Y ~ 1.0)
	wall_cast.position = Vector3(0, 1.0, 0)
	# Direction: Vers l'avant (Z local négatif) sur 3.0m (Très indulgent pour debugging)
	wall_cast.target_position = Vector3(0, 0, -3.0)
	wall_cast.collision_mask = 1 # Terrain/World
	wall_cast.enabled = true
	add_child(wall_cast)
	
	# DEBUG VISUAL RAYCAST
	var mesh = ImmediateMesh.new()
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.name = "DebugRayLine"
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)
	
	# Material
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.RED
	mat.vertex_color_use_as_albedo = true
	mesh_inst.material_override = mat

func _setup_stamina_ui():
	# UI CanvasLayer
	var canvas = CanvasLayer.new()
	canvas.name = "StaminaUI"
	add_child(canvas)
	
	# Progress Bar (Circular if possible, simplified here)
	stamina_bar = TextureProgressBar.new()
	stamina_bar.name = "StaminaRing"
	# Setup simple green bar for now
	stamina_bar.set_anchors_preset(Control.PRESET_CENTER)
	stamina_bar.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	stamina_bar.value = 100
	
	# On crée une texture circulaire dynamique
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	# Cercle Vert
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x,y).distance_to(Vector2(size/2.0, size/2.0))
			if dist < size/2.0 - 2 and dist > size/2.0 - 8:
				img.set_pixel(x, y, Color(0, 1, 0, 0.8))
	var tex = ImageTexture.create_from_image(img)
	stamina_bar.texture_progress = tex
	# Fond gris
	var img_bg = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x,y).distance_to(Vector2(size/2.0, size/2.0))
			if dist < size/2.0 - 2 and dist > size/2.0 - 8:
				img_bg.set_pixel(x, y, Color(0.2, 0.2, 0.2, 0.5))
	var tex_bg = ImageTexture.create_from_image(img_bg)
	stamina_bar.texture_under = tex_bg
	
	canvas.add_child(stamina_bar)
	stamina_bar.visible = false # caché par défaut

func _setup_glider_visuals():
	glider_mesh = Node3D.new() # Container
	glider_mesh.name = "GliderContainer"
	var glider_scene = load("res://Assets/3D/Items/glider.glb")
	if glider_scene:
		var g = glider_scene.instantiate()
		g.name = "GliderModel"
		glider_mesh.add_child(g)
		# Ajustements Transform
		g.scale = Vector3(0.15, 0.15, 0.15) # Scale Down (Drastic)
		# Correct Flip: 0 (Forward). User said "it was straight" at 0.
		g.rotation_degrees = Vector3(0, 0, 0) 
		g.position = Vector3(0, 1.5, -0.5)
		print("🪁 Glider Model loaded!")
	else:
		# Fallback
		var plane = PlaneMesh.new()
		plane.size = Vector2(2, 1)
		var m = MeshInstance3D.new()
		m.mesh = plane
		glider_mesh.add_child(m)
		
	glider_mesh.visible = false
	visuals.add_child(glider_mesh)

func _snap_to_terrain() -> void:
	var h = 0.0 # Default flat ground
	if global_position.y < h:
		global_position.y = h + 1.0
		velocity.y = 0
		print("🚀 Snapped Player to Surface (Simple): Y=", global_position.y)

func _physics_process(delta: float) -> void:
	# STATE MACHINE
	match current_state:
		State.NORMAL:
			_state_normal(delta)
		State.CLIMB:
			_state_climb(delta)
		State.GLIDE:
			_state_glide(delta)
	
	# STAMINA REGEN (Si on ne grimpe pas et ne plane pas)
	if current_state == State.NORMAL:
		if current_stamina < max_stamina:
			current_stamina += stamina_regen_rate * delta
			if current_stamina > max_stamina: current_stamina = max_stamina
		# Hide UI si plein
		if current_stamina >= max_stamina:
			stamina_bar.visible = false
	else:
		stamina_bar.visible = true
		stamina_bar.max_value = max_stamina
		stamina_bar.value = current_stamina
		# Positionner au dessus de la tête (Projetée)
		var cam = get_viewport().get_camera_3d()
		if cam:
			var screen_pos = cam.unproject_position(global_position + Vector3(0, 2.2, 0))
			stamina_bar.position = screen_pos - Vector2(32, 32)
	
	move_and_slide()

# === STATE: NORMAL ===
func _state_normal(delta: float) -> void:
	# 1. GRAVITY
	if not is_on_floor():
		velocity.y -= gravity * delta
		
		# CHECK CLIMB (AIR) - Auto-Grab if touching wall in air
		if wall_cast.is_colliding():
			_enter_climb_state()
			return
			
		# CHECK GLIDE
		if Input.is_action_just_pressed("ui_accept") and not is_attacking:
			_enter_glide_state()
			return
			
	else:
		if jump_delay_timer <= 0: velocity.y = -0.1 
		
		# CHECK CLIMB (GROUND) - Grab if pushing against wall
		if wall_cast.is_colliding() and Input.is_action_pressed("move_forward"):
			_enter_climb_state()
			return

	# 2. INSTANT JUMP
	if jump_delay_timer > 0:
		jump_delay_timer -= delta
		if jump_delay_timer <= 0:
			velocity.y = jump_force

	if is_on_floor() and Input.is_action_just_pressed("ui_accept") and not is_attacking and jump_delay_timer <= 0:
		if animation_player and animation_player.has_animation("Jump"):
			animation_player.play("Jump", 0.05) 
			animation_player.seek(0.0, true)
		jump_delay_timer = 0.35

	# 3. ATTACK INPUT
	if combo_cooldown > 0: combo_cooldown -= delta
	if Input.is_action_just_pressed("attack"):
		if not is_attacking:
			if combo_cooldown <= 0 and is_on_floor(): _perform_attack(1)
		else:
			input_buffered = true

	# 4. MOVEMENT
	if is_attacking:
		_handle_attack_movement(delta)
	else:
		_handle_standard_movement(delta)
		_update_movement_animations()

# === STATE: CLIMB ===
func _state_climb(delta: float) -> void:
	if not wall_cast.is_colliding() or current_stamina <= 0:
		_exit_climb_state()
		return
		
	# Consume Stamina
	current_stamina -= climb_stamina_cost * delta
	
	# Normal & Orientation
	var normal = wall_cast.get_collision_normal()
	var look_dir = -normal
	look_dir.y = 0
	if look_dir.length() > 0.01:
		visuals.look_at(global_position + look_dir, Vector3.UP)
		rotation.y = lerp_angle(rotation.y, atan2(look_dir.x, look_dir.z), 10.0 * delta)
	
	# Input
	var input_dir = Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	# AZERTY FIX
	if input_dir == Vector2.ZERO:
		if Input.is_physical_key_pressed(KEY_Z): input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_physical_key_pressed(KEY_Q): input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
	
	velocity = Vector3.ZERO
	# FIX: Forward (-1 on stick) should mean UP (+1 in 3D Y) -> So negate Y
	# Mais get_vector("backward", "forward") -> Forward is +1 ? No usually Left/Right, Up/Down.
	# Let's trust "move_forward" is -1. So -(-1) = +1 (Up).
	velocity.y = -input_dir.y * climb_speed 
	
	# Right/Left movement
	var right = normal.cross(Vector3.UP).normalized()
	velocity += right * input_dir.x * climb_speed
	
	# Animations Safe Play
	if animation_player:
		var raw_anim = anim_climb_idle
		
		# CORRECT ANIMATION MAPPING FOR CLIMB
		if -input_dir.y > 0.1: raw_anim = anim_climb_up # Check against velocity Y direction
		elif -input_dir.y < -0.1: raw_anim = anim_climb_down
		elif input_dir.x > 0.1: 
			if animation_player.has_animation(anim_climb_right): raw_anim = anim_climb_right
			else: raw_anim = anim_climb_right # Fallback Right
		elif input_dir.x < -0.1:
			if animation_player.has_animation(anim_climb_left): raw_anim = anim_climb_left
			else: raw_anim = anim_climb_left # Fallback Left
		
		# CHECK EXISTENCE
		if animation_player.has_animation(raw_anim):
			animation_player.play(raw_anim, 0.2)
		else:
			if animation_player.has_animation("Idle"): animation_player.play("Idle", 0.2)
			
	# Jump off
	if Input.is_action_just_pressed("ui_accept"):
		current_stamina -= climb_jump_cost
		velocity = (normal + Vector3.UP).normalized() * jump_force
		_exit_climb_state()

func _enter_climb_state():
	current_state = State.CLIMB
	velocity = Vector3.ZERO # Stop falling
	print("🧗 Climb Start")

func _exit_climb_state():
	current_state = State.NORMAL
	print("🧗 Climb End")

# === STATE: GLIDE ===
func _state_glide(delta: float) -> void:
	if is_on_floor() or current_stamina <= 0:
		_exit_glide_state()
		return
		
	# Consume Stamina
	current_stamina -= glide_stamina_cost * delta
	
	# Input
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward") # Note: Forward = Up
	# AZERTY FIX
	if input_dir == Vector2.ZERO:
		if Input.is_physical_key_pressed(KEY_Z): input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_physical_key_pressed(KEY_Q): input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
	
	# Rotation Control
	if input_dir.x != 0:
		rotate_y(-input_dir.x * rotation_speed * 0.5 * delta)
		
	# Constant Forward Speed + Slow Fall
	var forward = -global_transform.basis.z
	velocity.x = forward.x * glide_speed
	velocity.z = forward.z * glide_speed
	velocity.y = -glide_fall_speed
	
	# Cancel Glide
	if Input.is_action_just_pressed("ui_accept"): # Toggle off
		_exit_glide_state()

func _enter_glide_state():
	current_state = State.GLIDE
	if glider_mesh: glider_mesh.visible = true
	if animation_player and animation_player.has_animation(anim_glide):
		animation_player.play(anim_glide, 0.2)
	print("🪁 Glide Start")

func _exit_glide_state():
	current_state = State.NORMAL
	if glider_mesh: glider_mesh.visible = false
	print("🪁 Glide End")

# === MOVEMENT HELPERS ===
func _handle_standard_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir == Vector2.ZERO: input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# SUPPORT AZERTY HARDCODED
	if input_dir == Vector2.ZERO:
		if Input.is_physical_key_pressed(KEY_Z): input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_physical_key_pressed(KEY_Q): input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
		
	var direction := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		var cam_basis = camera_pivot.global_basis
		var forward = -cam_basis.z; var right = cam_basis.x
		forward.y = 0; right.y = 0
		forward = forward.normalized(); right = right.normalized()
		
		# INVERTED FIX: Forward input (-1) should produce Forward vector.
		# Originally: forward * -y. if y=-1 -> forward * 1 -> Forward
		# User says "Moves Backward". So we must FLIP this.
		# New: forward * y. if y=-1 -> forward * -1 -> Backward relative to Cam -> Closer to User?
		# Wait, if user says Z moves Backward...
		# Let's try INVERTING logic. 
		# We use +input_dir.y for forward component.
		# FIX: Forward input is -1. So we use -input_dir.y to go Forward.
		direction = (forward * -input_dir.y + right * input_dir.x).normalized()
	
	if direction.length() > 0.01:
		velocity.x = lerp(velocity.x, direction.x * move_speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * move_speed, acceleration * delta)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, atan2(direction.x, direction.z), rotation_speed * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)

func _handle_attack_movement(delta: float) -> void:
	# FORCE FORWARD MOVEMENT (Camera Relative)
	var current_speed = 0.0
	if combo_count == 1: current_speed = 3.0 
	elif combo_count == 2: current_speed = 3.0
	elif combo_count == 3: current_speed = 5.0
	elif combo_count == 4: current_speed = 2.0 

	var cam_forward = -camera_pivot.global_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()
	
	var t = 0.0
	if animation_player: t = animation_player.current_animation_position
	
	var impulse_window = 0.15
	if combo_count == 6: impulse_window = 0.1
	
	if t < impulse_window:
		var target_vel = cam_forward * current_speed
		velocity.x = lerp(velocity.x, target_vel.x, 20.0 * delta)
		velocity.z = lerp(velocity.z, target_vel.z, 20.0 * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, 15.0 * delta)
		velocity.z = lerp(velocity.z, 0.0, 15.0 * delta)
	
	if not is_zero_approx(cam_forward.length_squared()):
		var target_angle = atan2(cam_forward.x, cam_forward.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 20.0 * delta)
	
	root_motion_accum = Vector3.ZERO

# === ANIMATION UPDATE ===
func _update_movement_animations() -> void:
	# Ignore if climbing or gliding
	if current_state != State.NORMAL: return 
	if not animation_player: return
	
	if not is_on_floor():
		if animation_player.current_animation != "Jump" and velocity.y > 0: 
			if animation_player.has_animation("Jump") and animation_player.current_animation != "Jump":
				animation_player.play("Jump", 0.2)
		return

	var h_speed = Vector2(velocity.x, velocity.z).length()
	var target = "Idle"
	if h_speed > 3.0: target = "Run"
	elif h_speed > 0.1: target = "Walk"
	
	if animation_player.has_animation(target):
		if animation_player.current_animation != target:
			animation_player.play(target, 0.2)

# ... (Existing setup helpers) ...

# === SETUP HELPERS (RESTORED) ===
func _setup_bones() -> void:
	_head_bone_idx = skeleton.find_bone("mixamorig_Head")
	_neck_bone_idx = skeleton.find_bone("mixamorig_Neck")
	_hips_bone_idx = skeleton.find_bone("mixamorig_Hips")
	if _head_bone_idx == -1: _head_bone_idx = skeleton.find_bone("Head")
	if _neck_bone_idx == -1: _neck_bone_idx = skeleton.find_bone("Neck")
	
	# === EQUIP WEAPON ===
	_equip_weapon_bone()

func _equip_weapon_bone() -> void:
	# Trouver la main droite
	var bone_name = "mixamorig_RightHand"
	var b_idx = skeleton.find_bone(bone_name)
	if b_idx == -1:
		bone_name = "RightHand" # Fallback
		b_idx = skeleton.find_bone(bone_name)
	
	if b_idx != -1:
		# Créer l'attachement
		var attachment = BoneAttachment3D.new()
		attachment.bone_name = bone_name
		skeleton.add_child(attachment)
		
		# Instancier l'épée
		if weapon_scene:
			var sword = weapon_scene.instantiate()
			attachment.add_child(sword)
			current_weapon_node = sword
			
			# === AJUSTEMENT POSTURE ===
			sword.scale = Vector3(0.6, 0.6, 0.6)
			sword.position = Vector3(0, -0.15, 0.0) 
			sword.rotation_degrees = Vector3(0, 90, 0)
			
			print("⚔️ Arme équipée sur : ", bone_name)
	else:
		print("❌ Impossible de trouver la main droite pour l'arme.")

func _load_animations_from_files() -> void:
	# RECURSIVE SEARCH
	var base_path = "res://Assets/Animations/"
	print("📂 Scanning for animations in: " + base_path)
	_scan_animations_recursive(base_path)

func _scan_animations_recursive(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_scan_animations_recursive(path + file_name + "/")
			else:
				if file_name.ends_with(".fbx") or file_name.ends_with(".glb"): # Check extension
					_process_animation_file(path + file_name, file_name)
			file_name = dir.get_next()

func _process_animation_file(full_path: String, file_name: String) -> void:
	if full_path.ends_with(".import"): return

	var target_name = ""
	var lower_name = file_name.to_lower()
	
	# MAPPING LOGIC (Existing + Updates)
	if "sword and shield idle.fbx" in lower_name and not "block" in lower_name: target_name = "Idle"
	elif "sword and shield run.fbx" in lower_name and not "(2)" in lower_name: target_name = "Run"
	elif "sword and shield walk.fbx" in lower_name and not "(2)" in lower_name: target_name = "Walk"
	elif "sword and shield jump.fbx" in lower_name and not "(2)" in lower_name: target_name = "Jump"
	
	# CLIMBING & GLIDING
	elif "hanging idle" in lower_name: target_name = "Climbing Idle"
	elif "climbing up wall" in lower_name: target_name = "Climbing Up"
	elif "climbing down wall" in lower_name: target_name = "Climbing Down"
	elif "braced hang shimmy" in lower_name: target_name = "Climbing Left" 
	
	elif "glider" in lower_name: target_name = "Glider Hang"
	
	# COMBO ATTACKS 
	elif "sword and shield slash.fbx" in lower_name: target_name = "Attack1"
	elif "sword and shield slash (2).fbx" in lower_name: target_name = "Attack2"
	elif "sword and shield slash (3).fbx" in lower_name: target_name = "Attack3"
	elif "sword and shield slash (4).fbx" in lower_name: target_name = "Attack4"
	elif "sword and shield slash (5).fbx" in lower_name: target_name = "Attack5"
	elif "sword and shield kick.fbx" in lower_name: target_name = "Attack6"
	
	if target_name == "": return
	
	var packed = load(full_path)
	if not packed: return
	
	var instance = packed.instantiate()
	var ext_player = _find_node_recursive(instance, "AnimationPlayer")
	if ext_player:
		var list = ext_player.get_animation_list()
		if list.size() > 0:
			var anim_resource = ext_player.get_animation(list[0])
			if not anim_resource: 
				instance.queue_free()
				return
			
			anim_resource.loop_mode = Animation.LOOP_LINEAR if target_name in ["Idle", "Run", "Walk", "Climbing Idle", "Climbing Up", "Climbing Down", "Glider Hang"] else Animation.LOOP_NONE
			
			# STRIP POSITIONS
			var tracks_to_remove = []
			for i in range(anim_resource.get_track_count()):
				var track_path = str(anim_resource.track_get_path(i))
				var track_type = anim_resource.track_get_type(i)
				
				if track_type == Animation.TYPE_POSITION_3D:
					tracks_to_remove.append(i)
				elif "position" in track_path.to_lower():
					tracks_to_remove.append(i)
			
			tracks_to_remove.reverse()
			for idx in tracks_to_remove:
				anim_resource.remove_track(idx)
			
			if not animation_player.has_animation(target_name):
				animation_player.get_animation_library("").add_animation(target_name, anim_resource)
				print("✅ Loaded Animation: " + target_name + " from " + file_name)
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-60), deg_to_rad(60))
		camera_pivot.rotation.x = 0
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _perform_attack(step: int) -> void:
	if not animation_player: return
	
	combo_count = step
	is_attacking = true
	input_buffered = false 
	root_motion_accum = Vector3.ZERO
	if skeleton and _hips_bone_idx != -1:
		var current_y = skeleton.get_bone_pose_position(_hips_bone_idx).y
		skeleton.set_bone_pose_position(_hips_bone_idx, Vector3(0, current_y, 0))
		last_hips_pos = Vector3(0, current_y, 0)

	var anim_name = "Attack" + str(step)
	
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name, 0.2)
		animation_player.seek(0.0, true)
	else:
		if animation_player.has_animation("Attack1"):
			animation_player.play("Attack1", 0.1)
			animation_player.seek(0.0, true)
		else:
			_end_combo("Missing Anim")

func _end_combo(_reason: String) -> void:
	is_attacking = false
	combo_count = 0
	input_buffered = false
	root_motion_accum = Vector3.ZERO
	combo_cooldown = COMBO_COOLDOWN_TIME
	if animation_player:
		animation_player.play("Idle", 0.2)

func _on_animation_finished(anim_name: String) -> void:
	if "Attack" in anim_name:
		if input_buffered:
			var next_step = combo_count + 1
			if next_step <= COMBO_MAX_HITS:
				_perform_attack(next_step)
			else:
				_end_combo("Combo Complet")
		else:
			_end_combo("Anim Finished")

# === RPG METHODS ===
func gain_xp(amount: int):
	current_xp += amount
	print("✨ XP Gained: ", amount, " | Total: ", current_xp, "/", xp_to_next_level)
	if current_xp >= xp_to_next_level:
		_level_up()
	_update_rpg_ui()

func _level_up():
	level += 1
	current_xp -= xp_to_next_level
	xp_to_next_level = int(xp_to_next_level * 1.5)
	
	max_hp += 20
	current_hp = max_hp
	attack_damage += 5
	
	print("🌟 LEVEL UP! Level: ", level, " | HP: ", max_hp, " | DMG: ", attack_damage)
	
	# Visual FX (Particle?)
	var label = Label3D.new()
	label.text = "LEVEL UP!"
	label.modulate = Color(1, 1, 0) # Gold
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.position = Vector3(0, 3.0, 0)
	add_child(label)
	
	var tw = create_tween()
	tw.tween_property(label, "position:y", 5.0, 1.5)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 1.5)
	tw.tween_callback(label.queue_free)

func take_damage(amount: float):
	current_hp -= amount
	print("💔 OUCH! Took ", amount, " dmg. HP: ", current_hp)
	_spawn_damage_text(amount)
	
	if current_hp <= 0:
		_die()
	_update_rpg_ui()

func _die():
	print("☠️ GAME OVER")
	# Respawn Logic placeholder
	global_position.y += 10 # Pop up
	current_hp = max_hp
	
func _spawn_damage_text(amount):
	var label = Label3D.new()
	label.text = str(int(amount))
	label.modulate = Color(1, 0, 0) # Red
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.position = Vector3(0, 2.0, 0)
	add_child(label)
	
	var tw = create_tween()
	tw.tween_property(label, "position:y", 3.0, 0.5)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(label.queue_free)

func _update_rpg_ui():
	# Update Stamina Bar color based on HP? Or just print for now
	# We can reuse the Stamina UI codebase to add a Health Bar later.
	pass
