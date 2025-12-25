extends CharacterBody3D
class_name Player

## Player Controller - ZETA OMEGA (Final Version + Exploration Update)
## Features: Jump Snappy, Combo 3-Hit, Mixamo Fix, STAMINA, CLIMBING, GLIDING

# === EXPORT VARIABLES ===
@export_group("Movement")
@export var move_speed: float = 5.0
@export var acceleration: float = 20.0 # Snappy Movement
@export var rotation_speed: float = 12.0 # Faster Rotation

# ...


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
@export var water_level: float = 2.0 # Water surface Y height

@export_group("Camera")
@export var mouse_sensitivity: float = 0.003

@export_group("Animations")
@export var anim_climb_idle: String = "Climbing Idle"
@export var anim_climb_up: String = "Climbing Up"
@export var anim_climb_down: String = "Climbing Down"
@export var anim_climb_left: String = "Climbing Left" # BONUS
@export var anim_climb_right: String = "Climbing Right" # BONUS

@export var anim_glide: String = "Glider Hang" # ou "Falling Idle"
@export var anim_swim: String = "Swimming" # Mixamo "Swimming"
@export var anim_swim_idle: String = "Swim Idle" # Treading Water


# === NODES ===
@onready var camera_pivot: Node3D = $CameraPivot
@onready var visuals: Node3D = $Visuals
@onready var skeleton: Skeleton3D # Sera récupéré dynamiquement
@onready var main_camera: Camera3D = $Camera3D
@onready var phantom_camera: Node3D = $PhantomCamera3D
var animation_player: AnimationPlayer = null # Needed for runtime reference

# DYNAMIC NODES (Created in code)
var wall_cast: RayCast3D
var stamina_bar: TextureProgressBar
var hp_bar: TextureProgressBar
var xp_bar: TextureProgressBar
var hud_level_label: Label
var free_cam: Camera3D = null
var glider_mesh: Node3D
var debug_label: Label

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
enum State { NORMAL, CLIMB, GLIDE, SWIM }
var current_state: State = State.NORMAL
var is_sprinting: bool = false # SPRINT STATE

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
	_apply_toon_shader()
	
	# NIGHT LIGHT (Fairy - Subtle)
	var light = OmniLight3D.new()
	light.name = "PlayerLight"
	light.light_color = Color(1.0, 0.9, 0.7) 
	light.light_energy = 0.1 # Reduced from 0.5 (Too bright)
	light.omni_range = 10.0
	light.position = Vector3(0, 2.0, 0)
	add_child(light)
	
	# SETUP EXPLORATION
	main_camera.environment = null # Fix: Clear local env to see Sky/DayNight cycle
	_setup_wall_detector()
	_setup_stamina_ui()
	_setup_glider_visuals()
	_setup_rpg_ui()
	
	# SETUP PHANTOM CAMERA
	if phantom_camera:
		print("👻 Phantom Camera Initialized")
		phantom_camera.follow_mode = 6 # THIRD_PERSON
		phantom_camera.look_at_mode = 0 # NONE (Orbit handles rotation)
		phantom_camera.follow_target = get_node("CameraPivot")
		phantom_camera.set_follow_damping(true)
		phantom_camera.set_follow_damping_value(Vector3(0.1, 0.1, 0.1)) # Smoothing
		# Set initial distance
		phantom_camera.spring_length = 4.0
		phantom_camera.collision_mask = 1 # Terrain
		
		# Provisoirement plus haut pour assurer la priorité
		phantom_camera.priority = 30
		
		# Sync initial orientation
		var initial_rot = phantom_camera.get_third_person_rotation()
		cam_yaw = initial_rot.y
		cam_pitch = initial_rot.x
		print("🎥 Camera Yaw:", cam_yaw, " Pitch:", cam_pitch)
	
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
	# We use a Star-Pattern of rays for "Universal" Detection
	# Shortened Rays (1.0m) to avoid snapping from far away
	var ray_configs = [
		{"name": "WallForward", "pos": Vector3(0, 1.2, 0), "dir": Vector3(0, 0, -1.0)},
		{"name": "WallHigh", "pos": Vector3(0, 1.9, 0), "dir": Vector3(0, 0, -1.0)},
		{"name": "WallLow", "pos": Vector3(0, 0.4, 0), "dir": Vector3(0, 0, -1.0)},
		{"name": "WallLeft", "pos": Vector3(-0.6, 1.2, 0), "dir": Vector3(0, 0, -1.0)},
		{"name": "WallRight", "pos": Vector3(0.6, 1.2, 0), "dir": Vector3(0, 0, -1.0)},
		{"name": "WallDiagUL", "pos": Vector3(-0.4, 1.7, 0), "dir": Vector3(0, 0, -1.0)},
		{"name": "WallDiagUR", "pos": Vector3(0.4, 1.7, 0), "dir": Vector3(0, 0, -1.0)},
		{"name": "WallHead", "pos": Vector3(0, 2.2, 0), "dir": Vector3(0, 0.4, -0.8)}, # Upwards tilt for ledges
	]

	
	for config in ray_configs:
		var r = RayCast3D.new()
		r.name = config["name"]
		r.position = config["pos"]
		r.target_position = config["dir"]
		r.collision_mask = 1 + 4 + 8 + 16 # Detect Layers 1, 3, 4, 5 (Terrain, Objects...) - EXCLUDE 2 (Player)
		r.add_exception(self) # Double Safety
		r.enabled = true
		add_child(r)

	
	# Keep the old reference for backward compatibility if needed
	wall_cast = get_node("WallForward")
	
