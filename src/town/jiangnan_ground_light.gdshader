shader_type canvas_item;

varying vec2 world_position;
uniform sampler2D continuous_grass : source_color, repeat_enable, filter_nearest;

float hash_position(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float light_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(mix(hash_position(cell), hash_position(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_position(cell + vec2(0.0, 1.0)), hash_position(cell + vec2(1.0, 1.0)), blend.x), blend.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Atlas variants preserve their original alpha/corner masks. Their RGB must
	// share map-space coordinates: random atlas selection cannot cut a grass patch.
	vec2 atlas_size = 1.0 / TEXTURE_PIXEL_SIZE;
	// TileMap runtime atlases pad every 8px cell with a pixel on each side.
	// Sprite/editor previews use the original atlas; handle both representations.
	if (abs(atlas_size.x - 900.0) < 0.5 || abs(atlas_size.x - 1280.0) < 0.5) {
		atlas_size *= 0.8;
	}
	float atlas_y = UV.y * atlas_size.y;
	bool grass_band = abs(atlas_size.x - 720.0) < 0.5 &&
		(atlas_y < 48.0 || (atlas_y >= 288.0 && atlas_y < 336.0));
	bool frontage_grass = abs(atlas_size.x - 1024.0) < 0.5 &&
		abs(atlas_size.y - 496.0) < 0.5 && atlas_y < 392.0;
	if (grass_band || frontage_grass) {
		COLOR.rgb = texture(continuous_grass, floor(world_position / 2.0) / 256.0).rgb;
		if (grass_band && atlas_y >= 288.0) COLOR.rgb *= vec3(0.88, 0.92, 0.88);
	}
	vec2 pixel = floor(world_position * 0.4) / 0.4;
	float patches = light_noise(pixel / 265.0) * 0.82 + light_noise(pixel / 87.0) * 0.18;
	COLOR.rgb *= mix(vec3(0.81, 0.88, 0.81), vec3(1.10, 1.06, 0.96), patches);
}
