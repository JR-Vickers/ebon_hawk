shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform sampler2D diffuse_texture : source_color, filter_linear_mipmap;
uniform sampler2D lightmap_texture : source_color, filter_linear_mipmap;
uniform vec3 self_illumination = vec3(0.0);
uniform float opacity = 1.0;
uniform bool alpha_is_reflectivity = false;

void fragment() {
	vec4 diffuse = texture(diffuse_texture, UV);
	ALBEDO = diffuse.rgb * (texture(lightmap_texture, UV2).rgb + self_illumination);
	ALPHA = (alpha_is_reflectivity ? 1.0 : diffuse.a) * opacity;
}