func _setup_stamina_ui():
	# UI CanvasLayer
	var canvas = CanvasLayer.new()
	canvas.name = "StaminaUI"
	add_child(canvas)
	
	# Progress Bar (Circular if possible, simplified here)
	stamina_bar = TextureProgressBar.new()
	stamina_bar.name = "StaminaRing"
	# FIX: Don't block mouse
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		# Force orientation exactly to 0
		g.scale = Vector3(0.08, 0.08, 0.08) # Reduced from 0.15 (User Feedback: Too Big)
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

func _setup_rpg_ui():
	var canvas = CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	
	# Layout Container
	var hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE # CRITICAL CAMERA FIX
	canvas.add_child(hud)
	
	# === HEALTH BAR (Bottom Left) ===
	hp_bar = TextureProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.position = Vector2(50, get_window().size.y - 120)
	hp_bar.size = Vector2(300, 20)
	
	# Procedural Color Textures
	var bg = GradientTexture2D.new(); bg.width = 300; bg.height = 20
	var fill = GradientTexture2D.new(); fill.width = 300; fill.height = 20
	bg.fill_from = Vector2(0,0); bg.fill_to = Vector2(0,1)
	bg.gradient = Gradient.new(); bg.gradient.set_color(0, Color(0.1, 0.1, 0.1, 0.7)); bg.gradient.set_color(1, Color(0.2, 0.2, 0.2, 0.7))
	fill.gradient = Gradient.new(); fill.gradient.set_color(0, Color(0.9, 0.2, 0.2)); fill.gradient.set_color(1, Color(0.5, 0.1, 0.1))
	
	hp_bar.texture_under = bg
	hp_bar.texture_progress = fill
	hp_bar.value = 100
	hud.add_child(hp_bar)
	
	# === XP BAR (Bottom Center - Slender) ===
	xp_bar = TextureProgressBar.new()
	xp_bar.name = "XPBar"
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	xp_bar.position.y -= 30
	xp_bar.size = Vector2(600, 6)
	
	var xp_fill = GradientTexture2D.new(); xp_fill.width = 600; xp_fill.height = 6
	xp_fill.gradient = Gradient.new(); xp_fill.gradient.set_color(0, Color(0.1, 0.7, 1.0)); xp_fill.gradient.set_color(1, Color(0, 0.4, 0.8)) # Cyan/Blue
	
	xp_bar.texture_progress = xp_fill
	xp_bar.value = 0
	hud.add_child(xp_bar)
	
	# === LEVEL LABEL ===
	hud_level_label = Label.new()
	hud_level_label.name = "LevelLabel"
	hud_level_label.position = Vector2(50, get_window().size.y - 160)
	hud_level_label.text = "LV. 1"
	hud_level_label.add_theme_font_size_override("font_size", 24)
	hud_level_label.add_theme_color_override("font_color", Color.GOLD)
	hud.add_child(hud_level_label)
	
	# === DEBUG LABEL ===
	debug_label = Label.new()
	debug_label.name = "DebugInfo"
	debug_label.position = Vector2(50, 200)
	debug_label.add_theme_font_size_override("font_size", 24)
	debug_label.add_theme_color_override("font_color", Color(1, 0.4, 0.7)) # Hot Pink (Rose)
	debug_label.add_theme_constant_override("outline_size", 4)
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)

	debug_label.add_theme_color_override("font_color", Color.MAGENTA)
	debug_label.text = "DEBUG INITIALIZING..."
	canvas.add_child(debug_label)

