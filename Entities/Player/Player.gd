extends CharacterBody3D

# --- CONFIGURATION ---
@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.003
@export var gravity: float = 9.8

# --- NODES ---
@onready var visuals: Node3D = $Visuals
@onready var camera_pivot: Node3D = $CameraPivot

# --- INTERNAL ---
var skeleton: Skeleton3D = null
var animation_player: AnimationPlayer = null
var head_bone_idx: int = -1
var neck_bone_idx: int = -1

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# 1. SETUP ANIMATIONS (Injection + Finding Player)
	_setup_animations()
	
	# 2. SETUP SKELETON (For Head Spin Fix)
	skeleton = find_skeleton(visuals)
	if skeleton:
		print("SKELETON FOUND: ", skeleton.name)
		# Rechercher les os de la tête et du cou
		# On cherche "Head" ou "mixamorig:Head" (sensible à la casse parfois)
		head_bone_idx = _find_bone_fuzzy(skeleton, "Head")
		neck_bone_idx = _find_bone_fuzzy(skeleton, "Neck")
		print("Head Index: ", head_bone_idx, " Neck Index: ", neck_bone_idx)
	else:
		print("CRITICAL: SKELETON NOT FOUND !")

func _process(delta: float) -> void:
	# --- 3. CORRECTION TETE (HEAD SPIN FIX) ---
	# Force la rotation à 0 APRES l'animation
	if skeleton:
		if head_bone_idx != -1:
			skeleton.set_bone_pose_rotation(head_bone_idx, Quaternion.IDENTITY)
		if neck_bone_idx != -1:
			skeleton.set_bone_pose_rotation(neck_bone_idx, Quaternion.IDENTITY)

	# DEBUG UI
	_update_debug_ui()

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# --- 1. INPUTS PAR DEFAUT (ROBUSTE) ---
	# On utilise ui_left/right/up/down pour être sûr à 100% que ça marche
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# DEBUG: Pour vérifier si le clavier marche
	if input_dir.length() > 0:
		# print("Input reçu : ", input_dir) # Uncomment for spam
		pass

	# --- 2. MOUVEMENT RELATIF A LA CAMERA ---
	var direction := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		# On prend la direction "devant" de la caméra (Basis Z) et "droite" (Basis X)
		# On ignore la rotation Y de la caméra pour ne pas "voler" vers le ciel
		var cam_basis = camera_pivot.global_transform.basis
		direction = (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		direction.y = 0 # Force le mouvement au sol
		direction = direction.normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# Rotation fluide du personnage
		var target_rot_y = atan2(velocity.x, velocity.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_rot_y, 0.15)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	
	# Gestion Animations de base
	_handle_movement_animation(velocity.length())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			get_tree().quit()
			
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		var new_rotation_x = camera_pivot.rotation.x - (event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(new_rotation_x, deg_to_rad(-90), deg_to_rad(30))
		camera_pivot.orthonormalize()

# --- HELPERS ---

func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var s = find_skeleton(child)
		if s: return s
	return null

func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var ap = find_animation_player(child)
		if ap: return ap
	return null

func _find_bone_fuzzy(skel: Skeleton3D, bone_name: String) -> int:
	# Cherche Exact, puis Mixamo prefix, puis contains
	var idx = skel.find_bone(bone_name)
	if idx != -1: return idx
	
	idx = skel.find_bone("mixamorig:" + bone_name)
	if idx != -1: return idx
	
	idx = skel.find_bone("Mixamorig:" + bone_name)
	if idx != -1: return idx
	
	# Recherche brute (parcours tous les os)
	for i in range(skel.get_bone_count()):
		var bname = skel.get_bone_name(i)
		if bone_name in bname:
			return i
	return -1

func _handle_movement_animation(speed_len: float) -> void:
	if not animation_player: return
	
	var anim_to_play = "Idle"
	if speed_len > 0.1:
		anim_to_play = "Run"
	
	# Fuzzy play logic
	if animation_player.has_animation(anim_to_play):
		if animation_player.current_animation != anim_to_play:
			animation_player.play(anim_to_play, 0.2)
	else:
		# Fallback: Play ANYTHING active if standard names involve
		# This handles the "mixamo.com" vs "Run" issue automatically
		_play_any_containing(anim_to_play)

func _play_any_containing(partial_name: String) -> void:
	if animation_player.current_animation.to_lower().contains(partial_name.to_lower()):
		return # Already playing something relevant
		
	for anim in animation_player.get_animation_list():
		if partial_name.to_lower() in anim.to_lower():
			animation_player.play(anim, 0.2)
			return

func _setup_animations() -> void:
	# 1. Injecter les fichiers externes (Run.fbx etc)
	_inject_external_animations()
	
	# 2. Trouver l'anim player final
	animation_player = find_animation_player(self)
	
	# 3. Looping
	if animation_player:
		for anim_name in animation_player.get_animation_list():
			var anim = animation_player.get_animation(anim_name)
			var al = anim_name.to_lower()
			if "run" in al or "idle" in al or "walk" in al:
				anim.loop_mode = Animation.LOOP_LINEAR

func _inject_external_animations() -> void:
	var anims_to_load = {
		"Run": "res://Assets/Animations/Sword And Shield Run.fbx",
		"Idle": "res://Assets/Animations/Sword And Shield Idle.fbx",
		"Jump": "res://Assets/Animations/Jumping.fbx"
	}
	
	var target = find_animation_player(self)
	if not target: return
	
	var library = target.get_animation_library("")
	if not library:
		library = AnimationLibrary.new()
		target.add_animation_library("", library)
	
	var skeleton_path = NodePath("")
	if skeleton:
		skeleton_path = target.get_parent().get_path_to(skeleton)

	for key in anims_to_load:
		var path = anims_to_load[key]
		if ResourceLoader.exists(path):
			var packed = load(path)
			var tmp = packed.instantiate()
			var tmp_ap = find_animation_player(tmp)
			if tmp_ap and tmp_ap.get_animation_list().size() > 0:
				var anim = tmp_ap.get_animation(tmp_ap.get_animation_list()[0]).duplicate()
				anim.loop_mode = Animation.LOOP_LINEAR
				
				# Retargeting simple
				if skeleton:
					for i in range(anim.get_track_count()):
						var track_path = str(anim.track_get_path(i))
						# Fix Bone Names
						if ":" in track_path:
							var parts = track_path.split(":")
							var bname = parts[1].replace("Mixamorig:", "").replace("mixamorig:", "")
							anim.track_set_path(i, str(skeleton_path) + ":" + bname)
				
				library.add_animation(key, anim)
			tmp.queue_free()

func _update_debug_ui():
	var lbl = get_node_or_null("DebugStats")
	if not lbl:
		lbl = Label.new()
		lbl.name = "DebugStats"
		add_child(lbl)
		lbl.position = Vector2(10,10)
	
	var input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	lbl.text = "In: %s\nVel: %.1f\nHeadIdx: %d" % [input, velocity.length(), head_bone_idx]
