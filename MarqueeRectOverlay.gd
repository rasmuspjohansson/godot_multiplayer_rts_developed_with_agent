extends Control
## Screen-space dashed selection rectangle; mouse_filter ignore so input reaches world.

var _rect: Rect2 = Rect2()
var _show: bool = false

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_marquee_rect(r: Rect2, show_rect: bool) -> void:
	_rect = r
	_show = show_rect
	queue_redraw()

func _draw() -> void:
	if not _show:
		return
	var r := _rect
	var col := Color(0.25, 0.85, 1.0, 0.95)
	var dash := 10.0
	var gap := 6.0
	_draw_dashed_polyline([
		Vector2(r.position.x, r.position.y),
		Vector2(r.position.x + r.size.x, r.position.y),
		Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
		Vector2(r.position.x, r.position.y + r.size.y),
		Vector2(r.position.x, r.position.y),
	], col, 2.0, dash, gap)

func _draw_dashed_polyline(pts: Array, color: Color, width: float, dash_len: float, gap_len: float) -> void:
	var step := dash_len + gap_len
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := b - a
		var L := seg.length()
		if L < 0.001:
			continue
		var dir := seg / L
		var t := 0.0
		while t < L:
			var d := minf(dash_len, L - t)
			draw_line(a + dir * t, a + dir * (t + d), color, width)
			t += step
