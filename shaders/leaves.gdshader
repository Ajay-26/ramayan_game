shader_type spatial;
render_mode cull_disabled;
// Painterly foliage cards (leaf clusters, pine branches, grass tufts).
// - Painted alpha texture, cut out with alpha scissor.
// - Normals were baked to point away from each cluster's center, so whole
//   clusters shade like soft round masses instead of flat cards.
// - Vertex color carries ambient occlusion (darker inside the canopy).
// - Each tree gets its own hue nudge from its world position.
// - Gentle wind sway that grows toward the top of the mesh.

uniform sampler2D leaf_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 color_a : source_color = vec3(0.16, 0.34, 0.12);
uniform vec3 color_b : source_color = vec3(0.3, 0.42, 0.14);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform float sway = 0.04;
uniform float sway_speed = 1.1;
uniform float sway_height = 10.0;

varying vec3 tint;
varying float ao;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float phase = TIME * sway_speed + origin.x * 0.31 + origin.z * 0.23 + VERTEX.y * 0.15;
	VERTEX.x += sin(phase) * sway * h * sway_height * 0.1;
	VERTEX.z += cos(phase * 0.83) * sway * 0.6 * h * sway_height * 0.1;
	tint = mix(color_a, color_b, hash(origin.xz));
	ao = COLOR.r;
}

void fragment() {
	vec4 tex = texture(leaf_texture, UV);
	ALBEDO = tex.rgb * tint * (0.45 + 0.75 * ao);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
