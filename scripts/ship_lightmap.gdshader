shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D diffuse_texture : source_color, filter_linear_mipmap;
uniform sampler2D lightmap_texture : source_color, filter_linear_mipmap;
uniform vec3 self_illumination = vec3(0.0);
uniform float opacity = 1.0;

void fragment() {
	vec4 diffuse = texture(diffuse_texture, UV);
	ALBEDO = diffuse.rgb * (texture(lightmap_texture, UV2).rgb + self_illumination);
}
