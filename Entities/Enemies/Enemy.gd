extends CharacterBody3D
class_name Enemy

# === RPG STATS ===
@export var enemy_name: String = "Skeleton"
@export var level: int = 1
@export var base_hp: float = 30.0
@export var damage: float = 5.0
@export var xp_reward: int = 10
@export var attack_range: float = 1.5
@export var aggro_range: float = 10.0
@export var move_speed: float = 3.5

var current_hp: float
var target: Node3D = null

# === COMPONENTS ===
var anim_player: AnimationPlayer
var visuals: Node3D

# === STATE MACHINE ===
enum State { IDLE, CHASE, ATTACK, DEAD, HIT }
var current_state: State = State.IDLE
var state_timer: float = 0.0

func _ready():
	add_to_group("Enemy")
	_setup_stats()
	_find_components()
	
	# Snap to floor
	var cast = RayCast3D.new()
	cast.position.y = 1.0
	cast.target_position = Vector3(0, -50, 0)
	add_child(cast)
	cast.force_raycast_update()
	if cast.is_colliding():
		global_position = cast.get_collision_point()

func _setup_stats():
	# Simple progression curve
	var scaler = 1.0 + (level - 1) * 0.2
	current_hp = base_hp * scaler
	damage = damage * scaler
	xp_reward = int(xp_reward * scaler)

func _find_components():
	# Try to find AnimationPlayer in children (FBX import structure)
	anim_player = _find_node_by_class(self, "AnimationPlayer")
	visuals = $Visuals if has_node("Visuals") else self

func _find_node_by_class(root: Node, class_str: String) -> Node:
	if root.get_class() == class_str: return root
	for c in root.get_children():
		var res = _find_node_by_class(c, class_str)
		if res: return res
	return null

# === STATUS EFFECTS ===
var active_effects = {} # { "type": {time: 0.0, power: 0.0} }

func _physics_process(delta):
	if current_state == State.DEAD: return
	
	_process_effects(delta)
	
	# Gravity
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	
	# FREEZE CHECK
	if active_effects.has("freeze"):
		velocity.x = 0; velocity.z = 0
		move_and_slide()
		return
	
	match current_state:
		State.IDLE: _process_idle(delta)
		State.CHASE: _process_chase(delta)
		State.ATTACK: _process_attack(delta)
	
	move_and_slide()

func apply_effect(type: String, duration: float, power: float):
	if current_state == State.DEAD: return
	
	active_effects[type] = {"time": duration, "power": power}
	print("🧪 Effect Applied: " + type + " for " + str(duration) + "s")
	
	_update_effect_visuals()

func _process_effects(delta):
	var to_remove = []
	
	for type in active_effects:
		var effect = active_effects[type]
		effect.time -= delta
		
		# DoT LOGIC
		if type == "poison":
			var dmg = effect.power * delta
			current_hp -= dmg
			if int(Time.get_ticks_msec() / 500) % 2 == 0: # Damage tick visual
				pass # TODO: tiny numbers?
				
		elif type == "fire":
			var dmg = effect.power * delta
			current_hp -= dmg
		
		if effect.time <= 0:
			to_remove.append(type)
	
	for r in to_remove:
		active_effects.erase(r)
		_update_effect_visuals()
		
	if current_hp <= 0: _die()

func _update_effect_visuals():
	# Priority Coloring
	var mod = Color.WHITE
	
	if active_effects.has("freeze"): mod = Color(0.5, 0.5, 1.0) # Blue
	elif active_effects.has("fire"): mod = Color(1.0, 0.5, 0.0) # Orange
	elif active_effects.has("poison"): mod = Color(0.2, 1.0, 0.2) # Green
	
	# Apply to visuals
	if visuals:
		for c in _find_all_meshes(visuals):
			c.material_override = null # Clear previous
			# To do it properly we should use material_overlay or modulate if CanvasItem
			# For 3D meshes, modulation is tricky without custom shader.
			# Fallback: Instance color if supported or just simple debug print
			# GeometryInstance3D has 'instance_shader_parameter' or material override color
			pass
		
		# Simple Scale Pulse for reaction
		var tw = create_tween()
		tw.tween_property(visuals, "scale", Vector3(1.1, 1.1, 1.1), 0.1)
		tw.tween_property(visuals, "scale", Vector3(1, 1, 1), 0.1)
		
		# If user has a "Outline" or similar, use that.
		# For now, we assume simple modulation isn't easy on standard materials without setup.
		
	# DEBUG LABEL
	if active_effects.size() > 0:
		if not has_node("StatusLabel"):
			var l = Label3D.new()
			l.name = "StatusLabel"
			l.position = Vector3(0, 2.3, 0)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.modulate = mod
			add_child(l)
		get_node("StatusLabel").text = str(active_effects.keys())
		get_node("StatusLabel").modulate = mod
	else:
		if has_node("StatusLabel"): get_node("StatusLabel").queue_free()

