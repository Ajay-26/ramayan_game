shader_type sky;
// Brooding night sky: heavy storm clouds drifting over a dim moon, the
// horizon underlit orange by distant fires, and lightning that lights the
// cloud banks from inside (`lightning` is set from script).
// Cloud shapes come from one tiling noise texture sampled twice, so the
// shader is cheap. Only the background uses it: ambient light is a flat
// color and sky reflections are off, so no radiance maps are rebuilt.

uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform vec3 zenith_color : source_color = vec3(0.025, 0.03, 0.045);
uniform vec3 horizon_color : source_color = vec3(0.13, 0.12, 0.13);
uniform vec3 ground_color : source_color = vec3(0.02, 0.02, 0.025);
uniform vec3 cloud_dark : source_color = vec3(0.035, 0.04, 0.05);
uniform vec3 cloud_lit : source_color = vec3(0.26, 0.27, 0.31);
uniform vec3 fire_glow : source_color = vec3(0.5, 0.18, 0.05);
uniform vec3 moon_direction = vec3(0.45, 0.42, -0.78);
uniform vec3 moon_color : source_color = vec3(0.78, 0.82, 0.92);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.62;
uniform float cloud_speed = 0.005;
uniform float lightning : hint_range(0.0, 4.0) = 0.0;
uniform vec3 lightning_direction = vec3(0.0, 0.5, -1.0);

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, zenith_color, smoothstep(0.0, 0.55, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));
	col += fire_glow * exp(-abs(h) * 16.0) * 0.7;

	vec3 md = normalize(moon_direction);
	float m = max(dot(d, md), 0.0);
	col += moon_color * (smoothstep(0.9988, 0.9992, m) * 4.0 + pow(m, 90.0) * 0.6 + pow(m, 10.0) * 0.1);

	float n = 0.0;
	float cover = 0.0;
	if (h > -0.05) {
		vec2 uv = d.xz / (max(h, 0.0) + 0.14);
		vec2 wind = vec2(1.0, 0.35) * TIME * cloud_speed;
		float a = texture(clouds, uv * 0.07 + wind).r;
		float b = texture(clouds, uv * 0.19 - wind * 1.8).r;
		n = a * 0.65 + b * 0.35;
		cover = smoothstep(0.85 - cloud_cover, 1.2 - cloud_cover, n) * smoothstep(-0.05, 0.1, h);
	}
	vec3 cloud = mix(cloud_dark, cloud_lit, smoothstep(0.45, 0.95, n));
	cloud += moon_color * pow(m, 5.0) * 0.3 * n;
	cloud += fire_glow * exp(-max(h, 0.0) * 5.0) * 0.4;
	float flash = lightning * (0.2 + 0.8 * pow(max(dot(d, normalize(lightning_direction)), 0.0), 3.0));
	cloud += vec3(0.7, 0.76, 1.0) * flash * (0.3 + n);
	col = mix(col, cloud, cover);
	col += vec3(0.45, 0.5, 0.65) * flash * 0.12;
	COLOR = col;
}
