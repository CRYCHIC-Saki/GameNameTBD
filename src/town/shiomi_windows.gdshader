shader_type canvas_item;
uniform float lamps : hint_range(0,1) = 0.0;
uniform vec4 atlas_rect;
uniform float max_window_y = 0.85;
varying vec4 illumination;
void vertex() { illumination = COLOR; }
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float paper = smoothstep(.63,.90,ink.r) * smoothstep(.16,.39,ink.r-ink.b) * smoothstep(.36,.63,ink.g);
	vec2 local = (UV - atlas_rect.xy) / atlas_rect.zw;
	paper *= step(.24, local.y) * step(local.y, max_window_y) * step(.06, local.x) * step(local.x, .94);
	vec3 lit = mix(ink.rgb * illumination.rgb, vec3(1.0,.74,.32), paper*lamps*.90);
	COLOR = vec4(lit, ink.a*illumination.a);
}
