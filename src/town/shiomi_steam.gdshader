shader_type canvas_item;

uniform float game_minute;
varying vec2 map_pixel;

void vertex() {
	map_pixel = VERTEX;
}

float hash_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 4375.5453);
}

float soft_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(i), hash_cell(i + vec2(1.,0.)), f.x),
		mix(hash_cell(i + vec2(0.,1.)), hash_cell(i + vec2(1.)), f.x), f.y);
}

void fragment() {
	// One sample per map pixel, so the haze belongs to the same view as the bath.
	vec2 uv = (floor(map_pixel) + .5) / vec2(70.,54.);
	float height = 1.0 - uv.y;
	float mist = 0.;
	for (int i = 0; i < 3; i++) {
		float vent = float(i);
		float rise = height * 4.6 - game_minute * (.72 + vent * .07);
		float billow = soft_noise(vec2(vent * 9.4, rise));
		float bend = height * (.10 + .11 * sin(rise * 2. + vent));
		float dx = uv.x - (.16 + vent * .255 + bend);
		float width = .032 + height * .089 + billow * .034;
		float body = exp(-dx * dx / (width * width));
		float lace = soft_noise(vec2(dx * 17. + vent * 4., rise * 1.9));
		mist += body * (.19 + .81 * billow) * (.40 + .60 * lace);
	}
	float fade = smoothstep(.0,.12,height) * (1. - smoothstep(.52,1.,height));
	COLOR = vec4(COLOR.rgb * vec3(.97,.97,.92), COLOR.a * clamp(mist * fade * .91,0.,.78));
}
