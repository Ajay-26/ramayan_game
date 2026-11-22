shader_type spatial;
// Bare-chested skin for the mannequin's bodysuit surface: skin color plus
// painted-in muscle shading (pecs, abs, obliques, shoulders, spine), worked out
// from the model-space position so it needs no special texture. Soft rounded
// highlights on each muscle and gentle shadows between them, anime style.

uniform vec4 skin_color : source_color = vec4(0.9, 0.75, 0.68, 1.0);
uniform float definition : hint_range(0.0, 2.0) = 1.4;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;

varying vec3 model_pos;
varying vec3 model_normal;

void vertex() {
	model_pos = VERTEX;
	model_normal = NORMAL;
}

// Soft round bump centered at c with radii r (x, y).
float bump(vec2 p, vec2 c, vec2 r) {
	vec2 d = (p - c) / r;
	return exp(-dot(d, d));
}

// Soft valley: 1 on the line, fading out over `width`.
float valley(float d, float width) {
	float t = d / width;
	return exp(-t * t);
}

void fragment() {
	vec2 p = model_pos.xy;
	float ax = abs(p.x);
	float shade = 0.0;

	if (model_normal.z > 0.1) {
		// Pectoral mounds and the shadow underneath them.
		shade += bump(vec2(ax, p.y), vec2(0.075, 1.355), vec2(0.07, 0.055)) * 0.16;
		if (ax < 0.17) {
			float under_pec = p.y - (1.29 + 0.5 * ax * ax);
			shade -= valley(under_pec, 0.022) * 0.28 * smoothstep(1.19, 1.25, p.y);
		}
		// Valley between the pecs.
		shade -= valley(p.x, 0.016) * 0.2 * smoothstep(1.22, 1.27, p.y) * smoothstep(1.46, 1.41, p.y);
		// Six-pack blocks: rounded highlights with soft gaps between them.
		float abs_zone = smoothstep(0.96, 1.01, p.y) * smoothstep(1.3, 1.25, p.y);
		for (int i = 0; i < 3; i++) {
			float row = 1.095 + float(i) * 0.062;
			shade += bump(vec2(ax, p.y), vec2(0.036, row), vec2(0.026, 0.022)) * 0.12;
		}
		shade -= valley(p.x, 0.012) * 0.22 * abs_zone;
		// Edges of the abs into the obliques.
		shade -= valley(ax - (0.095 + (1.28 - p.y) * 0.07), 0.02) * 0.2 * abs_zone;
		// Shoulders.
		shade += bump(vec2(ax, p.y), vec2(0.17, 1.43), vec2(0.05, 0.05)) * 0.1;
	} else if (model_normal.z < -0.1) {
		// Spine groove and the bulk of the back muscles.
		shade -= valley(p.x, 0.018) * 0.22 * smoothstep(0.96, 1.01, p.y) * smoothstep(1.48, 1.43, p.y);
		shade += bump(vec2(ax, p.y), vec2(0.09, 1.33), vec2(0.07, 0.09)) * 0.12;
	}

	ALBEDO = skin_color.rgb * (1.0 + shade * definition);
	ROUGHNESS = roughness_value;
}
