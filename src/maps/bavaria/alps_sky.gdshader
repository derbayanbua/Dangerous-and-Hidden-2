shader_type sky;
uniform sampler2D panorama : source_color, filter_linear;
uniform vec3 south_direction = vec3(0.817,0.0,0.576);
uniform float panorama_repeats = 3.0;
// Tageszyklus (day_night.gd): daylight 0 = Dämmerung … 1 = voller Tag, night 0 … 1 = tiefe Nacht,
// sun_direction = Richtung zur Sonne (Abend-/Morgenrot auf ihrer Seite). Beide 0 = bisherige Abenddämmerung.
uniform float daylight = 0.0;
uniform float night = 0.0;
uniform vec3 sun_direction = vec3(-0.576,-0.035,0.817);

float cloud_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	float a = fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
	float b = fract(sin(dot(cell+vec2(1,0),vec2(127.1,311.7)))*43758.5453);
	float c = fract(sin(dot(cell+vec2(0,1),vec2(127.1,311.7)))*43758.5453);
	float d = fract(sin(dot(cell+vec2(1,1),vec2(127.1,311.7)))*43758.5453);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}

float skyline(float u) {
	// Grobe Kontur in Texturkoordinaten; die Textur liefert die eigentlichen Fels-/Schneedetails.
	if (u<0.1) return mix(0.48,0.55,u/0.1);
	if (u<0.2) return mix(0.55,0.53,(u-0.1)/0.1);
	if (u<0.3) return mix(0.53,0.51,(u-0.2)/0.1);
	if (u<0.4) return mix(0.51,0.54,(u-0.3)/0.1);
	if (u<0.5) return mix(0.54,0.59,(u-0.4)/0.1);
	if (u<0.6) return mix(0.59,0.61,(u-0.5)/0.1);
	if (u<0.7) return mix(0.61,0.53,(u-0.6)/0.1);
	if (u<0.8) return mix(0.53,0.55,(u-0.7)/0.1);
	return mix(0.55,0.68,(u-0.8)/0.2);
}

vec4 mountain_band(float u, float elevation, vec3 horizon) {
	float v = 0.77-elevation*5.4;
	if (v <= 0.46 || v >= 0.88) return vec4(0.0);
	vec3 source = texture(panorama,vec2(u,v)).rgb;
	float alpha = smoothstep(skyline(u),skyline(u)+0.035,v);
	alpha *= smoothstep(-0.025,0.025,source.b-source.g);
	alpha *= smoothstep(0.88,0.78,v)*smoothstep(0.46,0.50,v);
	// Tageslicht-Panoramatextur je nach Tageszeit in Dunst/Dämmerung/Nacht einbetten.
	vec3 dusk = mix(source*vec3(0.38,0.42,0.57),horizon,0.30);
	vec3 day = mix(source*vec3(0.92,0.95,1.0),horizon,0.22);
	vec3 col = mix(dusk,day,daylight);
	col = mix(col,source*vec3(0.035,0.04,0.06)+horizon*0.25,night);
	return vec4(col,alpha);
}

// Fernkulisse Nord/Ost/West (assets/maps/bavaria/panorama): Streifen mit transparentem Himmel.
// *_p = (Horizontzeile v, v je Radiant, u je Radiant, u der Bildmitte = Sektorrichtung)
uniform bool far_enabled = false;
uniform sampler2D far_north : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D far_east : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D far_west : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 far_north_p = vec4(0.29,5.95,0.56,0.5);
uniform vec4 far_east_p = vec4(0.28,6.11,0.52,0.5);
uniform vec4 far_west_p = vec4(0.28,5.80,0.64,0.5);

float wrap_angle(float a) {
	return a-6.28318530718*floor((a+3.14159265359)/6.28318530718);
}

// Sektor voll bis ±36°, weich aus bis ±56°
float sector_weight(float d) {
	return 1.0-smoothstep(0.62,0.98,abs(d));
}

float edge_fade(float u) {
	return smoothstep(0.0,0.10,u)*(1.0-smoothstep(0.90,1.0,u));
}

vec3 far_tint(vec3 source, vec3 horizon) {
	vec3 dusk = mix(source*vec3(0.42,0.44,0.56),horizon,0.38);
	vec3 day = mix(source*vec3(0.95,0.97,1.0),horizon,0.25);
	vec3 col = mix(dusk,day,daylight);
	return mix(col,source*vec3(0.03,0.035,0.055)+horizon*0.30,night);
}

