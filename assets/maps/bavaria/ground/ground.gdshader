shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D grass_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D flower_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D soil_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D light_soil_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D gravel_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D stone_grass_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform int surface_kind = 0;
uniform float route_half_width = 0.0;
uniform vec2 route_a;
uniform vec2 route_b;
varying vec3 world_position;
vec2 hash2(vec2 p){return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);}
float noise(vec2 p){vec2 a=floor(p);vec2 f=smoothstep(vec2(0.0),vec2(1.0),fract(p));return mix(mix(hash2(a).x,hash2(a+vec2(1,0)).x,f.x),mix(hash2(a+vec2(0,1)).x,hash2(a+vec2(1,1)).x,f.x),f.y);}
vec3 tile(sampler2D tex,vec2 uv){
 vec2 cell=floor(uv*0.35);vec2 f=smoothstep(vec2(0.0),vec2(1.0),fract(uv*0.35));
 vec3 a=texture(tex,uv+hash2(cell)*9.0).rgb;
 vec3 b=texture(tex,uv+hash2(cell+vec2(1,0))*9.0).rgb;
 vec3 c=texture(tex,uv+hash2(cell+vec2(0,1))*9.0).rgb;
 vec3 d=texture(tex,uv+hash2(cell+vec2(1,1))*9.0).rgb;
 return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 // Texturfläche etwa 2,4×1,59 m, Steine bleiben kiesgroß statt meterhoher Brocken.
 vec2 p=world_position.xz;vec2 uv=p/vec2(2.4,1.587);
 float broad=noise(p*0.13);float patch=smoothstep(0.28,0.73,noise(p*0.43));
 vec3 base=tile(grass_tex,uv);
 if(surface_kind==0){base=mix(base,tile(light_soil_tex,uv),0.12+patch*0.26);}
 if(surface_kind==1){base=mix(base,tile(flower_tex,uv),0.18+patch*0.48);base=mix(base,tile(light_soil_tex,uv),broad*0.13);}
 if(surface_kind==2){base=mix(tile(soil_tex,uv),tile(light_soil_tex,uv),patch*0.38);base=mix(base,tile(gravel_tex,uv),broad*0.18);}
 if(surface_kind==3){base=mix(tile(gravel_tex,uv),tile(stone_grass_tex,uv),0.15+patch*0.40);}
 if(surface_kind==4){base=mix(tile(stone_grass_tex,uv),base,patch*0.60);}
 base*=0.91+noise(p*0.045)*0.16;
 if(route_half_width>0.0){
  vec2 ab=route_b-route_a;float t=clamp(dot(p-route_a,ab)/max(dot(ab,ab),0.001),0.0,1.0);
  float dist=length(p-(route_a+t*ab));
  float edge=smoothstep(route_half_width-0.42,route_half_width,dist+noise(p*3.2)*0.12);
  base=mix(base,tile(grass_tex,uv),edge);
 }
 ALBEDO=base;ROUGHNESS=0.92;SPECULAR=0.18;
}
