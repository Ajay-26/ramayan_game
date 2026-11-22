shader_type spatial;
render_mode cull_disabled;
// Foliage drawn with MultiMesh: per-instance color (lush green variations),
// gentle wind sway that grows with height above the mesh's base.

uniform float sway = 0.08;
uniform float sway_speed = 1.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float color_boost = 1.0;

varying vec3 tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float phase = TIME * sway_speed + world.x * 0.35 + world.z * 0.27;
	VERTEX.x += sin(phase) * sway * h;
	VERTEX.z += cos(phase * 0.8) * sway * 0.6 * h;
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = tint * color_boost;
	ROUGHNESS = roughness_value;
}
