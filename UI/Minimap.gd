extends Control

# REFERENCES
@onready var panel = $Panel
# On va supprimer le vieux PlayerDot et créer une flèche dynamique
@onready var old_dot = $Panel/PlayerDot 

# PARAMETRES
var zoom_minimap = 200.0 # Vue de 200m
var zoom_worldmap = 2000.0 # Vue de 2km

# COMPOSANTS DYNAMIQUES
var viewport: SubViewport
var map_camera: Camera3D
var map_texture_rect: TextureRect
var player_arrow: Node2D # Notre flèche

# ETAT
var is_fullscreen = false
var minimap_size = Vector2(200, 200)
var minimap_margin = 20 # Marge depuis le bord

# NAVIGATION CARTE
var map_offset_accum = Vector2.ZERO # Décalage manuel de la caméra
var is_dragging = false
var drag_start_mouse = Vector2.ZERO
var drag_start_offset = Vector2.ZERO

# FOG OF WAR
var fog_overlay: ColorRect
var fog_shader: ShaderMaterial

func _ready() -> void:
	add_to_group("Minimap") # Pour recevoir "refresh_fog"
	
	# 1. SETUP UI INITIAL (Coin Haut Droit)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	var vp_size = get_viewport_rect().size
	position = Vector2(vp_size.x - minimap_size.x - minimap_margin, minimap_margin)
	size = minimap_size
	
	# Gestion dynamique de la taille (resize event si besoin)
	get_tree().root.size_changed.connect(_on_vp_resize)
	
	# IMPORTANT : Intercepter les clics pour le Drag & Drop
	panel.gui_input.connect(_on_panel_gui_input)
	
	# 2. VIEWPORT & CAMERA
	viewport = SubViewport.new()
	viewport.name = "MapViewport"
	viewport.size = Vector2(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_3d = get_viewport().world_3d 
	add_child(viewport)
	
	map_camera = Camera3D.new()
	map_camera.name = "MapCamera"
	map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	map_camera.size = zoom_minimap
	map_camera.position.y = 1000.0
	map_camera.rotation_degrees.x = -90.0
	map_camera.cull_mask = 1 | 2 | 4
	
	# --- FIX VISUEL CARTE (Retirer Brouillard/Ciel) ---
	var map_env = Environment.new()
	map_env.background_mode = Environment.BG_COLOR
	map_env.background_color = Color(0.1, 0.1, 0.1) # Fond gris sombre (si pas de terrain)
	map_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	map_env.ambient_light_color = Color.WHITE # Lumière neutre plate pour bien voir la texture
	map_env.ambient_light_energy = 1.0
	map_env.fog_enabled = false # CRUCIAL: Pas de brouillard !
	map_camera.environment = map_env
	
	viewport.add_child(map_camera)
	
	# 3. TEXTURE DANS LE PANEL
	map_texture_rect = TextureRect.new()
	map_texture_rect.name = "MapRender"
	map_texture_rect.texture = viewport.get_texture()
	map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IMPORTANT: Mouse Filter Ignore pour laisser passer les clics au PANEL
	map_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	
	panel.add_child(map_texture_rect)
	panel.move_child(map_texture_rect, 0)
	
	# --- 3.5 FOG OVERLAY ---
	_setup_fog()
	
	# 3.6 ICONS OVERLAY (Au dessus du Fog)
	_setup_icons_overlay()
	
	# 4. CRÉATION DE LA FLÈCHE (REMPLACE LE DOT)
	if old_dot: old_dot.visible = false # On cache le vieux carré
	if player_arrow: player_arrow.queue_free() # Cleanup
	_create_arrow_icon()
	
	# 5. STYLE INITIAL (ROND)
	_apply_round_style()

# --- HANDLERS D'EVENEMENTS ---

func _on_vp_resize():
	# Si on est en mode Minimap (pas fullscreen), on reste collé au bord droit
	if not is_fullscreen:
		var vp_size = get_viewport_rect().size
		position = Vector2(vp_size.x - minimap_size.x - minimap_margin, minimap_margin)

func _create_arrow_icon():
	player_arrow = Polygon2D.new()
	player_arrow.color = Color(1, 0.2, 0.2) # Rouge vif
	# Triangle pointant vers le HAUT (car -Z est "devant" en 3D, et Haut en 2D Map)
	player_arrow.polygon = PackedVector2Array([
		Vector2(0, -8),  # Pointe
		Vector2(6, 6),   # Bas Droite
		Vector2(0, 4),   # Centre Bas (creux)
		Vector2(-6, 6)   # Bas Gauche
	])
	# Centrer dans le panel
	player_arrow.position = minimap_size / 2.0
	panel.add_child(player_arrow)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_M or event.keycode == KEY_COMMA:
			toggle_map_mode()

func _on_panel_gui_input(event: InputEvent):
	if not is_fullscreen: return # Pas de drag sur la minimap
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				drag_start_mouse = event.global_position
				drag_start_offset = map_offset_accum
			else:
				is_dragging = false
	
	if event is InputEventMouseMotion and is_dragging:
		var delta_mouse = event.global_position - drag_start_mouse
		var ratio = map_camera.size / size.x 
		var world_move = delta_mouse * ratio
		map_offset_accum = drag_start_offset - Vector2(world_move.x, world_move.y)

	# ZOOM (Mouse Wheel) - Uniquement en grand écran ou si survolé
	if event is InputEventMouseButton:
		if is_fullscreen:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_worldmap = clamp(zoom_worldmap - 100, 200, 4000)
				create_tween().tween_property(map_camera, "size", zoom_worldmap, 0.1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_worldmap = clamp(zoom_worldmap + 100, 200, 4000)
				create_tween().tween_property(map_camera, "size", zoom_worldmap, 0.1)

# --- LOOP PRINCIPAL ---

func _process(_delta: float) -> void:
	var player = get_tree().get_first_node_in_group("Player")
	if not player: return
	
	# 1. Mise à jour Caméra
	# EN MODE MINIMAP : Toujours centré sur le joueur (Ignorer l'offset de drag)
	# EN MODE FULLSCREEN : Joueur + Offset
	var target_x = player.global_position.x
	var target_z = player.global_position.z
	
	if is_fullscreen:
		target_x += map_offset_accum.x
		target_z += map_offset_accum.y
		
	map_camera.global_position.x = target_x
	map_camera.global_position.z = target_z
	
	# 2. Update Fog Shader Center
	if fog_shader:
		# Center Pos is Camera Pos (X, Z)
		var center = Vector2(map_camera.global_position.x, map_camera.global_position.z)
		fog_shader.set_shader_parameter("center_pos", center)
		# View Radius = Size / 2
		fog_shader.set_shader_parameter("view_radius", map_camera.size / 2.0)
		
	# 3. Update Icons
	var icons = panel.get_node_or_null("IconsOverlay")
	if icons: icons.queue_redraw()
	
	# 4. Mise à jour Flèche (Rotation)
	# En mode Fullscreen + Déplacement, on garde la flèche au centre RELATIF au joueur
	# MAIS ATTENTION: Si on déplace la map, le joueur n'est plus au centre du Panel
	# Calculez la position du joueur sur la map par rapport au centre de la vue caméra
	
	# Offset Pixel = (Différence Monde) * Ratio (Pixels / Mètres)
	# Ratio = TailleViewport / TailleCaméra
	var ratio = size.x / map_camera.size # ex: 512px / 200m = 2.5 px/m
	
	# Position relative du joueur par rapport au centre de la caméra
	# Note: map_camera est décalé de map_offset_accum par rapport au joueur
	# map_cam.pos = player.pos + offset
	# player.pos - map_cam.pos = -offset
	
	var rel_x = -map_offset_accum.x
	var rel_z = -map_offset_accum.y 
	
	var screen_offset_x = rel_x * ratio
	var screen_offset_y = rel_z * ratio # Le Z 3D devient Y écran positif vers le bas
	
	if player_arrow:
		# Rotation
		var rot = player.rotation.y
		if player.has_node("Visuals"):
			rot = player.get_node("Visuals").rotation.y + player.rotation.y
		player_arrow.rotation = -rot + PI 
		
		# Position (Centre Panel + Décalage inversé du Drag)
		player_arrow.position = (size / 2.0) + Vector2(screen_offset_x, screen_offset_y)

# --- SETUP & HELPERS ---

func _setup_fog():
	fog_overlay = ColorRect.new()
	fog_overlay.name = "FogOverlay"
	fog_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# SHADER
	var sh = Shader.new()
	sh.code = """
	shader_type canvas_item;
	
	uniform vec3 unlocks[20]; // x,y world pos, z radius
	uniform int unlock_count = 0;
	uniform vec2 center_pos = vec2(0,0);
	uniform float view_radius = 100.0; // Half Size in Meters
	
	void fragment() {
		// UV (0..1) -> World Pos
		// Center is center_pos. Width is view_radius * 2
		vec2 rel = (UV - 0.5) * (view_radius * 2.0);
		// Note: Y screen is Z world.
		// If UV.y increases (down), rel.y increases.
		// In World Z increases (South). Matches.
		
		vec2 pixel_world_pos = center_pos + rel;
		
		float alpha = 1.0;
		
		// Check against unlocks
		for(int i = 0; i < unlock_count; i++) {
			float d = distance(pixel_world_pos, unlocks[i].xy);
			// Smooth edge
			float r = unlocks[i].z;
			if (d < r) {
				alpha = 0.0;
			} else if (d < r + 20.0) {
				// Fade out
				alpha = (d - r) / 20.0;
			}
			if (alpha <= 0.001) break;
		}
		
		COLOR = vec4(0.0, 0.0, 0.0, alpha);
	}
	"""
	fog_shader = ShaderMaterial.new()
	fog_shader.shader = sh
	fog_overlay.material = fog_shader
	
	panel.add_child(fog_overlay)
	# On le met juste après la texture de la map
	panel.move_child(fog_overlay, 1)
	
	refresh_fog()

func refresh_fog():
	# Appelé par GameManager
	if not fog_shader: return
	
	var data = GameManager.unlocked_regions
	var count = min(data.size(), 20)
	fog_shader.set_shader_parameter("unlock_count", count)
	
	var arr = []
	for i in range(count):
		var u = data[i]
		arr.append(Vector3(u.position.x, u.position.y, u.radius))
	
	# Pad with zeros if less than 20 (Godot requires matching array size sometimes or handling in shader loop)
	if count < 20:
		for k in range(20 - count):
			arr.append(Vector3.ZERO)
			
	fog_shader.set_shader_parameter("unlocks", arr)

func _setup_icons_overlay():
	# Un simple Control qui va utiliser _draw()
	var icons = Control.new()
	icons.name = "IconsOverlay"
	icons.set_anchors_preset(Control.PRESET_FULL_RECT)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons.draw.connect(_on_icons_draw)
	
	panel.add_child(icons)
	panel.move_child(icons, 2) # Après Fog (0=Tex, 1=Fog, 2=Icons)

func _on_icons_draw():
	if not map_camera: return
	var icons_node = panel.get_node("IconsOverlay")
	if not icons_node: return
	
	var towers = GameManager.all_towers
	var cam_pos = Vector2(map_camera.global_position.x, map_camera.global_position.z)
	var cam_size = map_camera.size # Largeur en mètres vue par la cam (ex: 200m ou 2000m)
	var screen_size = minimap_size # Taille en pixels du panel (ex: 200px)
	if is_fullscreen:
		screen_size = panel.size
		
	var ratio = screen_size.x / cam_size
	
	for t in towers:
		var t_pos = Vector2(t.position.x, t.position.z)
		
		# Position relative à la caméra
		var rel = t_pos - cam_pos
		
		# Projection Écran (X=X, Z=Y)
		# Attention à la rotation -90deg X de la cam : Z monde = Y écran (vers le bas)
		var screen_pos = (screen_size / 2.0) + Vector2(rel.x, rel.y) * ratio
		
		# Clipping simple (ne pas dessiner si trop loin)
		if not panel.get_rect().has_point(panel.global_position + screen_pos):
			# Optionnel: Dessiner une flèche sur le bord ? 
			# Pour l'instant on clip juste.
			pass
			
		# Dessin
		var col = Color(1, 0.5, 0) # Orange (Locked)
		if t.activated: col = Color(0, 0.8, 1) # Bleu (Unlocked)
		
		icons_node.draw_circle(screen_pos, 4.0, col)
		icons_node.draw_circle(screen_pos, 6.0, col * Color(1,1,1,0.3)) # Glow

func toggle_map_mode():
	is_fullscreen = !is_fullscreen
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	
	# Reset offset when closing? Non, on garde la position ou on reset, au choix.
	# Reset pour retrouver le joueur en réouvrant:
	if is_fullscreen: map_offset_accum = Vector2.ZERO 
	
	if is_fullscreen:
		# --- MODE FULLSCREEN (Centre) ---
		var win_size = get_viewport_rect().size
		var margin = 50.0
		var target_size = win_size - Vector2(margin*2, margin*2)
		var target_pos = Vector2(margin, margin)
		
		# Activer curseur souris
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		# On anime NOUS-MÊME (MinimapUI)
		tween.tween_property(self, "position", target_pos, 0.5)
		tween.tween_property(self, "size", target_size, 0.5)
		
		# Camera Zoom
		tween.tween_property(map_camera, "size", zoom_worldmap, 0.5)
		
		# Style Carré
		var style = panel.get_theme_stylebox("panel").duplicate()
		style.set_corner_radius_all(10)
		panel.add_theme_stylebox_override("panel", style)
		
	else:
		# --- MODE MINIMAP (Coin Haut Droit) ---
		var vp_size = get_viewport_rect().size
		var target_pos = Vector2(vp_size.x - minimap_size.x - minimap_margin, minimap_margin)
		
		# Désactiver curseur souris (Retour jeu)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		tween.tween_property(self, "position", target_pos, 0.5)
		tween.tween_property(self, "size", minimap_size, 0.5)
		
		tween.tween_property(map_camera, "size", zoom_minimap, 0.5)
		
		# Style Rond (Cercle parfait)
		_apply_round_style()

func _apply_round_style():
	# FORCE CLIP
	panel.clip_contents = true
	
	# Create BRAND NEW Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.border_color = Color(1, 1, 1, 1)
	style.set_border_width_all(4)
	style.set_corner_radius_all(minimap_size.x / 2.0) # Cercle parfait
	
	panel.add_theme_stylebox_override("panel", style)
