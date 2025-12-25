extends Node
# class_name MapManager # Removed to avoid Autoload conflict

# === SINGLETON: MapManager ===
# Gère l'état global du brouillard de guerre et des points d'intérêt.

signal map_updated # Emis quand le brouillard ou un point change d'état

# DATA STORAGE
var unlocked_regions: Dictionary = {} # { region_id: bool }
var known_points: Dictionary = {} # { point_id: "LOCKED" | "UNLOCKED" | "HIDDEN" }

# INDEXING (Non sauvegardé, reconstruit au runtime)
var _points_in_region: Dictionary = {} # { region_id: [point_id, point_id...] }

func _ready() -> void:
    # Si besoin de charger des données, le faire ici ou via GameManager
    pass

# === REGISTRATION ===
func register_point(point_id: String, region_id: String) -> void:
    if not region_id in _points_in_region:
        _points_in_region[region_id] = []
    
    if not point_id in _points_in_region[region_id]:
        _points_in_region[region_id].append(point_id)
    
    # Init default state if unknown
    if not point_id in known_points:
        known_points[point_id] = "HIDDEN"

# === LOGIC ===

func unlock_tower(region_id: String) -> void:
    print("🗼 MapManager: Unlocking Tower/Region ", region_id)
    unlocked_regions[region_id] = true
    
    # Révéler les points de cette région
    if region_id in _points_in_region:
        for pid in _points_in_region[region_id]:
            var current_status = known_points.get(pid, "HIDDEN")
            # Si caché, on le révèle (devient Rouge/LOCKED)
            # On ne touche pas s'il est déjà Bleu/UNLOCKED
            if current_status == "HIDDEN":
                known_points[pid] = "LOCKED"
    
    map_updated.emit()

func unlock_teleport_point(point_id: String) -> void:
    print("🔵 MapManager: Unlocking Point ", point_id)
    known_points[point_id] = "UNLOCKED" # Force Blue
    map_updated.emit()

func get_point_status(point_id: String, region_id: String = "") -> String:
    # 1. Check direct status (Saved state)
    var status = known_points.get(point_id, "HIDDEN")
    
    # 2. Logic Override: If Region is unlocked, point should be at least LOCKED (Red), never HIDDEN
    # (Sauf si on veut une logique où des points secrets restent cachés même dans une zone connue ?)
    # Le user a dit: "Retourne RED si non activé MAIS région débloquée"
    
    if status == "UNLOCKED":
        return "BLUE"
        
    if region_id != "":
        if unlocked_regions.get(region_id, false):
            return "RED" # Visible (Inactive)
            
    # Fallback to stored status (likely HIDDEN or LOCKED if set manually)
    if status == "LOCKED": return "RED"
    
    return "HIDDEN"

# === SAVE/LOAD HELPERS ===
func get_save_data() -> Dictionary:
    return {
        "unlocked_regions": unlocked_regions,
        "known_points": known_points
    }

func load_save_data(data: Dictionary) -> void:
    if "unlocked_regions" in data: unlocked_regions = data["unlocked_regions"]
    if "known_points" in data: known_points = data["known_points"]
    map_updated.emit()
