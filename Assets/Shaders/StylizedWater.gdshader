shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

// --- UNIFORMS ---
group_uniforms Coloring;
uniform vec3 albedo : source_color = vec3(0.0, 0.3, 0.8);
uniform vec3 albedo_deep : source_color = vec3(0.0, 0.1, 0.4);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

group_uniforms Depth_Fog;
uniform float beer_factor = 2.0; // Profondeur optique
uniform float foam_distance = 0.5; // Distance de l'écume
uniform float foam_max_distance = 1.0;
uniform float foam_min_distance = 0.04;
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

group_uniforms Waves;
uniform sampler2D texture_normal;
uniform sampler2D texture_normal2;
uniform vec2 wave_direction = vec2(0.5, -0.2);
uniform vec2 wave_direction2 = vec2(-0.2, 0.5);
uniform float time_scale : hint_range(0.0, 0.2) = 0.025;
uniform float wave_amplitude = 0.1;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void vertex() {
	// Simple vertex wave (Swell)
	float time = TIME * 0.5;
	float wave = cos(VERTEX.x * 0.2 + time) * sin(VERTEX.z * 0.2 + time);
	VERTEX.y += wave * wave_amplitude;
}

void fragment() {
	// 1. DEPTH CALCULATION (Logarithmic buffer)
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	float object_depth = -VERTEX.z; // In View Space
	
	float depth_blend = clamp((linear_depth - object_depth) / beer_factor, 0.0, 1.0);
	depth_blend = exp(-depth_blend * 3.0); // Beer's law curve
	
	// 2. COLOR BLEND (Shallow vs Deep)
	vec3 color = mix(albedo_deep, albedo, depth_blend);
	
	// 3. FOAM CALCULATION
	float z_depth = linear_depth - object_depth;
	float foam = clamp(1.0 - (z_depth / foam_distance), 0.0, 1.0);
	// Sharpen foam
	foam = smoothstep(0.4, 1.0, foam);
	
	// 4. NORMALS & WAVES
	vec2 time = TIME * wave_direction * time_scale;
	vec2 time2 = TIME * wave_direction2 * time_scale;
	vec3 normal_blend = mix(texture(texture_normal, UV + time).rgb, texture(texture_normal2, UV + time2).rgb, 0.5);
	
	ALBEDO = mix(color, foam_color.rgb, foam);
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	NORMAL_MAP = normal_blend;
	
	// Optional: Refraction near foam?
	ALPHA = clamp(1.0 - depth_blend * 0.5 + foam, 0.6, 1.0); // Semi-transparent in shallow
}
