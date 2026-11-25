shader_type canvas_item;

varying vec2 world_position;

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
	vec2 pixel = floor(world_position * 0.4) / 0.4;
	float patches = light_noise(pixel / 265.0) * 0.82 + light_noise(pixel / 87.0) * 0.18;
	COLOR.rgb *= mix(vec3(0.81, 0.88, 0.81), vec3(1.10, 1.06, 0.96), patches);
}