vec4 far_band(sampler2D tex, vec4 p, float d, float elevation, vec3 horizon) {
	float u = p.w-d*p.z;   // Azimut wächst nach links (Blick nach außen) → Bild-u fällt
	float v = p.x-elevation*p.y;
	// Ohne Verzweigung vor dem Abtasten: Mipmap-Wahl braucht gültige Ableitungen (gleichmäßiger Kontrollfluss).
	float inside = step(0.0,u)*step(u,1.0)*step(0.0,v)*step(v,1.0);
	vec4 s = texture(tex,clamp(vec2(u,v),vec2(0.0),vec2(1.0)));
	// Schmale weiche Bildkante (2 %), falls ein Bild an einer Stelle allein deckt: keine harte senkrechte Schnittkante.
	float soft = smoothstep(0.0,0.02,u)*(1.0-smoothstep(0.98,1.0,u));
	return vec4(far_tint(s.rgb,horizon),s.a*inside*soft);
}

float star_field(vec3 ray) {
	vec3 p = ray*260.0;
	vec3 cell = floor(p);
	float h = fract(sin(dot(cell,vec3(127.1,311.7,74.7)))*43758.5453);
	vec3 f = fract(p)-0.5;
	float spot = smoothstep(0.18,0.0,length(f));
	return step(0.9965,h)*spot*(0.5+0.5*fract(h*913.7));
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	float elevation = asin(clamp(ray.y,-1.0,1.0));
	vec3 east = vec3(south_direction.z,0.0,-south_direction.x);
	vec2 sun_flat = normalize(sun_direction.xz+vec2(0.00001));
	float glow = pow(max(dot(normalize(ray.xz+vec2(0.00001)),sun_flat),0.0),3.0);
	// Rot am Horizont nur bei tiefer Sonne
	float low_sun = 1.0-smoothstep(0.05,0.35,sun_direction.y);
	low_sun *= smoothstep(-0.30,-0.06,sun_direction.y);
	vec3 horizon_dusk = mix(vec3(0.30,0.34,0.47),vec3(0.65,0.36,0.27),glow);
	vec3 horizon_day = mix(vec3(0.66,0.74,0.84),vec3(0.88,0.78,0.62),glow*low_sun);
	vec3 horizon = mix(horizon_dusk,horizon_day,daylight);
	horizon = mix(horizon,vec3(0.040,0.050,0.085),night);
	vec3 zenith = mix(vec3(0.075,0.12,0.25),vec3(0.22,0.40,0.72),daylight);
	zenith = mix(zenith,vec3(0.006,0.010,0.028),night);
	vec3 result = mix(horizon,zenith,smoothstep(0.0,1.1,elevation));
	vec3 ground = mix(vec3(0.10,0.13,0.14),vec3(0.30,0.33,0.31),daylight)*(1.0-0.85*night);
	if (elevation < 0.0) result = mix(horizon,ground,smoothstep(0.0,0.4,-elevation));
	// Weiche, unregelmäßige Wolkenbänder; kein Kondensstreifen.
	vec2 cloud_uv = ray.xz/max(ray.y,0.12)*vec2(0.7,1.5)+vec2(12.3,4.8);
	float clouds = cloud_noise(cloud_uv)*0.58+cloud_noise(cloud_uv*2.1)*0.28+cloud_noise(cloud_uv*4.3)*0.14;
	float cloud_mask = smoothstep(0.48,0.75,clouds)*smoothstep(0.035,0.17,elevation);
	vec3 cloud_color = mix(vec3(0.15,0.18,0.27),vec3(0.48,0.30,0.28),glow);
	cloud_color = mix(cloud_color,mix(vec3(0.86,0.87,0.90),vec3(0.95,0.80,0.66),glow*low_sun),daylight);
	cloud_color = mix(cloud_color,vec3(0.025,0.030,0.045),night);
	result = mix(result,cloud_color,cloud_mask*mix(0.55,0.70,daylight));
	// Sterne nur bei Nacht und klarem Himmel
	result += vec3(0.85,0.88,1.0)*star_field(ray)*night*(1.0-cloud_mask)*smoothstep(0.04,0.25,elevation);
	float azimuth = atan(dot(ray,east),dot(ray,south_direction));   // 0 = Süd, +π/2 = Ost, ±π = Nord, −π/2 = West
	if (far_enabled) {
		// Umlaufende Fernkulisse: Süd = Alpen, Nord/Ost/West = Landschaftsstreifen; weiche Sektorübergänge
		float d_s = azimuth;
		float d_e = wrap_angle(azimuth-1.5707963);
		float d_n = wrap_angle(azimuth-3.1415927);
		float d_w = wrap_angle(azimuth+1.5707963);
		float w_s = sector_weight(d_s);
		float w_e = sector_weight(d_e);
		float w_n = sector_weight(d_n);
		float w_w = sector_weight(d_w);
		float us = 0.5+d_s*panorama_repeats/6.28318530718;
		// Gewicht = Sektor × Bildrand (jedes Bild blendet an seinem Rand aus; der Nachbar übernimmt)
		w_s *= edge_fade(us);
		w_e *= edge_fade(far_east_p.w-d_e*far_east_p.z);
		w_n *= edge_fade(far_north_p.w-d_n*far_north_p.z);
		w_w *= edge_fade(far_west_p.w-d_w*far_west_p.z);
		// Quadrierte Gewichte: kürzere Überblendzone, weniger halbdeckender „Dunst“ an den Nähten (Ost/Süd, Nord/West)
		w_s *= w_s; w_e *= w_e; w_n *= w_n; w_w *= w_w;
		float wsum = max(w_s+w_e+w_n+w_w,0.00001);
		vec4 s = (us>0.0 && us<1.0) ? mountain_band(us,elevation,horizon) : vec4(0.0);
		vec4 e = far_band(far_east,far_east_p,d_e,elevation,horizon);
		vec4 n = far_band(far_north,far_north_p,d_n,elevation,horizon);
		vec4 w = far_band(far_west,far_west_p,d_w,elevation,horizon);
		float a_s = s.a*w_s/wsum;
		float a_e = e.a*w_e/wsum;
		float a_n = n.a*w_n/wsum;
		float a_w = w.a*w_w/wsum;
		float coverage = a_s+a_e+a_n+a_w;
		vec3 far_col = (s.rgb*a_s+e.rgb*a_e+n.rgb*a_n+w.rgb*a_w)/max(coverage,0.00001);
		// Naht zwischen zwei Bildern mit unterschiedlicher Hügellinie: Land des stärkeren Bildes bleibt deckend
		// (sonst schimmert in der Überblendung ein heller Himmelsstreifen durch)
		// Jedes Bild mit nennenswertem Anteil (≥ 25 % der Gewichte) deckt mit seinem eigenen Land voll – auch wenn das
		// stärker gewichtete Nachbarbild dort Himmel/Lücke hat (Ost/Süd-Dunst: Alpenband unter der Bergkontur leer).
		float c_s = s.a*smoothstep(0.0,0.25,w_s/wsum);
		float c_e = e.a*smoothstep(0.0,0.25,w_e/wsum);
		float c_n = n.a*smoothstep(0.0,0.25,w_n/wsum);
		float c_w = w.a*smoothstep(0.0,0.25,w_w/wsum);
		coverage = max(coverage,max(max(c_s,c_e),max(c_n,c_w)));
		result = mix(result,far_col,clamp(coverage,0.0,1.0));
	} else {
		// Ohne Fernkulisse: Alpenband umlaufend, überlappende Sektoren statt sichtbarer Texturkanten.
		float u = fract(azimuth/6.28318530718*panorama_repeats+0.5);
		float other_u = fract(u+0.5);
		float weight = pow(sin(3.14159265359*u),2.0);
		vec4 a = mountain_band(u,elevation,horizon);
		vec4 b = mountain_band(other_u,elevation,horizon);
		float alpha_a = a.a*weight;
		float alpha_b = b.a*(1.0-weight);
		float coverage = alpha_a+alpha_b;
		vec3 mountains = (a.rgb*alpha_a+b.rgb*alpha_b)/max(coverage,0.00001);
		result = mix(result,mountains,coverage);
	}
	if (LIGHT0_ENABLED) {
		// Licht 0 = Sonne bzw. nachts der Mond (gleiche Richtungsleuchte)
		float disc = smoothstep(mix(0.9997,0.99993,night),mix(0.99995,0.99998,night),dot(ray,LIGHT0_DIRECTION));
		vec3 disc_color = mix(LIGHT0_COLOR*0.7,vec3(0.78,0.80,0.86),night);
		result += disc_color*disc*smoothstep(0.0,0.025,ray.y);
	}
	COLOR = result;
}
