shader_type spatial;
// Masonry for forts, towers, pillars and ruins: offset rows of stone blocks with
// mortar lines, per-block color, weathering, and moss creeping up from the
// ground. Projected in world space, so it works on any wall or CSG shape.

uniform vec3 stone_a : source_color = vec3(0.47, 0.44, 0.41);
uniform vec3 stone_b : source_color = vec3(0.34, 0.32, 0.31);
uniform vec3 mortar : source_color = vec3(0.2, 0.19, 0.18);
uniform vec3 moss : source_color = vec3(0.22, 0.32, 0.14);
uniform vec2 block_size = vec2(1.1, 0.55);
uniform float moss_height = 1.4;

varying vec3 world_pos;
varying vec3 world_normal;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p;
	if (n.y > 0.7) {
		p = world_pos.xz * 0.8;  // tops: flagstones
	} else if (n.x > n.z) {
		p = world_pos.zy;
	} else {
		p = world_pos.xy;
	}
	vec2 q = p / block_size;
	float row = floor(q.y);
	q.x += mod(row, 2.0) * 0.5 + hash(vec2(row, 3.0)) * 0.3;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float edge = min(min(f.x, 1.0 - f.x) * block_size.x, min(f.y, 1.0 - f.y) * block_size.y);
	float stone_mask = smoothstep(0.015, 0.05, edge + (noise(p * 9.0) - 0.5) * 0.02);
	float id = hash(cell);
	vec3 color = mix(stone_a, stone_b, id);
	color *= 0.82 + 0.3 * noise(p * 3.0) + 0.08 * noise(p * 15.0);
	// Rounded block faces: a little darker toward the mortar.
	color *= mix(0.78, 1.0, smoothstep(0.0, 0.18, edge));
	color = mix(mortar, color, stone_mask);
	// Moss near the ground and on top surfaces.
	float m = smoothstep(moss_height, 0.0, world_pos.y) * 0.7 + smoothstep(0.75, 0.95, world_normal.y) * 0.5;
	m *= smoothstep(0.35, 0.75, noise(p * 1.7));
	color = mix(color, moss * (0.8 + 0.4 * noise(p * 6.0)), clamp(m, 0.0, 0.85));
	ALBEDO = color;
	ROUGHNESS = 0.92;
}
