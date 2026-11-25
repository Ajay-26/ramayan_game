shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// A low ceiling of churning storm cloud over the boss arena, seen from below.
// Fades out toward its edges so it blends into the sky. `density` fades the
// whole deck in and out; `lightning` lights it from inside (set from script).

uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform float density : hint_range(0.0, 1.0) = 0.0;
uniform float lightning : hint_range(0.0, 2.0) = 0.0;
uniform vec3 cloud_dark : source_color = vec3(0.03, 0.03, 0.04);
uniform vec3 cloud_lit : source_color = vec3(0.17, 0.16, 0.19);
uniform vec3 fire_glow : source_color = vec3(0.35, 0.12, 0.04);
uniform float speed = 0.012;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * 0.012;
	float t = TIME * speed;
	float a = texture(clouds, uv + vec2(t, t * 0.3)).r;
	float b = texture(clouds, uv * 2.1 + vec2(-t * 1.7, t * 0.8)).r;
	float swirl = texture(clouds, uv * 0.5 + vec2(b, a) * 0.15 + t * 0.2).r;
	float n = a * 0.45 + b * 0.25 + swirl * 0.3;
	float edge = 1.0 - smoothstep(0.25, 0.5, length(UV - 0.5));
	vec3 col = mix(cloud_dark, cloud_lit, smoothstep(0.4, 0.85, n));
	col += fire_glow * (1.0 - n) * 0.6;
	col += vec3(0.65, 0.72, 1.0) * lightning * (0.3 + n);
	ALBEDO = col;
	ALPHA = clamp(smoothstep(0.3, 0.7, n) * density * edge * 1.2, 0.0, 0.96);
}
