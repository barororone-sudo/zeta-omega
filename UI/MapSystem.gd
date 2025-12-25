extends Control
class_name MapSystem

# === CONFIGURATION ===
@export var map_texture: Texture2D # L'image de fond (Dessinée ou Capture)
@export var player_icon_texture: Texture2D
@export var point_icon_texture: Texture2D # Rond (Teleport)
@export var tower_icon_texture: Texture2D # Carré (Tour)

# PARAMETRES
var zoom_level: float = 1.0
const MIN_ZOOM = 0.5
const MAX_ZOOM = 3.0
var is_fullscreen: bool = false
var drag_velocity: Vector2 = Vector2.ZERO

# REFERENCES
@onready var map_container: Control = $MapContainer
@onready var map_rect: TextureRect = $MapContainer/MapTexture
@onready var icons_container: Control = $MapContainer/Icons
@onready var player_marker: TextureRect = $MapContainer/PlayerMarker

# ETAT
var map_center_offset: Vector2 = Vector2.ZERO # Décalage manuel (Drag)
var world_size: Vector2 = Vector2(2048, 2048) # Taille du monde en mètres
var map_size_px: Vector2 = Vector2(1024, 1024) # Taille de l'image map

func _ready() -> void:
	_generate_default_icons()
	
	# Setup initial
	_setup_ui()
	set_process_input(true)
	
	# Connecter au MapManager pour rafraîchir les icônes quand ça change
	if has_node("/root/MapManager"):
		get_node("/root/MapManager").map_updated.connect(refresh_icons)
	
	# Premier refresh
	call_deferred("refresh_icons")

func _generate_default_icons():
	if not player_icon_texture:
		var g = GradientTexture2D.new()
		g.width = 16; g.height = 16
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(0.5, 0.0)
		g.gradient = Gradient.new()
		g.gradient.set_color(0, Color.WHITE)
		g.gradient.set_color(1, Color(1,1,1,0))
		player_icon_texture = g
		
	if not point_icon_texture:
		var g = GradientTexture2D.new()
		g.width = 12; g.height = 12
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(0.5, 0.0)
		g.gradient = Gradient.new()
		g.gradient.set_color(0, Color.WHITE)
		g.gradient.set_color(1, Color(1,1,1,0))
		point_icon_texture = g
		
	if not tower_icon_texture:
		var g = GradientTexture2D.new()
		g.width = 16; g.height = 16
		g.fill = GradientTexture2D.FILL_SQUARE
		g.gradient = Gradient.new()
		g.gradient.set_color(0, Color.WHITE)
		g.gradient.set_color(1, Color.WHITE)
		tower_icon_texture = g
		
	if not map_texture:
		# Fallback Map Background
		var g = GradientTexture2D.new()
		g.width = 1024; g.height = 1024
		g.fill_from = Vector2(0,0); g.fill_to = Vector2(0,1)
		g.gradient = Gradient.new()
		g.gradient.set_color(0, Color(0.05, 0.05, 0.05))
		g.gradient.set_color(1, Color(0.1, 0.1, 0.1))
		map_texture = g

func _setup_ui() -> void:
	# Créer la structure si elle n'existe pas (pour être robuste)
	if not map_container:
		map_container = Control.new()
		map_container.name = "MapContainer"
		map_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		map_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(map_container)
	
	if not map_rect:
		map_rect = TextureRect.new()
		map_rect.name = "MapTexture"
		map_rect.texture = map_texture
		map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		map_container.add_child(map_rect)
		
	if not icons_container:
		icons_container = Control.new()
		icons_container.name = "Icons"
		map_container.add_child(icons_container)
		
	if not player_marker:
		player_marker = TextureRect.new()
		player_marker.name = "PlayerMarker"
		player_marker.texture = player_icon_texture
		# Centrer l'icone
		player_marker.pivot_offset = Vector2(8, 8) 
		map_container.add_child(player_marker)

