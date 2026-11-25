shader_type canvas_item;
uniform vec4 frame;
uniform float game_minute;
uniform float evening;
// 0 = glazed building windows, 1 = street lamp, 2 = fountain, 3 = forge chimney.
uniform int fixture;
varying vec4 light;
void vertex() { light = COLOR; }
void fragment() {
	vec2 local = (UV-frame.xy)/frame.zw;
	vec2 uv = UV;
	if (fixture==3 && local.x>.22 && local.x<.43 && local.y<.25) {
		uv.x += frame.z*.012*sin(local.y*19.0+game_minute*.84)*(1.0-smoothstep(.03,.25,local.y));
	}
	vec4 ink=texture(TEXTURE,uv);
	vec3 paint=ink.rgb*light.rgb;
	if (fixture==2) {
		float water=smoothstep(.13,.38,ink.b-ink.r)*smoothstep(.32,.70,ink.g);
		paint+=water*(.12+.12*sin(local.y*100.0-game_minute*2.5+local.x*5.0))*light.rgb;
	} else {
		float gold=smoothstep(.67,.93,ink.r)*smoothstep(.39,.67,ink.g)*smoothstep(.22,.52,ink.r-ink.b);
		float pane=fixture==1 ? (1.0-step(.46,local.y)) : step(.39,local.y)*(1.0-step(.87,local.y));
		paint=mix(paint,vec3(1.0,.76,.35),gold*pane*evening*.92);
	}
	COLOR=vec4(paint,ink.a*light.a);
}
