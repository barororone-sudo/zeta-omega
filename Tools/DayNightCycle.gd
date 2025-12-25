extends Node3D

@export var day_length: float = 300.0 # 5 Minutes (Slower/Better Pacing)
@export var start_time: float = 0.3 # 0.0 = Midnight, 0.5 = Noon
@export var sun_color: Gradient
@export var sky_top_color: Gradient
@export var sky_horizon_color: Gradient

var sky_mat: ProceduralSkyMaterial
var time_rate: float
var current_time: float = 0.0

var sun: DirectionalLight3D
var env: WorldEnvironment

func _ready():
	time_rate = 1.0 / day_length
	current_time = start_time
	
	sun = get_node_or_null("Sun")
	if not sun: sun = get_tree().root.find_child("Sun", true, false)
	
	env = get_node_or_null("WorldEnvironment")
	if not env: env = get_tree().root.find_child("WorldEnvironment", true, false)
	
	# Create defaults if missing
	if not sun:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		sun.shadow_enabled = true
		add_child(sun)
		
	if not env:
		env = WorldEnvironment.new()
		env.name = "WorldEnvironment"
		add_child(env)
		var e = Environment.new()
		e.background_mode = Environment.BG_SKY
		var sky = Sky.new()
		sky_mat = ProceduralSkyMaterial.new()
		sky.sky_material = sky_mat
		e.sky = sky
		env.environment = e
	else:
		if env.environment and env.environment.sky and env.environment.sky.sky_material is ProceduralSkyMaterial:
			sky_mat = env.environment.sky.sky_material

func _process(delta):
	current_time += time_rate * delta
	if current_time > 1.0: current_time -= 1.0
	
	# Rotate Sun (0 to 360 degrees)
	var angle = (current_time * 360.0) - 90.0
	sun.rotation_degrees.x = angle
	sun.rotation_degrees.y = 30.0 # Tilt
	
	# Night Lighting (Moon effect)
	if current_time > 0.25 and current_time < 0.75:
		if not sun.visible: sun.visible = true
		sun.light_energy = smoothstep(0.2, 0.3, current_time) * smoothstep(0.8, 0.7, current_time)
		sun.light_color = Color(1.0, 0.9, 0.8) # Warm Day
	else:
		sun.visible = true # Keep sun for moon-light effect
		sun.light_energy = 0.8 # Genshin Night (Bright)
		sun.light_color = Color(0.6, 0.7, 1.0) # Soft Blue Moon
		if env and env.environment:
			env.environment.ambient_light_energy = 1.0 # Very bright ambient for gameplay visibility
		
	# Update Sky Colors
	if sky_mat:
		var sky_col = Color("0077ff")
		var hor_col = Color("aaccff")
		
		if current_time < 0.25 or current_time > 0.75: # Night
			sky_col = Color("001133") # Lighter Navy Blue instead of Black
			hor_col = Color("002244") # Visible Horizon
		elif current_time < 0.35: # Sunrise
			var t = (current_time - 0.25) / 0.1
			sky_col = Color("000022").lerp(Color("0077ff"), t)
			hor_col = Color("111133").lerp(Color("ff8844"), t)
		elif current_time > 0.65: # Sunset
			var t = (current_time - 0.65) / 0.1
			sky_col = Color("0077ff").lerp(Color("000022"), t)
			hor_col = Color("ff8844").lerp(Color("111133"), t)
			
		sky_mat.sky_top_color = sky_col
		sky_mat.sky_horizon_color = hor_col
		sky_mat.ground_horizon_color = hor_col