func _snap_to_terrain() -> void:
	var h = 0.0 # Default flat ground
	if global_position.y < h:
		global_position.y = h + 1.0
		velocity.y = 0
		print("🚀 Snapped Player to Surface (Simple): Y=", global_position.y)

func _physics_process(delta: float) -> void:
	# STATE MACHINE
	
	# STATE MACHINE
	match current_state:
		State.NORMAL:
			_state_normal(delta)
		State.CLIMB:
			_state_climb(delta)
		State.GLIDE:
			_state_glide(delta)
		State.SWIM:
			_state_swim(delta)
	
	# STAMINA REGEN (Si on ne grimpe pas et ne plane pas ET QU'ON NE COURT PAS)
	if current_state == State.NORMAL and not is_sprinting:
		if current_stamina < max_stamina:
			current_stamina += stamina_regen_rate * delta
			if current_stamina > max_stamina: current_stamina = max_stamina

	# UI UPDATE (Always update if not full)
	if current_stamina >= max_stamina - 0.1: # Threshold to hide
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
	
	
	_update_debug_info()
	move_and_slide()

# === STATE: NORMAL ===
func _state_normal(delta: float) -> void:
	# 1. GRAVITY & AIR CHECKS
	if is_on_floor():
		# CHECK CLIMB (GROUND) - Allow starting climb by walking into wall
		if _is_any_wall_colliding() and Input.is_action_pressed("move_forward"):
			_enter_climb_state()
			return
	else:
		velocity.y -= gravity * delta
		
		# CHECK GLIDE
		if Input.is_action_just_pressed("ui_accept") and not is_attacking:
			_enter_glide_state()
			return
		
		# CHECK WATER (Enter Swim)
		# Prevent re-entering swim state if we are jumping OUT of water (velocity.y > 0)
		if global_position.y < water_level - 0.5 and velocity.y <= 0:
			_enter_swim_state()
			return
		
		# CHECK CLIMB (AIR) - Grab if touching wall in air
		if _is_any_wall_colliding():
			_enter_climb_state()
			return


	# 2. INSTANT JUMP
	if jump_delay_timer > 0:
		jump_delay_timer -= delta
		if jump_delay_timer <= 0:
			# Safety check: Don't jump if we entered swim state in the meantime
			if current_state == State.NORMAL:
				velocity.y = jump_force

	# JUMP INPUT (Only on floor and NOT underwater)
	var is_underwater = global_position.y < water_level - 0.2
	if is_on_floor() and not is_underwater and Input.is_action_just_pressed("ui_accept") and not is_attacking and jump_delay_timer <= 0:
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

# === STATE: SWIM ===
func _state_swim(delta: float) -> void:
	# Exit Condition: Surface
	# We exit if we are clearly above the water level and moving UP (jumping out)
	# or if we are high enough above the surface.
	if global_position.y > water_level + 0.5:
		_exit_swim_state()
		return

		
	# Buoyancy: Tend to surface
	var depth = water_level - global_position.y
	
	# Apply buoyancy with smoothing
	if depth > -0.2: # If even slightly below or at surface
		# Buoyancy Target: 0.0 (Float) or slightly up if submerged
		var target_up = clamp(depth * 8.0, -1.0, 5.0)
		velocity.y = lerp(velocity.y, target_up, delta * 3.0)
	else:
		# Above water: Gravity (already applied? No, we are in SWIM state)
		velocity.y -= 10.0 * delta # Sinking back to surface

	
	# Input (Relative to Camera)
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir == Vector2.ZERO: 
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	var dir = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		var cam_basis = camera_pivot.global_basis
		var forward = -cam_basis.z; var right = cam_basis.x
		forward.y = 0; right.y = 0
		dir = (forward.normalized() * -input_dir.y + right.normalized() * input_dir.x).normalized()

	# Swim Movement
	velocity.x = lerp(velocity.x, dir.x * move_speed * 0.8, acceleration * 0.5 * delta)
	velocity.z = lerp(velocity.z, dir.z * move_speed * 0.8, acceleration * 0.5 * delta)
	
	# Vertical Control overrides Buoyancy
	if Input.is_action_pressed("ui_accept"): # Jump/Surface
		velocity.y = 5.0
	elif Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C): # Dive
		velocity.y = -5.0
		
	# Rotation
	if dir.length() > 0.01:
		var target_angle = atan2(dir.x, dir.z) - global_rotation.y
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)

	# ANIMATION (Swim vs Idle)
	if animation_player:
		var speed = Vector2(velocity.x, velocity.z).length()
		var target_anim = anim_swim_idle if speed < 0.5 else anim_swim
		if animation_player.current_animation != target_anim and animation_player.has_animation(target_anim):
			animation_player.play(target_anim, 0.4) 

