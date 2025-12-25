extends Node3D

# --- CONFIGURATION ---
@export_category("Tower Settings")
@export var is_active: bool = false
@export var region_id: int = 0
@export var activation_color: Color = Color(0.0, 0.8, 1.0) # CYAN/BLUE
@export var inactive_color: Color = Color(1.0, 0.4, 0.0) # ORANGE
@export var emission_energy: float = 3.0

# --- SIGNALS ---
signal map_region_unlocked(region_id)

# --- NODES (Expected Children) ---
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var cinematic_camera: Camera3D = $CinematicCamera
@onready var light: OmniLight3D = $OmniLight3D
@onready var launch_pad: Area3D = $LaunchPad
# We look for interaction label generically or use interaction system
# Assuming simple "Press E" for now.

var player_in_range: CharacterBody3D = null
var is_cutscene_playing: bool = false
var _original_cam_transform: Transform3D
var _materials_cloned = false

func _ready():
	_setup_materials()
	_update_visuals(true) # Instant update
	
	# Connect Interaction
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	
	# Connect Launch Pad
	launch_pad.body_entered.connect(_on_launch_pad_entered)

func _process(_delta):
	# Simple Input Detection
	if player_in_range and not is_active and not is_cutscene_playing:
		if Input.is_action_just_pressed("interact") or Input.is_physical_key_pressed(KEY_E):
			_start_activation_sequence()

# --- SETUP ---
func _setup_materials():
	# Clone materials so we don't change ALL towers
	if mesh_instance and not _materials_cloned:
		for i in range(mesh_instance.get_surface_override_material_count()):
			if mesh_instance.get_active_material(i):
				mesh_instance.set_surface_override_material(i, mesh_instance.get_active_material(i).duplicate())
		_materials_cloned = true

func _update_visuals(instant: bool = false):
	var target_color = active_color if is_active else inactive_color
	
	# Light
	if instant:
		light.light_color = target_color
		light.light_energy = 1.0 if not is_active else 2.0
	else:
		var tween = create_tween()
		tween.tween_property(light, "light_color", target_color, 2.0)
		tween.tween_property(light, "light_energy", 2.0, 2.0)

	# Material Emission (Assuming Material 0 is the glowy one)
	if mesh_instance:
		var mat = mesh_instance.get_active_material(0)
		if mat is StandardMaterial3D:
			mat.emission_enabled = true
			if instant:
				mat.albedo_color = target_color
				mat.emission = target_color
				mat.emission_energy_multiplier = emission_energy
			else:
				var tween = create_tween()
				tween.tween_property(mat, "emission", target_color, 2.0)
				tween.tween_property(mat, "albedo_color", target_color, 2.0)

# --- ACTIVATION SEQUENCE ---
func _start_activation_sequence():
	is_cutscene_playing = true
	var player = player_in_range
	
	print("🗼 Activating Tower " + str(region_id) + "...")
	
	# 1. LOCK PLAYER
	# Best way generically: Disable processing
	player.set_physics_process(false) 
	player.velocity = Vector3.ZERO
	# Hide UI if possible (optional)
	
	# 2. CAMERA TRANSITION
	var player_cam = player.find_child("Camera3D") # Assuming structure
	if not player_cam: 
		player_cam = get_viewport().get_camera_3d()
	
	# Store original cam to return later
	# We rely on PhantomCamera usually, but simple approach:
	cinematic_camera.current = true
	
	# CINEMATIC ANIMATION
	var tween = create_tween()
	# Rotate camera around tower? Or just static shot?
	# Let's do a simple "Zoom out" or "Pan"
	# Assuming CinematicCamera is placed well.
	
	# 3. ANIMATE TOWER
	await get_tree().create_timer(1.0).timeout
	is_active = true
	_update_visuals(false) # Tweened changes
	
	# Sound Effect could go here
	
	# 4. WAIT & ADMIRE
	await get_tree().create_timer(3.0).timeout
	
	# 5. UNLOCK MAP
	emit_signal("map_region_unlocked", region_id)
	print("✅ Region " + str(region_id) + " Unlocked!")
	
	# 6. RETURN CONTROL
	player_cam.current = true
	player.set_physics_process(true)
	is_cutscene_playing = false
	
	# Optional: Particles or shockwave

# --- LAUNCH PAD ---
func _on_launch_pad_entered(body):
	if is_active and body is CharacterBody3D and body.is_in_group("Player"):
		print("🚀 Launching Player!")
		body.velocity.y = 50.0 # SUPER JUMP
		# Ideally trigger Glider state immediately if Player script supports it
		# body.current_state = body.State.GLIDE 

# --- INTERACTION SIGNALS ---
func _on_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = body
		# UI Tip: "Press E to Activate"

func _on_body_exited(body):
	if body == player_in_range:
		player_in_range = null

# --- HELPER VARS ---
var active_color = activation_color # Alias
