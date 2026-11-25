shader_type canvas_item;

// Work in native town pixels even when the atlas camera zooms. Average the
// paint within each pixel so tiny white flecks do not sparkle as the player walks.
uniform vec4 atlas_rect;
uniform vec2 map_size;
uniform bool cascade = false;
uniform float game_minute;
varying vec4 light;

void vertex() {
	light = COLOR;
}

void fragment() {
	vec2 p = floor((UV-atlas_rect.xy)/atlas_rect.zw*map_size) + .5;
	vec2 local = p/map_size;
	vec2 d = .28/map_size;
	vec2 guard = .5 * TEXTURE_PIXEL_SIZE / atlas_rect.zw;
	vec4 ink = vec4(0.);
	for (int y=0; y<2; y++) {
		for (int x=0; x<2; x++) {
			vec2 uv = clamp(local+(vec2(float(x),float(y))*2.-1.)*d,guard,vec2(1.)-guard);
			vec4 sample_color = texture(TEXTURE,atlas_rect.xy+uv*atlas_rect.zw);
			ink += .25*vec4(sample_color.rgb*sample_color.a,sample_color.a);
		}
	}
	vec3 c = ink.rgb/max(ink.a,.001);
	float lum = dot(c,vec3(.29,.56,.15));
	// Cool slate shade, warm weathered facets and subdued foam from this coast.
	float band = floor(lum*15.+.5)/15.;
	vec3 stone = mix(c, vec3(lum), .14) + (band-lum)*.43;
	stone = stone*.87 + mix(vec3(.035,.052,.06),vec3(.069,.067,.043),lum);
	float wet = smoothstep(-.01,.095,c.b-c.r+.04)*smoothstep(.4,.79,lum);
	stone = mix(stone,stone*vec3(.82,.93,.91),wet*.72);
	if (cascade) {
		// Limit flow to the pale threads of the painted fall. The moss and
		// rocks on its shoulders stay still. Two waves fade through each other.
		float lane = smoothstep(.21,.37,local.x)*(1.-smoothstep(.69,.84,local.x));
		float height = smoothstep(.13,.34,local.y)*(1.-smoothstep(.78,.93,local.y));
		float water = lane*height*smoothstep(.24,.75,lum)*smoothstep(-.06,.08,c.b-c.r+.055);
		float drift = .5+.5*sin(p.y*.54-game_minute*4.1+1.4*sin(p.x*.72));
		float run = .5+.5*sin(p.y*.29-game_minute*2.7+p.x*.47);
		vec3 ribbon = mix(vec3(.31,.52,.54),vec3(.78,.85,.78),.20+.50*drift+.30*run);
		stone = mix(stone,ribbon,water*.78);
	}
	COLOR = vec4(stone*light.rgb,ink.a*light.a);
}
