@tool
extends Control

# --- CONFIGURATION ---
@export_group("References")
@export var health_bar_path: NodePath = "HealthBar"
@export var stamina_bar_path: NodePath = "StaminaBar"
@export var level_label_path: NodePath = "LevelLabel"

# --- NODES ---
@onready var health_bar: TextureProgressBar = get_node_or_null(health_bar_path)
@onready var stamina_bar: TextureProgressBar = get_node_or_null(stamina_bar_path)
@onready var level_label: Label = get_node_or_null(level_label_path)

# --- STATE ---
var player: Node = null
var stats: Node = null

func _ready():
	if Engine.is_editor_hint(): return
	
	# FIND PLAYER
	player = get_tree().get_first_node_in_group("Player")
	if not player:
		print("❌ [GameHUD] Player not found in group 'Player'.")
		return
	
	# FIND STATS
	stats = player.find_child("Stats", true, false) # Verify naming
	if not stats: 
		# Fallback: Maybe on the player root if not child
		if player.has_signal("health_changed"): stats = player
		else: print("⚠️ [GameHUD] Stats component not found on Player.")
	
	# CONNECT SIGNALS
	if stats:
		if stats.has_signal("health_changed"):
			stats.health_changed.connect(_on_health_changed)
			# Sync Initial State
			if "current_health" in stats and "max_health" in stats:
				_on_health_changed(stats.current_health, stats.max_health)
				
		if stats.has_signal("leveled_up"):
			stats.leveled_up.connect(_on_level_up)
			if "level" in stats: _on_level_up(stats.level)
			
	# Initialize Stamina
	if stamina_bar:
		stamina_bar.modulate.a = 0.0 # Start hidden
		
	# Initialize Health Bar Visuals (Juice)
	if health_bar:
		# Ensure it has textures if missing (Fallback for easy testing)
		if not health_bar.texture_progress:
			_create_fallback_textures()

func _process(_delta):
	if Engine.is_editor_hint(): return
	
	if player:
		_process_stamina()

# --- HEALTH LOGIC (With Juice) ---
func _on_health_changed(value: float, max_v: float):
	if not health_bar: return
	
	health_bar.max_value = max_v
	# Tween for smooth slide
	var tw = create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(health_bar, "value", value, 0.4)
	
	# Shake effect if damage taken
	if value < health_bar.value:
		var visual_tw = create_tween()
		visual_tw.tween_property(health_bar, "position:x", health_bar.position.x + 5, 0.05)
		visual_tw.tween_property(health_bar, "position:x", health_bar.position.x - 5, 0.05)
		visual_tw.tween_property(health_bar, "position:x", health_bar.position.x, 0.05)

# --- STAMINA LOGIC (Smart Fade) ---
func _process_stamina():
	if not stamina_bar: return
	
	var cur = 0.0
	var max_s = 100.0
	
	if "current_stamina" in player: cur = player.current_stamina
	if "max_stamina" in player: max_s = player.max_stamina
	
	stamina_bar.max_value = max_s
	stamina_bar.value = cur
	
	# Visibility Logic
	var target_alpha = 1.0
	if cur >= max_s * 0.99: # Full
		target_alpha = 0.0
	
	stamina_bar.modulate.a = lerp(stamina_bar.modulate.a, target_alpha, 0.1)

# --- LEVEL LOGIC ---
func _on_level_up(lvl):
	if level_label:
		level_label.text = "LV. " + str(lvl)
		# Pop animation
		var tw = create_tween()
		tw.tween_property(level_label, "scale", Vector2(1.5, 1.5), 0.2)
		tw.tween_property(level_label, "scale", Vector2(1.0, 1.0), 0.2)

# --- FALLBACK GENERATION (For rapid testing) ---
func _create_fallback_textures():
	# Simple Gradient Textures
	var w = Gradient.new()
	w.colors = [Color.RED, Color(0.8, 0, 0)]
	var tex = GradientTexture2D.new()
	tex.gradient = w
	tex.width = 200; tex.height = 20
	health_bar.texture_progress = tex
	
	var bg = Gradient.new()
	bg.colors = [Color(0.2,0,0), Color(0.2,0,0)]
	var bg_tex = GradientTexture2D.new()
	bg_tex.gradient = bg
	bg_tex.width = 200; bg_tex.height = 20
	health_bar.texture_under = bg_tex
