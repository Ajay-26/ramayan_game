shader_type canvas_item;
// Full-screen cinematic grade over the 3D view, for a grim mid-2000s action
// game look: crushed blacks, punchy contrast, desaturated midtones, cold
// slate-teal shadows and warm bronze highlights, then a heavy vignette and a
// touch of film grain. Also pulses red at the edges when Rama is hurt.
// One screen read per frame, so it stays cheap enough for the web build.

uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;

uniform float saturation : hint_range(0.0, 2.0) = 0.7;
uniform float contrast : hint_range(0.5, 2.0) = 1.15;
uniform float contrast_pivot : hint_range(0.0, 1.0) = 0.4;
uniform float black_crush : hint_range(0.0, 0.2) = 0.015;
uniform float exposure : hint_range(0.5, 2.0) = 1.15;
// Color multipliers for the darkest and brightest parts of the image.
uniform vec3 shadow_tint = vec3(0.84, 0.97, 1.12);
uniform vec3 highlight_tint = vec3(1.14, 0.98, 0.78);
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.32;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.018;
// Pulses red when Rama is hurt (set from script).
uniform float hurt_amount : hint_range(0.0, 1.0) = 0.0;
// Brief white-blue wash for lightning (set from script).
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb * exposure;

	float l = dot(c, LUMA);
	c = mix(vec3(l), c, saturation);
	c = (c - contrast_pivot) * contrast + contrast_pivot;
	c = max(c - black_crush, vec3(0.0)) / (1.0 - black_crush);
	float t = smoothstep(0.08, 0.75, clamp(dot(c, LUMA), 0.0, 1.0));
	c *= mix(shadow_tint, highlight_tint, t);

	c += vec3(0.75, 0.82, 1.0) * flash_amount * (0.35 + 0.65 * t);

	vec2 centered = SCREEN_UV - 0.5;
	float dist = length(centered * vec2(1.0, 0.82));
	float vignette = smoothstep(vignette_start, 0.82, dist) * vignette_strength;
	c *= 1.0 - vignette;
	c = mix(c, vec3(0.5, 0.0, 0.0), hurt_amount * smoothstep(0.2, 0.8, dist) * 0.6);

	float n = hash(floor(FRAGCOORD.xy) + fract(TIME * 13.0) * 100.0) - 0.5;
	c += n * grain_amount;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