func _enter_swim_state():
	current_state = State.SWIM
	print("🏊 Swim Start")
	velocity.y *= 0.1 # Splash damping
	if animation_player and animation_player.has_animation(anim_swim):
		animation_player.play(anim_swim, 0.5)

func _exit_swim_state():
	current_state = State.NORMAL
	print("🏊 Swim End")
	# Pop out jump
	if Input.is_action_pressed("ui_accept"):
		velocity.y = jump_force # Launch out
		if animation_player and animation_player.has_animation("Jump"):
			animation_player.play("Jump", 0.1)
	else:
		# Just surface, do NOT launch
		# If moving up fast, clamp it so we don't fly
		if velocity.y > 2.0: velocity.y = 2.0


# === STATE: CLIMB ===
func _state_climb(delta: float) -> void:
	var colliding_rays = []
	for c in get_children():
		if c is RayCast3D and c.name.begins_with("Wall") and c.is_colliding():
			colliding_rays.append(c)
	
	if colliding_rays.is_empty() or current_stamina <= 0:
		_exit_climb_state()
		return
		
	# LEDGE POP LOGIC: If a low ray hits but the high ray doesn't, we are at a ledge
	var head_hit = get_node("WallHead").is_colliding()
	var forward_hit = get_node("WallForward").is_colliding()
	if not head_hit and not forward_hit and get_node("WallLow").is_colliding():
		# Auto-hop up
		velocity.y = 8.0
		velocity += -global_transform.basis.z * 5.0
		_exit_climb_state()
		return

	# Consume Stamina
	current_stamina -= climb_stamina_cost * delta
	
	# Detect wall normal (average of hits for stability)
	var wall_normal = Vector3.BACK
	var hits = 0
	for r in colliding_rays:
		wall_normal += r.get_collision_normal()
		hits += 1
	wall_normal = (wall_normal / hits).normalized()
			
	# Look at Wall
	var look_dir = -wall_normal
	look_dir.y = 0
	if look_dir.length() > 0.01:
		var target_quat = Quaternion(Basis.looking_at(look_dir, Vector3.UP))
		visuals.quaternion = visuals.quaternion.slerp(target_quat, 15.0 * delta)
	
	# Input
	var move_up = Input.is_physical_key_pressed(KEY_Z) or Input.is_physical_key_pressed(KEY_W)
	var move_down = Input.is_physical_key_pressed(KEY_S)
	var move_left = Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_A)
	var move_right = Input.is_physical_key_pressed(KEY_D)
	
	velocity = Vector3.ZERO
	var actual_climb_speed = climb_speed * 1.5 # Boosted for feel
	
	if move_up: velocity.y = actual_climb_speed
	elif move_down: velocity.y = -actual_climb_speed
	
	var right = wall_normal.cross(Vector3.UP).normalized()
	if move_left: velocity -= right * actual_climb_speed
	elif move_right: velocity += right * actual_climb_speed
	
	# Extreme Magnetism (Stay on wall)
	velocity -= wall_normal * 3.0
	
	# Animations
	if animation_player:
		var raw_anim = anim_climb_idle
		if move_up: raw_anim = anim_climb_up
		elif move_down: raw_anim = anim_climb_down
		elif move_left: raw_anim = anim_climb_left
		elif move_right: raw_anim = anim_climb_right
		
		if animation_player.has_animation(raw_anim):
			animation_player.play(raw_anim, 0.1)
			var move_speed_ratio = velocity.length() / actual_climb_speed
			if move_speed_ratio < 0.1:
				animation_player.speed_scale = 0.0
			else:
				animation_player.speed_scale = move_speed_ratio * 1.5
		else:
			if animation_player.has_animation("Idle"): animation_player.play("Idle", 0.2)
			
	# Jump off
	if Input.is_action_just_pressed("ui_accept"):
		current_stamina -= climb_jump_cost
		velocity = (wall_normal + Vector3.UP).normalized() * jump_force
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
	
	# Input (Relative to Camera)
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir == Vector2.ZERO: 
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# AZERTY FALLBACK (If not mapped via InputMap)
	if input_dir == Vector2.ZERO:
		if Input.is_physical_key_pressed(KEY_Z): input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_physical_key_pressed(KEY_Q): input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
		if input_dir.length() > 1: input_dir = input_dir.normalized()

	# CALC TARGET VELOCITY (Camera Relative)
	var target_vel = Vector3.ZERO
	
	if input_dir != Vector2.ZERO:
		var cam_basis = camera_pivot.global_basis
		var forward = -cam_basis.z; var right = cam_basis.x
		forward.y = 0; right.y = 0
		forward = forward.normalized(); right = right.normalized()
		
		# Standard Movement mapping
		var dir = (forward * -input_dir.y + right * input_dir.x).normalized()
		target_vel = dir * glide_speed
		
		# ROTATE VISUALS TO FACE DIRECTION
		var target_angle = atan2(dir.x, dir.z) - global_rotation.y
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 5.0 * delta)
		
	else:
		# Hover (Brake)
		target_vel = Vector3.ZERO
	
	# PRESERVE MOMENTUM (Inertia)
	velocity.x = lerp(velocity.x, target_vel.x, 2.0 * delta)
	velocity.z = lerp(velocity.z, target_vel.z, 2.0 * delta)
	
	# GRAVITY (Constant fall speed)
	velocity.y = lerp(velocity.y, -glide_fall_speed, 2.0 * delta)
	
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
	if animation_player:
		animation_player.play("Idle", 0.3) # Fallback to idle pose while falling
		
	# LANDING BRAKE
	velocity.x *= 0.2
	velocity.z *= 0.2
	
	print("🪁 Glide End")

