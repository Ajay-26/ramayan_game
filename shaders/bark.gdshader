shader_type spatial;
// Painterly bark: vertical fibrous streaks and darker cracks, from the mesh UVs
// (U goes around the trunk, V along it). Works for tree trunks and palisade logs.

uniform vec3 bark_light : source_color = vec3(0.36, 0.27, 0.19);
uniform vec3 bark_dark : source_color = vec3(0.16, 0.11, 0.08);
uniform vec3 moss : source_color = vec3(0.2, 0.3, 0.12);
uniform float streak_scale = 9.0;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_normal;
varying float height;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	height = VERTEX.y;
}

void fragment() {
	vec2 uv = vec2(UV.x * streak_scale, UV.y * streak_scale * 0.25);
	float fibers = noise(vec2(uv.x * 2.0, uv.y * 0.6)) * 0.6 + noise(uv * vec2(5.0, 1.2)) * 0.4;
	float cracks = smoothstep(0.62, 0.8, noise(vec2(uv.x * 3.0, uv.y * 0.35)));
	vec3 color = mix(bark_dark, bark_light, fibers);
	color = mix(color, bark_dark * 0.6, cracks);
	// Moss creeping up the shaded, lower side.
	float m = moss_amount * smoothstep(0.6, 0.0, height) * (0.5 + 0.5 * noise(uv * 1.5));
	color = mix(color, moss, clamp(m, 0.0, 1.0));
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
