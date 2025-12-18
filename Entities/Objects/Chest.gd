extends StaticBody3D

var is_open: bool = false
@onready var anim_player: AnimationPlayer = null # Will try to find it or use Tween

func _ready() -> void:
	# Try to find AnimationPlayer in the imported GLTF scene
	if has_node("chest/AnimationPlayer"):
		anim_player = $chest/AnimationPlayer

func interact() -> void:
	if is_open:
		return
	
	is_open = true
	print("Chest Opened!")
	
	if anim_player and anim_player.has_animation("open"):
		anim_player.play("open")
	else:
		# Fallback Tween animation (rotate lid if possible, or scale punch)
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector3(1.1, 1.1, 1.1), 0.1)
		tween.tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
		# Attempt to rotate lid if we can find a child named "lid" or similar, otherwise just bounce
		# For KayKit chest, usually requires bone animation or separate lid node. 
		# If it's a single mesh, scaling is the safe feedback.