func _is_any_wall_colliding() -> bool:
	var hits = []
	if wall_cast and wall_cast.is_colliding(): hits.append(wall_cast)
	var r_low = get_node_or_null("RayLow")
	if r_low and r_low.is_colliding(): hits.append(r_low)
	var r_high = get_node_or_null("RayHigh")
	if r_high and r_high.is_colliding(): hits.append(r_high)
	
	# New Layout Check
	for c in get_children():
		if c is RayCast3D and c.name.begins_with("Wall") and c.is_colliding():
			hits.append(c)
	
	for r in hits:
		var n = r.get_collision_normal()
		# ANGLE CHECK: Climb slopes steeper than ~40 degrees
		# Dot with UP. 0=Vertical, 1=Flat. 
		# Walkable is usually > 0.707 (45 deg).
		# We climb anything < 0.75 (Overlap with walkable to ensure no "dead zone").
		if abs(n.dot(Vector3.UP)) < 0.75:
			return true
			
	return false

# === MOVEMENT HELPERS ===
func _handle_standard_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	if input_dir == Vector2.ZERO: 
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# ROBUST AZERTY FALLBACK (Additive)
	# If default actions aren't mapped or user presses unmapped keys, we catch them here.
	if input_dir.y == 0:
		if Input.is_physical_key_pressed(KEY_Z): input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
	if input_dir.x == 0:
		if Input.is_physical_key_pressed(KEY_Q): input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
		
	# Normalize immediately if we mixed inputs
	if input_dir.length_squared() > 1.0: input_dir = input_dir.normalized()
		
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
	
		direction = (forward * -input_dir.y + right * input_dir.x).normalized()
	
	if direction.length() > 0.01:
		# SPRINT LOGIC
		var speed_modifier = 1.0
		
		# Check for Shift (Sprint)
		var wants_sprint = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SHIFT)
		var can_sprint = false
		
		# HYSTERESIS: Require 10 Stamina to START sprinting, but 0 to CONTINUE.
		if is_sprinting:
			can_sprint = current_stamina > 0.0
		else:
			can_sprint = current_stamina > 10.0 # Must recover a bit before running again
		
		if wants_sprint and can_sprint:
			speed_modifier = 2.0 # Run even faster (x2)
			is_sprinting = true
			current_stamina -= 30.0 * delta # Cost 30/sec
			if current_stamina < 0: current_stamina = 0
		else:
			is_sprinting = false
		
		velocity.x = lerp(velocity.x, direction.x * move_speed * speed_modifier, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * move_speed * speed_modifier, acceleration * delta)
		
		# VISUALS ROTATION FIX: Account for Root Rotation!
		var target_angle = atan2(direction.x, direction.z) - global_rotation.y
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)

	# DEBUG PROBE
	if Input.is_physical_key_pressed(KEY_ENTER):
		_probe_scene_tree()

