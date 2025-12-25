shader_type spatial;
render_mode cull_disabled, vertex_lighting;

// CONFIG
uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_detailmap;
uniform sampler2D u_terrain_normalmap;
uniform sampler2D u_terrain_globalmap : hint_default_black;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

// APPEARANCE
uniform sampler2D u_albedo_alpha : source_color;
uniform float u_view_distance = 100.0;
uniform float u_globalmap_tint_bottom : hint_range(0.0, 1.0) = 1.0;
uniform float u_globalmap_tint_top : hint_range(0.0, 1.0) = 1.0;
uniform float u_bottom_ao : hint_range(0.0, 1.0) = 0.5;
uniform vec4 u_color_bottom : source_color = vec4(0.2, 0.4, 0.1, 1.0); // Sombre
uniform vec4 u_color_top : source_color = vec4(0.5, 0.7, 0.2, 1.0); // Clair
uniform float u_roughness = 0.7;

// WIND & INTERACTION
uniform vec3 u_player_pos = vec3(0.0);
uniform float u_interact_radius = 1.5;
uniform float u_interact_strength = 2.0;

uniform float u_time_scale = 1.0;
uniform float u_wind_strength = 0.5;
uniform sampler2D u_wind_noise; // OpenSimplexNoise texture

varying vec3 v_normal;
varying vec2 v_uv;
varying float v_distance;

void vertex() {
	// 1. BILLBOARD / SWAY
	// Simple sway based on UV.y (top vertices move, bottom fixed)
	float sway_mask = UV.y; // 0 top, 1 bottom? Usually reversed for grass mesh.
	// Let's assume standard Quad mesh: y=0 is bottom, y=1 is top.
	sway_mask = 1.0 - UV.y; 
	// Or check standard Godot billboard mesh
	
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// WIND
	float time = TIME * u_time_scale;
	vec2 wind_uv = world_pos.xz * 0.1 + time * 0.1;
	// Cheap wind
	float wind_noise = sin(world_pos.x + time) * cos(world_pos.z + time * 0.5);
	
	// DISPLACEMENT
	vec3 disp = vec3(wind_noise * u_wind_strength * sway_mask, 0.0, 0.0);
	
	// INTERACTION
	float dist = distance(world_pos, u_player_pos);
	if (dist < u_interact_radius) {
		vec3 push_dir = normalize(world_pos - u_player_pos);
		float push_factor = (1.0 - dist / u_interact_radius);
		// Flatten down
		disp.y -= push_factor * u_interact_strength * 0.5 * sway_mask;
		// Push out
		disp.xz += push_dir.xz * push_factor * u_interact_strength * sway_mask;
	}
	
	VERTEX += disp;
	
	v_normal = NORMAL;
	v_uv = UV;
	
	// Distance Fade
	v_distance = distance(CAMERA_POSITION_WORLD, world_pos);
}

void fragment() {
	vec4 col = texture(u_albedo_alpha, v_uv);
	if (col.a < 0.5) discard;
	
	// Gradient Color
	vec3 gradient = mix(u_color_bottom.rgb, u_color_top.rgb, 1.0 - v_uv.y);
	ALBEDO = col.rgb * gradient;
	ROUGHNESS = u_roughness;
	NORMAL = v_normal;
	
	// Distance Fade (Alpha Dither)
	// float fade = 1.0 - smoothstep(u_view_distance * 0.8, u_view_distance, v_distance);
	// ALPHA = fade; // Standard fade
}