func _find_all_meshes(root):
	var res = []
	if root is MeshInstance3D: res.append(root)
	for c in root.get_children():
		res.append_array(_find_all_meshes(c))
	return res



# --- STATES ---

func _process_idle(delta):
	velocity.x = move_toward(velocity.x, 0, 10 * delta)
	velocity.z = move_toward(velocity.z, 0, 10 * delta)
	
	# Look for player
	if not target:
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			var p = players[0]
			if global_position.distance_to(p.global_position) < aggro_range:
				target = p
				_switch_state(State.CHASE)

func _process_chase(_delta):
	if not target: 
		_switch_state(State.IDLE)
		return
		
	var dist = global_position.distance_to(target.global_position)
	if dist > aggro_range * 1.5:
		target = null
		_switch_state(State.IDLE)
		return
		
	if dist <= attack_range:
		_switch_state(State.ATTACK)
		return
		
	# Move towards logic (Simple direction, no navmesh for now as requested)
	var dir = (target.global_position - global_position).normalized()
	dir.y = 0
	
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	
	# Rotate visually
	if dir.length() > 0.1:
		var look_pos = global_position + dir
		look_at(Vector3(look_pos.x, global_position.y, look_pos.z), Vector3.UP)

func _process_attack(delta):
	velocity = Vector3.ZERO
	if state_timer > 0:
		state_timer -= delta
		if state_timer <= 0:
			# Damage check
			if target and global_position.distance_to(target.global_position) <= attack_range + 0.5:
				if target.has_method("take_damage"):
					target.take_damage(damage)
			_switch_state(State.CHASE)

func _switch_state(new_state):
	current_state = new_state
	state_timer = 0.0
	
	match new_state:
		State.IDLE: _play_anim("Idle")
		State.CHASE: _play_anim("Run") # Or Walk
		State.ATTACK: 
			_play_anim("Attack")
			state_timer = 1.0 # Attack duration
		State.DEAD: 
			_play_anim("Death")
			collision_layer = 0

# --- ANIMATION HELPER ---
func _play_anim(name_key: String):
	if not anim_player: return
	
	# Fuzzy matching for downloaded assets
	var anim_list = anim_player.get_animation_list()
	var best_match = ""
	
	for anim in anim_list:
		var lower = anim.to_lower()
		var key_lower = name_key.to_lower()
		
		# Priority to exact match
		if lower == key_lower:
			best_match = anim
			break
		
		# Partial match
		if key_lower in lower:
			best_match = anim
			
	if best_match != "":
		anim_player.play(best_match, 0.2)

# --- PUBLIC ---
func take_damage(amount: float):
	if current_state == State.DEAD: return
	
	current_hp -= amount
	_spawn_damage_number(int(amount))
	
	if current_hp <= 0:
		_die()
	else:
		# Flash effect could go here
		pass

func _die():
	_switch_state(State.DEAD)
	# Give XP
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		if players[0].has_method("gain_xp"):
			players[0].gain_xp(xp_reward)
			
	# Despawn
	await get_tree().create_timer(3.0).timeout
	queue_free()

func _spawn_damage_number(value: int):
	var label = Label3D.new()
	label.text = str(value)
	label.font_size = 64
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 0, 0)
	label.position = Vector3(0, 2.0, 0)
	add_child(label)
	
	# Animate up and fade
	var tw = create_tween()
	tw.tween_property(label, "position:y", 3.0, 0.5)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(label.queue_free)
