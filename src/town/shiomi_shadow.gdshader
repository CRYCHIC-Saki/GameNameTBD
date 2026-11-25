shader_type canvas_item;
render_mode blend_mul, unshaded;

uniform vec4 atlas_rect;
varying float strength;

void vertex() {
    strength = COLOR.a;
}

void fragment() {
    // A wider penumbra away from the feet keeps the base planted.
    float reach = clamp((atlas_rect.y + atlas_rect.w - UV.y) / atlas_rect.w, 0.0, 1.0);
    vec2 blur = atlas_rect.zw * vec2(0.027, 0.068) * mix(0.38, 1.0, reach);
    vec2 lo = atlas_rect.xy;
    vec2 hi = lo + atlas_rect.zw;
    float coverage = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float weight = float((2 - abs(x)) * (2 - abs(y)));
            vec2 pt = UV + vec2(float(x), float(y)) * blur;
            if (all(greaterThanEqual(pt, lo)) && all(lessThanEqual(pt, hi))) {
                coverage += weight * texture(TEXTURE, clamp(pt, lo + TEXTURE_PIXEL_SIZE * 0.5, hi - TEXTURE_PIXEL_SIZE * 0.5)).a;
            }
        }
    }
    COLOR = vec4(mix(vec3(1.0), vec3(0.20, 0.26, 0.36), coverage * strength / 16.0), 1.0);
}
