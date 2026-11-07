shader_type sky;
// 0.10.1 – Tag/Nacht-Himmel (BEWUSSTE ABWEICHUNG, Nutzerauftrag). Überblendet drei CC0-Fotohimmel (Poly Haven, siehe
// docs/SKY_SOURCES.md) nach Tageszeit und ergänzt prozedural Sonnenscheibe/-hof, Dämmerungsglühen am Horizont und Sterne.
// Gewichte/Farben setzt src/world/day_night.gd (nur bei Änderung, Radiance inkrementell).
render_mode use_debanding;

uniform sampler2D sky_day : source_color, filter_linear, repeat_enable;
uniform sampler2D sky_eve : source_color, filter_linear, repeat_enable;
uniform sampler2D sky_night : source_color, filter_linear, repeat_enable;
uniform vec3 weights = vec3(1.0, 0.0, 0.0);      // Tag, Dämmerung, Nacht (Summe 1)
uniform vec3 energies = vec3(0.9, 0.45, 0.35);   // Helligkeit je Foto
uniform vec3 rotations = vec3(0.0);              // Drehung je Foto [0..1 Umdrehung]
uniform float exposure = 1.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.45, 0.2, 1.0);
uniform float glow = 0.0;                        // Dämmerungsglühen (Sonnenseite)
uniform float sun_disc = 1.0;
uniform vec4 sun_color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float stars = 0.0;
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 horizon_fog : source_color = vec4(0.6, 0.62, 0.65, 1.0);
uniform float horizon_mix = 0.0;

vec3 pano(sampler2D t, vec3 d, float rot) {
	vec2 st = vec2(atan(d.x, d.z), acos(clamp(d.y, -1.0, 1.0)));
	st /= vec2(6.2831853, 3.1415927);
	st.x = fract(st.x + rot);
	return texture(t, st).rgb;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 c = vec3(0.0);
	if (weights.x > 0.001) c += weights.x * energies.x * pano(sky_day, d, rotations.x);
	if (weights.y > 0.001) c += weights.y * energies.y * pano(sky_eve, d, rotations.y);
	if (weights.z > 0.001) c += weights.z * energies.z * pano(sky_night, d, rotations.z);
	if (LIGHT0_ENABLED) {
		vec3 L = LIGHT0_DIRECTION;
		float cs = dot(d, L);
		// Dämmerungsglühen: Horizontband auf der Sonnenseite
		float hz = exp(-abs(d.y) * 7.0);
		float side = pow(max(dot(normalize(vec3(d.x, 0.0, d.z) + 1e-4), normalize(vec3(L.x, 0.0, L.z) + 1e-4)), 0.0), 3.0);
		c += glow_color.rgb * glow * hz * (0.25 + 0.75 * side);
		if (!AT_CUBEMAP_PASS) {
			float disc = smoothstep(0.99985, 0.99993, cs);
			float halo = pow(max(cs, 0.0), 180.0) * 0.6 + pow(max(cs, 0.0), 18.0) * 0.08;
			c += sun_color.rgb * (disc * 40.0 + halo) * sun_disc * step(-0.03, L.y);
		}
	}
	if (stars > 0.001 && d.y > 0.0 && !AT_CUBEMAP_PASS) {
		vec3 g = floor(d * 420.0);
		float h = hash3(g);
		float s = step(0.9965, h) * (0.4 + 0.6 * hash3(g + 7.0));
		float tw = 0.75 + 0.25 * sin(TIME * (1.5 + 3.0 * h) + h * 60.0);
		c += vec3(0.85, 0.9, 1.0) * s * tw * stars * smoothstep(0.0, 0.25, d.y) * 1.6;
		// Mond
		float mc = dot(d, normalize(moon_dir));
		c += vec3(0.75, 0.8, 0.9) * (smoothstep(0.99955, 0.9997, mc) * 3.0 + pow(max(mc, 0.0), 400.0) * 0.25) * stars;
	}
	// Horizont in Nebelfarbe: vernebelte Ferngeometrie (Kartenrand/Boden hinter dem Nebelende) geht nahtlos in den Himmel über
	float hb = smoothstep(0.14, -0.02, d.y) * horizon_mix;
	COLOR = mix(c * exposure, horizon_fog.rgb, hb);
}
