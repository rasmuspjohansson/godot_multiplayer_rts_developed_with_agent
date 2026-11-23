shader_type spatial;
render_mode cull_disabled;

uniform sampler2D steep_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(1.0, 1.0);
uniform float fog_enabled = 0.0;

void fragment() {
	ALBEDO = texture(steep_tex, UV).rgb;
	if (fog_enabled > 0.5) {
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 fog_uv = clamp(world_pos.xz / map_size, vec2(0.0), vec2(1.0));
		ALBEDO *= texture(fog_tex, fog_uv).g;
	}
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
