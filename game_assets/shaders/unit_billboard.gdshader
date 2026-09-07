shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_opaque, shadows_disabled;

// Stacked spritesheet: 4 rows (idle, move, attack, die), sheet_cols frames per row.
uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float sheet_cols = 1.0;
uniform vec4 frames = vec4(1.0);      // frame count per row
uniform vec4 fps = vec4(8.0);         // authored playback fps per row
uniform float anim_speed = 1.0;       // live multiplier for idle/move/attack (death stays authored)
uniform vec4 feet = vec4(0.1);        // feet position as fraction of frame height from the bottom, per row
uniform vec4 row_scale = vec4(1.0);   // display scale per row so character heights match the move clip
uniform float base_height = 22.0;     // world height of one full frame at scale 1
uniform float time_now = 0.0;         // seconds, same clock as tick_start
uniform float tick_start = 0.0;       // time the current sim tick was written
uniform float tick_dt = 0.05;
uniform vec3 select_tint = vec3(1.35, 1.35, 0.75);

varying vec2 v_uv;
varying float v_sel;
varying float v_hp;

void vertex() {
	// INSTANCE_CUSTOM = (state, flip, phase, selected); COLOR.rgb = prev - cur, COLOR.a = hp fraction.
	float state = INSTANCE_CUSTOM.x;
	int s = int(state + 0.5);
	float flip = INSTANCE_CUSTOM.y;
	float phase = INSTANCE_CUSTOM.z;
	v_sel = INSTANCE_CUSTOM.w;
	v_hp = COLOR.a;

	vec3 cur = MODEL_MATRIX[3].xyz;
	float alpha = clamp((time_now - tick_start) / max(tick_dt, 0.0001), 0.0, 1.0);
	vec3 pos = cur + COLOR.rgb * (1.0 - alpha);
	float size_mul = MODEL_MATRIX[0][0];

	float sc = row_scale[s];
	float h = base_height * sc * size_mul;
	vec3 cam_right = normalize(vec3(INV_VIEW_MATRIX[0][0], 0.0, INV_VIEW_MATRIX[0][2]));
	vec2 q = VERTEX.xy; // QuadMesh: -0.5..0.5, +y up
	vec3 wp = pos + cam_right * (q.x * h) + vec3(0.0, (q.y + 0.5 - feet[s]) * h, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;

	float fc = max(frames[s], 1.0);
	// Death (row 3) keeps authored timing so the clip always finishes; other rows use the dial.
	float play_fps = (s == 3) ? fps[s] : fps[s] * max(anim_speed, 0.01);
	float t;
	if (s == 3) {
		t = min(floor((time_now - phase) * play_fps), fc - 1.0);
	} else if (s == 2) {
		t = mod(floor((time_now - phase) * play_fps), fc);
	} else {
		t = mod(floor(time_now * play_fps + phase), fc);
	}
	float u = q.x + 0.5;
	if (flip > 0.5) {
		u = 1.0 - u;
	}
	float v = 0.5 - q.y;
	v_uv = vec2((t + u) / sheet_cols, (float(s) + v) * 0.25);
}

void fragment() {
	vec4 c = texture(sheet, v_uv);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * mix(vec3(1.0), select_tint, v_sel);
}
