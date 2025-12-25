extends Node

@export var interact_radius: float = 2.0
@export var interact_strength: float = 1.5

var terrain_node = null

func _ready() -> void:
    # Try to find Terrain
    await get_tree().process_frame
    terrain_node = GameManager.terrain_node
    if not terrain_node:
        terrain_node = get_tree().root.find_child("HTerrain", true, false)
        
    print("🌿 Interactive Grass Manager: Ready.")

func _process(delta: float) -> void:
    if not terrain_node: return
    
    var player = get_tree().get_first_node_in_group("Player")
    if not player: return
    
    # We need to access the Material of the Grass Detail Layer
    # HTerrain -> get_detail_layer(0) -> material?
    # Usually it's in terrain_node.get_detail_layer(index).material_override potentially
    
    # Actually HTerrain uses a specific API. 
    # Let's try to set the global shader parameter if the shader is shared?
    # Or iterate detail layers.
    
    # NOTE: Zylann's HTerrain might use a ShaderMaterial assigned in the inspector.
    # We can try to assume it's set and just update it.
    
    # Accessing material on Detail Layer 0
    # The API might be: `terrain_node.get_detail_layer(0)` which is a MultiMeshInstance3D? Not exactly.
    # It manages them internally.
    
    # Let's try to set it on the terrain_node if it exposes it, or find the child.
    pass
    # WAIT: Writing this pseudo-code revealed I need to know HOW to access the material.
    # I will inspect the HTerrain node structure in 'view_code_item' if possible, or assume standard prop.
    # Usually: simple `set_instance_shader_parameter` on the MultiMeshInstance3D children.
    
    for child in terrain_node.get_children():
        if child is MultiMeshInstance3D:
            # This is likely a chunk or a detail layer
            var mat = child.material_override
            if mat and mat is ShaderMaterial:
                mat.set_shader_parameter("u_player_pos", player.global_position)
                mat.set_shader_parameter("u_interact_radius", interact_radius)
                mat.set_shader_parameter("u_interact_strength", interact_strength)
