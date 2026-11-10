shader_type sky;
uniform sampler2D panorama : source_color, filter_linear;
uniform vec3 south_direction = vec3(0.817,0.0,0.576);
uniform float panorama_repeats = 3.0;

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
	// Tageslicht-Panoramatextur in denselben kühlen Dämmerungsdunst wie den Fernhorizont einbetten.
	return vec4(mix(source*vec3(0.38,0.42,0.57),horizon,0.30),alpha);
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	float elevation = asin(clamp(ray.y,-1.0,1.0));
	vec3 east = vec3(south_direction.z,0.0,-south_direction.x);
	float west = pow(max(dot(normalize(ray.xz+vec2(0.00001)),normalize(-east.xz)),0.0),3.0);
	vec3 horizon = mix(vec3(0.30,0.34,0.47),vec3(0.65,0.36,0.27),west);
	vec3 zenith = vec3(0.075,0.12,0.25);
	vec3 result = mix(horizon,zenith,smoothstep(0.0,1.1,elevation));
	if (elevation < 0.0) result = mix(horizon,vec3(0.10,0.13,0.14),smoothstep(0.0,0.4,-elevation));
	// Weiche, unregelmäßige Wolkenbänder; kein Taghimmel oder Kondensstreifen.
	vec2 cloud_uv = ray.xz/max(ray.y,0.12)*vec2(0.7,1.5)+vec2(12.3,4.8);
	float clouds = cloud_noise(cloud_uv)*0.58+cloud_noise(cloud_uv*2.1)*0.28+cloud_noise(cloud_uv*4.3)*0.14;
	float cloud_mask = smoothstep(0.48,0.75,clouds)*smoothstep(0.035,0.17,elevation);
	vec3 cloud_color = mix(vec3(0.15,0.18,0.27),vec3(0.48,0.30,0.28),west);
	result = mix(result,cloud_color,cloud_mask*0.55);
	float azimuth = atan(dot(ray,east),dot(ray,south_direction));
	// Umlaufende künstlerische Bergkulisse: überlappende Sektoren statt sichtbarer Texturkanten.
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
	if (LIGHT0_ENABLED) {
		float sun = smoothstep(0.9997,0.99995,dot(ray,LIGHT0_DIRECTION));
		result += LIGHT0_COLOR*sun*0.7*smoothstep(0.0,0.025,ray.y);
	}
	COLOR = result;
}