func _process(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("Player")
	if not player: return
	
	# 1. POSITIONS MONDE -> CARTE
	# Ratio: 1 mètre monde = X pixels carte
	var ratio_x = map_size_px.x / world_size.x
	var ratio_y = map_size_px.y / world_size.y
    
	# Position du joueur sur la carte (en pixels texture)
	# Attention: World Origin (0,0) est souvent au centre de la map 3D ?
	# Supposons que (0,0,0) monde = Centre de l'image map
	var player_map_pos = (Vector2(player.global_position.x, player.global_position.z) * Vector2(ratio_x, ratio_y)) + (map_size_px / 2.0)
	
	# Mise à jour Marker Joueur
	player_marker.position = player_map_pos - player_marker.pivot_offset
	player_marker.rotation = -player.rotation.y
	
	# 2. GESTION DU VUE (PAN & ZOOM)
	var screen_center = size / 2.0
    
    if is_fullscreen:
        # Mode Drag Libre
        # On affiche la map décalée par 'map_center_offset'
        # Le 'map_center_offset' représente le centre de la vue EN PIXELS CARTE
        
        # Si on ne drag pas, on peut suivre le joueur ou rester fixe ?
        # Zelda: Reste fixe sur la dernière position draguée.
        pass
    else:
        # Mode Minimap: Centré sur le joueur
        # IMPORTANT: CORRECTIF BUG RECENTER
        map_center_offset = player_map_pos
    
    # Calcul de la position du conteneur pour que 'map_center_offset' soit au milieu de l'écran
    # Pos = ScreenCenter - (MapCenter * Zoom)
    var target_pos = screen_center - (map_center_offset * zoom_level)
    
    map_container.position = map_container.position.lerp(target_pos, 20.0 * delta)
    map_container.scale = Vector2(zoom_level, zoom_level)

func _input(event: InputEvent) -> void:
    # TOGGLE MAP (M)
    if event is InputEventKey and event.pressed and event.keycode == KEY_M:
        toggle_map_mode()
        
    if is_fullscreen:
        # DRAG
        if event is InputEventMouseMotion:
            if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
                # On déplace le centre de la map dans le sens opposé de la souris
                map_center_offset -= event.relative / zoom_level
        
        # ZOOM
        if event is InputEventMouseButton:
            if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                zoom_level = clamp(zoom_level + 0.1, MIN_ZOOM, MAX_ZOOM)
            elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                zoom_level = clamp(zoom_level - 0.1, MIN_ZOOM, MAX_ZOOM)
            
            # TELEPORT (Clic Droit)
            if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
                try_teleport_click(event.position)

func toggle_map_mode() -> void:
    is_fullscreen = !is_fullscreen
    
    if is_fullscreen:
        # Setup Fullscreen
        zoom_level = 1.0
        # On garde le dernier offset (centré sur joueur au début)
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    else:
        # Setup Minimap
        zoom_level = 2.0 # Zoom plus fort
        # RESET OFFSET SUR JOUEUR (Correctif demandé)
        # _process va le faire automatiquement car 'else' block
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func refresh_icons() -> void:
    # Nettoyer
    for c in icons_container.get_children():
        c.queue_free()
        
    var mm = get_node_or_null("/root/MapManager")
    if not mm: return
    
    # Parcourir tous les points (Comment les trouver ? Via Groupe ou via MapManager data ?)
    # Le MapManager stocke l'état, mais pas forcément la position s'il est purement Data.
    # On va chercher les Nodes "MapPoint" dans la scène.
    var points = get_tree().get_nodes_in_group("MapPoint") # Assurez vous d'ajouter MapPoint.gd au groupe "MapPoint"
    
    for p in points:
        var status = mm.get_point_status(p.id, p.region_id)
        
        # SPATIAL FALLBACK: If Hidden but geographically revealed -> Show as RED
        if status == "HIDDEN":
            if GameManager.is_zone_revealed(p.global_position):
                status = "RED"
        
        if status == "HIDDEN": continue
        
        # Créer icône
        var icon = TextureRect.new()
        if p.type == MapPoint.Type.TOWER:
            icon.texture = tower_icon_texture
            # Couleur carrée
        else:
            icon.texture = point_icon_texture
            
        # Couleur
        if status == "BLUE":
            icon.modulate = Color(0, 0.8, 1) # Bleu
        else:
            icon.modulate = Color(1, 0, 0) # Rouge
            
        icon.mouse_filter = Control.MOUSE_FILTER_PASS # Pour détecter clic droit
        icon.set_meta("point_id", p.id) # Stocker l'ID pour le teleport
        
        # Positionnement
        var ratio_x = map_size_px.x / world_size.x
        var ratio_y = map_size_px.y / world_size.y
        var p_map_pos = (Vector2(p.global_position.x, p.global_position.z) * Vector2(ratio_x, ratio_y)) + (map_size_px / 2.0)
        
        icon.position = p_map_pos - Vector2(8,8) # Centrer
        
        icons_container.add_child(icon)

func try_teleport_click(mouse_pos: Vector2) -> void:
    # Raycast UI manuel ou check distance
    # On transforme la position souris en position locale IconsContainer
    var local_mouse = icons_container.get_global_transform().inverse() * mouse_pos
    
    # Cherche l'icône la plus proche
    for icon in icons_container.get_children():
        if icon.get_rect().has_point(local_mouse):
            # Clic sur icône
            if icon.modulate == Color(0, 0.8, 1): # Si Bleu
                var pid = icon.get_meta("point_id")
                print("✨ TELEPORT TO POINT: ", pid)
                # TODO: Appeler fonction teleport du Player
                return
