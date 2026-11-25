shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D screen : hint_screen_texture, repeat_disable, filter_nearest;

void fragment() {
	vec4 sample_color = texture(screen, SCREEN_UV);
	float luma = dot(sample_color.rgb, vec3(.25,.59,.16));
	vec3 vivid = mix(vec3(luma), sample_color.rgb, 1.09);
	COLOR = vec4(clamp(vivid + .115*luma*(1.0-sample_color.rgb),vec3(0),vec3(1)),sample_color.a);
}
