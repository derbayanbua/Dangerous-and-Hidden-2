shader_type sky;
// B-013 (BEWUSSTE ABWEICHUNG, Vorgabe Auftraggeber): Himmel mit prozeduralen, bewegten Wolken.
// Farben/Sonne übernimmt SkyFx aus dem ProceduralSkyMaterial der Mission (Original-Stimmung/Tageszeit bleibt).
// Wolken = projizierte Wolkenschicht mit FBM-Rauschen und Lichtabtastung zur Sonne hin (dicke, dunkle Unterseiten,
// helle Ränder). octaves/light_steps je Grafikstufe; im Radiance-Pass vereinfacht (schnell).

uniform vec3 sky_top : source_color = vec3(0.32, 0.42, 0.58);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.66, 0.52);
uniform vec3 ground_horizon : source_color = vec3(0.5, 0.45, 0.38);
uniform vec3 ground_bottom : source_color = vec3(0.18, 0.17, 0.15);
uniform float sky_curve = 0.15;
uniform float ground_curve = 0.02;
uniform float sky_energy = 1.0;
uniform float sun_angle_max = 20.0;
uniform float sun_curve = 0.15;

uniform float coverage : hint_range(0.0, 1.0) = 0.45;
uniform float density : hint_range(0.0, 2.0) = 1.0;
uniform float cloud_scale = 0.9;
uniform vec2 wind = vec2(0.006, 0.002);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_dark : source_color = vec3(0.45, 0.48, 0.55);
uniform int octaves = 5;
uniform int light_steps = 2;
uniform float night = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int n) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 8; i++) {
		if (i >= n) {
			break;
		}
		v += a * vnoise(p);
		p = rot * p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float cloud_density(vec2 uv, int n) {
	float base = fbm(uv, n);
	return clamp((base - (1.0 - coverage) * 0.75) * 2.6 * density, 0.0, 1.0);
}

vec3 base_sky(vec3 dir) {
	float y = dir.y;
	vec3 c;
	if (y >= 0.0) {
		float t = clamp(1.0 - pow(1.0 - y, 1.0 / max(sky_curve * 6.0, 0.05)), 0.0, 1.0);
		c = mix(sky_horizon, sky_top, t);
	} else {
		float t = clamp(1.0 - pow(1.0 + y, 1.0 / max(ground_curve * 6.0, 0.02)), 0.0, 1.0);
		c = mix(ground_horizon, ground_bottom, t);
	}
	return c * sky_energy;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col = base_sky(dir);
	vec3 sun_dir = LIGHT0_DIRECTION;
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	float sun_dot = LIGHT0_ENABLED ? dot(dir, sun_dir) : -1.0;
	// Sonnen-/Mondscheibe und Hof wie ProceduralSkyMaterial
	if (LIGHT0_ENABLED) {
		float ang = acos(clamp(sun_dot, -1.0, 1.0));
		float disk = LIGHT0_SIZE * 0.5;
		if (ang < disk) {
			col = mix(col, sun_col, 0.9);
		} else {
			float halo = clamp(1.0 - (ang - disk) / radians(sun_angle_max), 0.0, 1.0);
			col += sun_col * pow(halo, 1.0 / max(sun_curve, 0.01)) * 0.25 * (1.0 - night);
		}
	}
	if (dir.y > 0.0) {
		// Wolkenschicht: Projektion auf eine Ebene, nahe dem Horizont gestaucht (Perspektive)
		vec2 uv = dir.xz / (dir.y + 0.12) * cloud_scale + wind * TIME;
		int n = AT_CUBEMAP_PASS ? max(octaves - 2, 2) : octaves;
		float d = cloud_density(uv, n);
		if (d > 0.001) {
			// Lichtabtastung in Sonnenrichtung: dichte Wolken werden zur Sonne hin dunkler (Selbstschatten)
			float shade = 0.0;
			vec2 step_uv = sun_dir.xz * 0.06;
			int ls = AT_CUBEMAP_PASS ? 1 : light_steps;
			for (int i = 1; i <= 4; i++) {
				if (i > ls) {
					break;
				}
				shade += cloud_density(uv + step_uv * float(i), max(n - 1, 2));
			}
			shade /= float(max(ls, 1));
			float sun_up = clamp(sun_dir.y * 4.0 + 0.3, 0.0, 1.0) * (1.0 - night);
			vec3 lit = mix(cloud_dark, cloud_light * (0.6 + 0.6 * sun_col), exp(-shade * 1.8) * (0.35 + 0.65 * sun_up));
			// Silberrand im Gegenlicht
			lit += sun_col * pow(max(sun_dot, 0.0), 8.0) * (1.0 - d) * 0.6 * sun_up;
			// Abendrot/Dämmerung: Wolken nehmen die Horizontfarbe an
			lit = mix(lit, lit * sky_horizon * 1.6, clamp(1.0 - sun_dir.y * 3.0, 0.0, 1.0) * 0.45);
			lit *= mix(1.0, 0.18, night);
			float fade = smoothstep(0.0, 0.18, dir.y);   // zum Horizont ausblenden (Nebel/Ferne)
			col = mix(col, lit * sky_energy, d * fade);
		}
	}
	COLOR = col;
}