func _probe_scene_tree():
	print("\n🔍 === SCENE TREE PROBE ===")
	var root = get_tree().root
	_print_node_recursive(root, 0)
	print("🔍 =========================\n")

func _print_node_recursive(node: Node, depth: int):
	var prefix = ""
	for i in range(depth): prefix += "  "
	
	var info = prefix + "📄 " + node.name + " (" + node.get_class() + ")"
	if node.name == "HTerrain": info += " 📍 [TARGET FOUND!]"
	if node == GameManager.terrain_node: info += " 🔗 [LINKED]"
	
	print(info)
	
	# Don't go too deep into engine nodes, but check everything under AutoStart
	if depth > 10: return
	
	for child in node.get_children():
		_print_node_recursive(child, depth + 1)

func _update_debug_info() -> void:
	if not debug_label: return
	
	var txt = "DEBUG MODE\n"
	txt += "FPS: " + str(Engine.get_frames_per_second()) + "\n"
	txt += "State: " + str(State.keys()[current_state]) + "\n"
	txt += "Pos: " + str(global_position) + "\n"
	txt += "Biome: " + str(_get_biome_at_pos(global_position)) + "\n"
	
	if wall_cast and wall_cast.is_colliding():
		var n = wall_cast.get_collision_normal()
		var d = n.dot(Vector3.UP)
		txt += "Wall Dot: " + str(snapped(d, 0.01)) + " (" + ("OK" if abs(d) < 0.75 else "FLAT") + ")\n"
	else:
		txt += "Wall: NO HIT\n"
		
	debug_label.text = txt
	debug_label.visible = true

func _get_biome_at_pos(pos: Vector3) -> String:
	var t_node = GameManager.terrain_node
	var t_data = GameManager.terrain_data
	
	if not t_node:
		# Priority 1: Group-based discovery (Guaranteed for generated terrain)
		var active_nodes = get_tree().get_nodes_in_group("ActiveTerrain")
		if active_nodes.size() > 0: t_node = active_nodes[0]
		
		# Priority 2: Name-based fallback
		if not t_node: t_node = get_tree().root.find_child("HTerrain_Active", true, false)
		if not t_node: t_node = get_tree().root.find_child("HTerrain", true, false)
		
		if t_node:
			GameManager.terrain_node = t_node

	
	# AGGRESSIVE RECOVERY: If data is missing (even if node exists), try to fetch it
	if t_node and not t_data:
		if t_node.has_method("get_data"):
			t_data = t_node.get_data()
		
		# Fallback to multiple potential property names
		if not t_data: t_data = t_node.get("data")
		if not t_data: t_data = t_node.get("terrain_data")
		if not t_data: t_data = t_node.get("terraindata") # Some versions use this
		
		# Update Global if found
		if t_data: GameManager.terrain_data = t_data

	
	if t_node and t_data:
		var map_scale = t_node.map_scale
		var tx = int(pos.x / map_scale.x)
		var tz = int(pos.z / map_scale.z)
		var res = t_data.get_resolution()
		
		if tx >= 0 and tx < res and tz >= 0 and tz < res:
			var img_idx = t_data.get_image(6) # INDEX CHANNEL
			if img_idx:
				var pixel_idx = img_idx.get_pixel(tx, tz)
				var biome_id = int(pixel_idx.r * 255.0)
				
				if biome_id == 0: return "GRASS MAIN (0)"
				elif biome_id == 1: return "CLIFF MOSS (1)"
				elif biome_id == 2: return "BEACH (2)"
				elif biome_id == 3: return "DUNES (3)"
				elif biome_id == 4: return "CLIFF (4)"
				elif biome_id == 5: return "GRASS WILD (5)"
				elif biome_id == 6: return "FOREST FLOOR (6)"
				elif biome_id == 7: return "MTN BASE (7)"
				elif biome_id == 8: return "SNOW (8)"
				elif biome_id == 9: return "MUD (9)"
				else: return "BIOME ("+str(biome_id)+")"
			else:
				return "Err: No Image(6) on " + t_node.name
		else:
			return "Err: OOB " + str(Vector2(tx, tz))
	
	if not t_node: return "Err: No HTerrain Node"
	if not t_data: return "Err: No Data in " + str(t_node.name if t_node else "null") + " (" + str(t_node.get_path() if t_node else "null") + ")"
	return "Unknown"

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
	if h_speed > 6.0: target = "Run" # Sprint
	elif h_speed > 0.1: target = "Walk" # Normal
	
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
	elif "swimming" in lower_name and not "edge" in lower_name: target_name = "Swimming"
	elif "treading water" in lower_name: target_name = "Swim Idle"
	elif "swimming to edge" in lower_name: target_name = "Swim Edge"
	
	
	
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
			
			anim_resource.loop_mode = Animation.LOOP_LINEAR if target_name in ["Idle", "Run", "Walk", "Climbing Idle", "Climbing Up", "Climbing Down", "Glider Hang", "Swimming", "Swim Idle"] else Animation.LOOP_NONE
			
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

