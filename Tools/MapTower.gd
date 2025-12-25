extends MapPoint

@export var reveal_radius: float = 1200.0 

var player_in_range = null
@onready var anim = $AnimationPlayer

func _ready() -> void:
	type = Type.TOWER
	# Fallback ID if not set
	if id == "": id = "tower_" + str(global_position.snapped(Vector3(1,1,1)))
	region_id = id # For towers, region_id is their own ID
	
	super._ready() # Registers to MapManager
	
	if has_node("InteractionHint"):
		get_node("InteractionHint").visible = false
		
	_setup_visual_beam()
	
	# CRITICAL: Register to GameManager so Minimap sees us at Runtime!
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").register_tower(global_position, id)

func _setup_visual_beam():

	# Create a Vertical Beam
	var beam_mesh = MeshInstance3D.new()
	beam_mesh.name = "LightBeam"
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 200.0 # Sky beam
	beam_mesh.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 0, 0, 0.4) # Red transparent
	mat.emission_enabled = true
	mat.emission = Color(1, 0, 0)
	mat.emission_energy_multiplier = 5.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mesh.material_override = mat
	beam_mesh.position.y = 100.0
	add_child(beam_mesh)
	
	# Light
	var spot = SpotLight3D.new()
	spot.name = "BeamLight"
	spot.light_color = Color(1, 0, 0)
	spot.light_energy = 10.0
	spot.spot_range = 200.0
	spot.spot_angle = 15.0
	spot.rotation_degrees.x = -90 # Point UP
	add_child(spot)


func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and not is_active:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_E or event.keycode == KEY_F:
				activate()
		elif event.is_action_pressed("interact"):
			activate()



# Wiring existing signals if scene uses them
func _on_interact_body_entered(body): # Renamed to match scene signal
	if body.is_in_group("Player") and not is_active:
		player_in_range = body
		if has_node("InteractionHint"):
			get_node("InteractionHint").visible = true
			get_node("InteractionHint").text = "Appuyez sur [F] pour activer" # Ensure text
		print("💡 Appuie sur [F] pour activer la tour")

func _on_interact_body_exited(body): # Renamed to match scene signal
	if body == player_in_range:
		player_in_range = null
		if has_node("InteractionHint"):
			get_node("InteractionHint").visible = false


func activate() -> void:
	if is_active: return
	
	# 1. Base MapPoint Logic (Update MapManager -> Icons Blue)
	super.activate()
	
	print("🗼 Tour activée : ", id)
	
	if has_node("InteractionHint"):
		get_node("InteractionHint").visible = false
	
	# 2. Unlock Fog in GameManager (Spatial)
	var pos_2d = Vector2(global_position.x, global_position.z)
	GameManager.unlock_region(pos_2d, reveal_radius)
	
	# 3. Visual Feedback
	if anim: anim.play("Activate")
	
	# Update Beam Color to BLUE
	var beam = get_node_or_null("LightBeam")
	if beam:
		var mat = beam.material_override
		if mat:
			var tween = create_tween()
			tween.tween_property(mat, "albedo_color", Color(0, 0.5, 1, 0.4), 1.0)
			tween.parallel().tween_property(mat, "emission", Color(0, 0.5, 1), 1.0)
			
	var spot = get_node_or_null("BeamLight")
	if spot:
		var tween = create_tween()
		tween.tween_property(spot, "light_color", Color(0, 0.5, 1), 1.0)

	
	# Material change is handled by MapPoint automatically (it finds the mesh)
