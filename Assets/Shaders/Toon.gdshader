shader_type spatial;
render_mode diffuse_toon, specular_toon; 
// Godot's built-in toon modes help, but we customize lightly

// --- UNIFORMS ---
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;

group_uniforms Toon;
uniform float shadow_size : hint_range(0.0, 1.0) = 0.5;
uniform float shadow_smoothness : hint_range(0.001, 1.0) = 0.10;
uniform vec4 shadow_color : source_color = vec4(0.15, 0.15, 0.25, 1.0);

group_uniforms Rim;
uniform bool rim_enabled = true;
uniform float rim_size : hint_range(0.0, 1.0) = 0.12;
uniform float rim_smoothness : hint_range(0.0, 1.0) = 0.05;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power = 4.0;

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	ALBEDO = albedo.rgb * tex.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}

void light() {
	// 1. DIFFUSE (Cell Shading)
	// N dot L essentially
	float ndotl = dot(NORMAL, LIGHT);
	
	// Step function for sharp shadow edge
	// We map ndotl from -1..1 to 0..1 roughly, or just look for the threshold
	float light_intensity = smoothstep(shadow_size - shadow_smoothness, shadow_size + shadow_smoothness, ndotl);
	
	// Add Shadow color (Ambient usually covers this, but we can force tint)
	vec3 diffuse = mix(ALBEDO * shadow_color.rgb, ALBEDO * LIGHT_COLOR, light_intensity);
	
	// Shadows (Cast by other objects)
	diffuse *= ATTENUATION; // Built-in shadow map influence
	
	// 2. SPECULAR (Gloss)
	vec3 H = normalize(VIEW + LIGHT);
	float NdotH = dot(NORMAL, H);
	float specular_intensity = pow(NdotH, 1.0 / ROUGHNESS);
	// Hard step specular
	specular_intensity = smoothstep(0.5, 0.55, specular_intensity);
	vec3 specular = LIGHT_COLOR * specular_intensity;
	
	// 3. RIM LIGHT
	float rim = 0.0;
	if (rim_enabled) {
		float fresnel = 1.0 - dot(NORMAL, VIEW);
		// Rim appears on lit side or dark side? Typically backlit or edge.
		// Standard: (1 - V.N) * (N.L) to keep it on lit side?
		// Zelda style: Rim is often constant edge.
		rim = pow(fresnel, rim_power);
		rim = smoothstep(1.0 - rim_size - rim_smoothness, 1.0 - rim_size, rim);
		rim *= ndotl; // Mask by light to avoid glowing in dark (unless emissive)
	}
	vec3 rim_final = rim_color.rgb * rim * LIGHT_COLOR;
	
	DIFFUSE_LIGHT += (diffuse + rim_final) * ATTENUATION;
	SPECULAR_LIGHT += specular * ATTENUATION;
}
