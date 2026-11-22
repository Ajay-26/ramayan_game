shader_type canvas_item;
// Full-screen overlay: dark violet vignette plus subtle film grain, for grit.
// Draws on top of the 3D view without reading the screen, so it's cheap on web.

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.42;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.35;
uniform vec3 vignette_color : source_color = vec3(0.02, 0.0, 0.04);
uniform float grain_amount : hint_range(0.0, 0.3) = 0.01;
// Pulses red when Rama is hurt (set from script).
uniform float hurt_amount : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered = UV - 0.5;
	float dist = length(centered * vec2(1.0, 0.8));
	float vignette = smoothstep(vignette_start, 0.85, dist) * vignette_strength;
	vec3 color = mix(vignette_color, vec3(0.5, 0.0, 0.0), hurt_amount);
	float alpha = clamp(vignette + hurt_amount * smoothstep(0.2, 0.8, dist) * 0.6, 0.0, 1.0);

	float n = hash(floor(FRAGCOORD.xy) + fract(TIME * 13.0) * 100.0) - 0.5;
	float g = n * grain_amount;
	COLOR = vec4(color + vec3(g > 0.0 ? 1.0 : 0.0), alpha + abs(g));
}
