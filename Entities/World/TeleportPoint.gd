extends MapPoint

@export var biome_id_int: int = -1

func _ready() -> void:
	type = Type.TELEPORT
	if id == "": id = "tp_" + str(global_position.snapped(Vector3(1,1,1)))
	
	super._ready()
	
	# MapPoint automatically handles:
	# 1. Registration to MapManager
	# 2. Area3D creation and body_entered signal
	# 3. Activation on enter
	# 4. Color change (Red -> Blue)

