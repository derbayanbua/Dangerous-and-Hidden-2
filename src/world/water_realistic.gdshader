shader_type spatial;
// Wasseroptik (BEWUSSTE ABWEICHUNG vom Original; 0.10.1 Normandie 3, seit 0.10.8 alle Originalkarten je Klimazone,
// Parameter in src/world/water_fx.gd). Eigene Umsetzung; Aufbau (Gerstner-Wellensumme, Beer-Lambert-Tiefenfarbe,
// Kamm- und Uferschaum) angelehnt an „Water shader 3D (Godot 4.3)“ von Lesus, godotshaders.com, CC0 – siehe
// THIRD_PARTY_LICENSES.txt. Kosten: ein transparenter Pass, keine Texturen, kein Bildschirm-Puffer.
// Qualität: wave_count (2…6 Wellen), ripple (feine Kräuselung), foam_amount (0 = aus).
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.16, 0.30, 0.27, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.07, 0.08, 1.0);
uniform vec4 foam_color : source_color = vec4(0.86, 0.90, 0.90, 1.0);
uniform float clarity = 1.6;          // m bis zur vollen Tiefenfarbe (Beer-Lambert-Länge)
uniform float turbidity = 0.0;        // 0 klar … 1 trüb (Fluss): Mindestdeckkraft, weniger Durchsicht
uniform float shore_fade = 0.35;      // m weicher Uferrand
uniform float wave_height = 0.04;     // m (Vertexversatz)
uniform float wave_scale = 1.0;       // Wellenlängen-Faktor
uniform float wave_speed = 1.0;
uniform int wave_count = 6;           // 2…6 (Grafikstufe)
uniform float ripple = 0.35;          // Anteil der feinen Kräuselung (0 = aus)
uniform float normal_strength = 0.55;
uniform float roughness_base = 0.04;
uniform float foam_amount = 0.0;      // Kammschaum (Meer mit Gischt)
uniform float edge_foam = 0.0;        // Uferschaum-Stärke
uniform float edge_foam_width = 0.6;  // m
uniform vec2 flow = vec2(0.25, 0.08); // m/s Strömung
// Ausblenden zur Fernebene: hinter dem Nebelende sonst flache Nebelplatte vor dem (weniger vernebelten) Himmel
uniform float far_fade_begin = 5000.0;
uniform float far_fade_end = 6000.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;

// Richtung (xz), Wellenlänge [m], Amplitude (relativ), Geschwindigkeitsfaktor
const vec4 W[6] = vec4[6](
	vec4(0.96, 0.28, 7.3, 1.00),
	vec4(-0.55, 0.83, 4.1, 0.70),
	vec4(0.31, -0.95, 2.3, 0.45),
	vec4(-0.89, -0.45, 1.27, 0.28),
	vec4(0.70, 0.71, 0.73, 0.17),
	vec4(-0.20, 0.98, 0.41, 0.10)
);

vec3 waves(vec2 p, float t, int n) {
	// x = Höhe, yz = Ableitung nach x/z
	vec3 r = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		if (i >= n) {
			break;
		}
		vec2 d = normalize(W[i].xy);
		float lambda = W[i].z * wave_scale;
		float k = 6.2831853 / lambda;
		float c = sqrt(9.81 / k) * wave_speed;      // Tiefwasser-Dispersion
		float ph = k * (dot(d, p) - c * t);
		float a = W[i].w / k * 0.6;                  // Steilheit begrenzt
		r.x += a * sin(ph);
		r.yz += a * k * cos(ph) * d;
	}
	return r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wpos.xz - flow * TIME;
	float h = waves(p, TIME, wave_count).x;
	VERTEX.y += h * wave_height * 4.0;
}

void fragment() {
	vec2 p = wpos.xz - flow * TIME;
	vec3 w = waves(p, TIME, wave_count);
	vec3 w2 = ripple > 0.0 ? waves(p * 2.7 + vec2(13.1, 7.7), TIME * 1.6, max(wave_count - 2, 2)) : vec3(0.0);
	vec2 slope = (w.yz + ripple * w2.yz) * normal_strength;
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Wassertiefe entlang des Blickstrahls aus dem Tiefenpuffer
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float behind = max(-vpos.z - (-VERTEX.z), 0.0);
	float depth_k = 1.0 - exp(-behind / max(clarity, 0.05));      // Beer-Lambert
	depth_k = mix(depth_k, 1.0, turbidity * 0.6);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	fres = 0.02 + 0.98 * fres;
	vec3 body = mix(shallow_color.rgb, deep_color.rgb, depth_k);

	// Schaum: Wellenkämme (Höhe + Steilheit) und Uferlinie, aufgebrochen durch Rauschen
	float foam = 0.0;
	if (foam_amount > 0.0 || edge_foam > 0.0) {
		float nz = vnoise(p * 1.7 + TIME * 0.3) * 0.6 + vnoise(p * 4.3 - TIME * 0.5) * 0.4;
		float crest = smoothstep(0.25, 0.8, length(w.yz)) * step(0.0, w.x);
		foam = foam_amount * crest * smoothstep(0.35, 0.75, nz);
		float edge = 1.0 - clamp(behind / max(edge_foam_width, 0.01), 0.0, 1.0);
		foam = max(foam, edge_foam * edge * smoothstep(0.25, 0.6, nz + edge * 0.4));
		foam = clamp(foam, 0.0, 1.0);
	}
	ALBEDO = mix(body * (1.0 - fres), foam_color.rgb, foam);
	ROUGHNESS = mix(roughness_base + 0.08 * length(w2.yz), 0.8, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// Deckkraft: flach/senkrecht durchsichtig, tief/flacher Blickwinkel deckend; Uferrand weich
	float a = mix(0.45 + 0.4 * turbidity, 0.94, depth_k);
	a = max(a, fres);
	a = max(a, foam);
	a *= clamp(behind / shore_fade, 0.0, 1.0);
	a *= 1.0 - smoothstep(far_fade_begin, far_fade_end, -VERTEX.z);
	ALPHA = clamp(a, 0.0, 1.0);
}
