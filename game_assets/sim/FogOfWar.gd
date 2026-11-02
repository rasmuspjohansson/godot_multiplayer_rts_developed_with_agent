extends RefCounted
## World-space fog. One disc per friendly army, in map XZ, so it does not move when the
## camera turns. G is "explored" and only grows. Queried by the ground shader
## and by the unit renderer.

const CELL := 16.0
## How far past the outermost soldier an army can see.
const SIGHT := 160.0

var texture: ImageTexture
var _image: Image
var _bytes := PackedByteArray()
var _cols: int = 1
var _rows: int = 1
var _dirty := false

func setup(map_w: float, map_h: float) -> void:
	_cols = maxi(1, int(ceil(map_w / CELL)))
	_rows = maxi(1, int(ceil(map_h / CELL)))
	_bytes.resize(_cols * _rows * 4)
	for i in range(_cols * _rows):
		_bytes[i * 4 + 3] = 255
	_image = Image.create(_cols, _rows, false, Image.FORMAT_RGBA8)
	_upload()

## Explored cells stay explored. A cell already set is left alone.
func stamp_circle(x: float, z: float, radius: float) -> void:
	if radius <= 0.0:
		return
	var rad_cells := int(ceil(radius / CELL))
	var c0 := int(floor(x / CELL))
	var r0 := int(floor(z / CELL))
	var r2 := radius * radius
	for dj in range(-rad_cells, rad_cells + 1):
		var j := r0 + dj
		if j < 0 or j >= _rows:
			continue
		for di in range(-rad_cells, rad_cells + 1):
			var i := c0 + di
			if i < 0 or i >= _cols:
				continue
			var wx := (float(i) + 0.5) * CELL
			var wz := (float(j) + 0.5) * CELL
			var dx := wx - x
			var dz := wz - z
			if dx * dx + dz * dz > r2:
				continue
			var o := (j * _cols + i) * 4 + 1
			if _bytes[o] == 255:
				continue
			_bytes[o] = 255
			_dirty = true

func end_stamp() -> void:
	if not _dirty:
		return
	_dirty = false
	_upload()

func is_explored(x: float, z: float) -> bool:
	return _channel(x, z, 1) > 127

## 1 on discovered ground, 0 if never seen.
func light_at(x: float, z: float) -> float:
	if is_explored(x, z):
		return 1.0
	return 0.0

func _channel(x: float, z: float, channel: int) -> int:
	var i := clampi(int(floor(x / CELL)), 0, _cols - 1)
	var j := clampi(int(floor(z / CELL)), 0, _rows - 1)
	return _bytes[(j * _cols + i) * 4 + channel]

func _upload() -> void:
	_image.set_data(_cols, _rows, false, Image.FORMAT_RGBA8, _bytes)
	if texture == null:
		texture = ImageTexture.create_from_image(_image)
	else:
		texture.update(_image)
