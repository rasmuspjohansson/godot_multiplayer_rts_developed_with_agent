shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap;
uniform sampler2D steep_tex : source_color, filter_linear_mipmap;

void fragment() {
	vec4 grass = texture(grass_tex, UV);
	vec4 steep = texture(steep_tex, UV);
	float walkable = COLOR.a;
	vec3 tinted_grass = grass.rgb * COLOR.rgb;
	ALBEDO = mix(steep.rgb, tinted_grass, walkable);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
