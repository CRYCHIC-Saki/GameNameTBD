shader_type canvas_item;
uniform float game_minute;
varying float wash;
void vertex() {
	float phase = VERTEX.y*.037 + game_minute*.43;
	VERTEX.x += 1.35*sin(phase);
	VERTEX.y += .55*cos(phase);
	wash = .78+.21*sin(phase);
}
void fragment() { COLOR.a *= wash; }
