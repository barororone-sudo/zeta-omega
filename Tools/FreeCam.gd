extends Camera3D

@export var move_speed: float = 60.0
@export var look_speed: float = 0.005
@export var fast_multiplier: float = 3.0

var rotation_target: Vector3 = Vector3.ZERO
var active: bool = false

func _ready():
	rotation_target = rotation
	process_mode = Node.PROCESS_MODE_ALWAYS # Ensure it runs even if player is paused

func _input(event):
	if not active: return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation_target.y -= event.relative.x * look_speed
		rotation_target.x -= event.relative.y * look_speed
		rotation_target.x = clamp(rotation_target.x, -PI/2, PI/2)
		rotation = rotation_target

func _process(delta):
	if not active: return
	
	var input_dir = Vector3.ZERO
	# Support both QWERTY (WASD) and AZERTY (ZQSD)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z): input_dir.z -= 1
	if Input.is_key_pressed(KEY_S): input_dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	
	# Height
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E): input_dir.y += 1
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_F): input_dir.y -= 1
	
	var multiplier = fast_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var move_vec = (global_basis * input_dir).normalized() * move_speed * multiplier * delta
	global_position += move_vec

func enable():
	active = true
	make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("📸 Spectator Cam Active (ZQSD / WASD)")

func disable():
	active = false
