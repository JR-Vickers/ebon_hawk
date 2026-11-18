shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D frame_texture : source_color, filter_linear;
uniform vec4 content_uv = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 fitted_uv = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
    vec2 local_uv = (UV - fitted_uv.xy) / fitted_uv.zw;
    if (any(lessThan(local_uv, vec2(0.0))) || any(greaterThanEqual(local_uv, vec2(1.0)))) {
        ALBEDO = vec3(0.005);
    } else {
        ALBEDO = texture(frame_texture, content_uv.xy + local_uv * content_uv.zw).rgb;
    }
}
