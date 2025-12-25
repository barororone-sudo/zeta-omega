extends Node3D
class_name MapPoint

enum Type { TOWER, TELEPORT }

# === CONFIGURATION ===
@export var id: String = ""
@export var region_id: String = ""
@export var type: Type = Type.TELEPORT

# === INTERNALS ===
var is_active: bool = false

# Compatibility alias for Minimap/GameManager
var activated: bool : 
	get: return is_active
	set(val): is_active = val

var mesh_instance: MeshInstance3D
var interaction_area: Area3D

func _ready() -> void:
	if id == "": id = name + "_" + str(global_position.snapped(Vector3(1,1,1)))
	
	setup_interaction()
	find_mesh()
	
	# REGISTER & CONNECT
	# Assumes 'MapManager' is an Autoload Singleton
	if has_node("/root/MapManager"):
		var mm = get_node("/root/MapManager")
		mm.register_point(id, region_id)
		mm.map_updated.connect(_on_map_updated)
		_on_map_updated() # Initial State
	else:
		printerr("⚠️ MapManager Autoload not found!")


	# Initial Visual State (Force Red if not active)
	set_visual_state(is_active)


func setup_interaction() -> void:
	# Check if Area3D exists, else create it
	interaction_area = get_node_or_null("Area3D")
	if not interaction_area:
		interaction_area = Area3D.new()
		interaction_area.name = "InteractionArea"
		add_child(interaction_area)
		
		var coll = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = 2.5
		coll.shape = shape
		interaction_area.add_child(coll)
	
	if not interaction_area.body_entered.is_connected(_on_body_entered):
		interaction_area.body_entered.connect(_on_body_entered)

func find_mesh() -> void:
	# Try to find a MeshInstance to colorize
	for c in get_children():
		if c is MeshInstance3D:
			mesh_instance = c
			break

func _on_map_updated() -> void:
	var mm = get_node("/root/MapManager")
	var status = mm.get_point_status(id, region_id)
	
	if status == "BLUE":
		set_visual_state(true)
	elif status == "RED" or status == "HIDDEN":
		set_visual_state(false)

func set_visual_state(active: bool) -> void:
	if is_active == active: return
	is_active = active
	
	var target_color = Color(0, 0.8, 1) if active else Color(1, 0, 0) # Blue vs Red
	
	if mesh_instance:
		# Use StandardMaterial3D emission or albedo
		# Create unique material to avoid shared resource issues
		var mat = mesh_instance.get_active_material(0)
		if not mat: 
			mat = StandardMaterial3D.new()
			mesh_instance.set_surface_override_material(0, mat)
		else:
			if mat.resource_path != "": # If it's a shared file, duplicate
				mat = mat.duplicate()
				mesh_instance.set_surface_override_material(0, mat)
		
		# TWEEN COLOR
		var tween = create_tween()
		tween.tween_property(mat, "albedo_color", target_color, 1.0)
		tween.parallel().tween_property(mat, "emission", target_color, 1.0)
		tween.parallel().tween_property(mat, "emission_energy_multiplier", 2.0 if active else 1.0, 1.0)

func activate() -> void:
	if is_active: return
	
	print("✨ Activating MapPoint: ", id)
	var mm = get_node("/root/MapManager")
	
	if type == Type.TOWER:
		mm.unlock_tower(region_id)
	else:
		mm.unlock_teleport_point(id)
	
	# Sound or Particles could be played here

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player"):
		activate()