# --- CAMERA CONTROL ---
var cam_yaw: float = 0.0
var cam_pitch: float = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# print("🖱️ Mouse Motion:", event.relative) # Debug
		cam_yaw -= event.relative.x * mouse_sensitivity
		cam_pitch -= event.relative.y * mouse_sensitivity
		cam_pitch = clamp(cam_pitch, deg_to_rad(-60), deg_to_rad(60))
		
		if phantom_camera:
			# Phantom Camera handles the orbit visually
			phantom_camera.set_third_person_rotation(Vector3(cam_pitch, cam_yaw, 0))
			# We rotate the pivot for movement orientation (WASD)
			camera_pivot.rotation.y = cam_yaw
		else:
			# Fallback if no phantom camera
			camera_pivot.rotation.y = cam_yaw
			# Note: spring_arm was removed in latest version, so we skip it to avoid crash
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		
	# FREE CAMERA TOGGLE (V Key)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		_toggle_free_cam()

func _toggle_free_cam():
	if not free_cam:
		free_cam = Camera3D.new()
		free_cam.name = "FreeFlyCam"
		free_cam.set_script(load("res://Tools/FreeCam.gd"))
		get_parent().add_child(free_cam)
	
	var is_currently_free = free_cam.active if free_cam else false

	if is_currently_free:
		free_cam.disable()
		if phantom_camera: 
			phantom_camera.priority = 30 # Forcer le retour
		main_camera.make_current() 
		set_physics_process(true)
		print("🦅 Spectator Cam: OFF")
	else:
		free_cam.global_position = main_camera.global_position
		free_cam.global_rotation = main_camera.global_rotation
		if phantom_camera: phantom_camera.priority = 0 
		free_cam.enable()
		set_physics_process(false)
		print("🦅 Spectator Cam: ON")

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
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
	if xp_bar:
		xp_bar.max_value = xp_to_next_level
		xp_bar.value = current_xp
	if hud_level_label:
		hud_level_label.text = "LV. " + str(level)

# --- SHADERS ---
func _apply_toon_shader():
	var toon_shader = load("res://Assets/Shaders/Toon.gdshader")
	if not toon_shader: return
	
	if not visuals: return
	
	print("🎨 Applying Toon Shader to Player...")
	for child in _find_all_meshes(visuals):
		# Create ShaderMaterial with Toon Shader
		var mat = ShaderMaterial.new()
		mat.shader = toon_shader
		
		# Try to preserve albedo texture if possible.
		var old_mat = child.get_active_material(0)
		if old_mat and old_mat is BaseMaterial3D:
			mat.set_shader_parameter("albedo", old_mat.albedo_color)
			mat.set_shader_parameter("texture_albedo", old_mat.albedo_texture)
		
		child.material_override = mat

func _find_all_meshes(node):
	var res = []
	if node is MeshInstance3D: res.append(node)
	for c in node.get_children():
		res.append_array(_find_all_meshes(c))
	return res
