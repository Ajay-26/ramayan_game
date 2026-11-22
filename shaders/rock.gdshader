shader_type spatial;
// Painterly rock for boulders, cliffs and ledges: layered noise, faint strata,
// darker cracks, and moss on upward-facing surfaces. World-space, triplanar-ish.

uniform vec3 rock_light : source_color = vec3(0.44, 0.42, 0.4);
uniform vec3 rock_dark : source_color = vec3(0.22, 0.21, 0.21);
uniform vec3 moss : source_color = vec3(0.13, 0.22, 0.08);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.45;
uniform float scale = 0.7;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i), n100 = hash(i + vec3(1, 0, 0));
	float n010 = hash(i + vec3(0, 1, 0)), n110 = hash(i + vec3(1, 1, 0));
	float n001 = hash(i + vec3(0, 0, 1)), n101 = hash(i + vec3(1, 0, 1));
	float n011 = hash(i + vec3(0, 1, 1)), n111 = hash(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise(p) * 0.55 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.15;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = world_pos * scale;
	float base = fbm(p);
	float strata = 0.5 + 0.5 * sin(world_pos.y * 2.6 + base * 3.0);
	vec3 color = mix(rock_dark, rock_light, base * 0.8 + strata * 0.25);
	float cracks = smoothstep(0.72, 0.85, noise(p * vec3(1.5, 4.0, 1.5)));
	color = mix(color, rock_dark * 0.55, cracks * 0.7);
	float m = smoothstep(0.35, 0.85, world_normal.y + (noise(p * 2.5) - 0.5) * 0.6) * moss_amount;
	color = mix(color, moss * (0.75 + 0.5 * noise(p * 6.0)), clamp(m, 0.0, 1.0));
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
