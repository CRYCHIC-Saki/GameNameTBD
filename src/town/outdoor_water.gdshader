shader_type canvas_item;

uniform float game_minute = 720.0;
uniform vec2 map_origin;
uniform vec2 world_per_pixel = vec2(1.0);
uniform bool river = false;
uniform bool resample_surface = false;
uniform sampler2D continuous_surface : source_color, repeat_enable, filter_nearest;
varying vec2 map_pixel;
varying vec3 surface_tint;

void vertex() {
	map_pixel = ((MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - map_origin) / world_per_pixel;
	surface_tint = COLOR.rgb;
}

void fragment() {
	vec2 p = floor(map_pixel);
	if (resample_surface) {
		// Water cells retain their shoreline mask and sample one continuous world surface.
		COLOR.rgb = texture(continuous_surface, floor(map_pixel * 2.0) / 256.0).rgb;
		COLOR.rgb *= surface_tint * vec3(.82,.92,.97);
	}
	float t = game_minute;
	// Short glints gather and separate on differently spaced rows of crests.
	float row = floor((p.y + t * (river ? 1.9 : .65)) / 10.0);
	float drift = sin(row * 19.37) * 34.0;
	float run = mod(p.x + drift - t * (river ? 2.9 : 1.6), 47.0);
	float crest = mod(p.y + t * (river ? 1.9 : .65) + 1.45*sin(p.x*.062 + row + t*.13), 10.0);
	float shimmer = (1.0-smoothstep(.55,1.55,crest)) * smoothstep(0.,3.,run)
		* (1.0-smoothstep(8.,18.,run)) * (.48+.52*pow(sin(row*3.7+t*.25)*.5+.5,2.));
	COLOR.rgb *= 1.0 + .035*sin(p.y*.19+p.x*.025-t*.77);
	COLOR.rgb += vec3(.24,.38,.38)*shimmer*clamp(dot(COLOR.rgb,vec3(.30,.53,.17))*2.1,.10,1.0);
}
