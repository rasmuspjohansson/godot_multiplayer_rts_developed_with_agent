extends Node3D
## Short-lived arrow visual following a parabolic arc.

const _ArrowTrajectory = preload("res://ArrowTrajectory.gd")
const ARROW_TEXTURE_PATH := "res://images/arrow/arrow_pointing_right.png"
const ARROW_WORLD_LENGTH := 10.0

static var _cached_texture: Texture2D

var _from: Vector3
var _to: Vector3
var _duration: float = 0.5
var _peak: float = 0.0
var _t: float = 0.0
var _sprite: Sprite3D

func setup(from: Vector3, to: Vector3, duration: float, peak: float) -> void:
	_from = from
	_to = to
	_duration = maxf(duration, 0.01)
	_peak = peak
	_build_sprite()
	global_position = _ArrowTrajectory.sample(_from, _to, _peak, 0.0)
	_update_facing(0.0)

func _build_sprite() -> void:
	if _sprite != null:
		return
	var tex := _load_texture()
	if tex == null:
		return
	_sprite = Sprite3D.new()
	_sprite.texture = tex
	_sprite.axis = Vector3.AXIS_X
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.pixel_size = ARROW_WORLD_LENGTH / float(tex.get_height())
	add_child(_sprite)

func _load_texture() -> Texture2D:
	if _cached_texture != null:
		return _cached_texture
	var img := Image.new()
	if img.load(ARROW_TEXTURE_PATH) == OK:
		_cached_texture = ImageTexture.create_from_image(img)
		return _cached_texture
	if ResourceLoader.exists(ARROW_TEXTURE_PATH):
		var res: Resource = ResourceLoader.load(ARROW_TEXTURE_PATH)
		if res is Texture2D:
			_cached_texture = res as Texture2D
	return _cached_texture

func _process(delta: float) -> void:
	_t += delta / _duration
	if _t >= 1.0:
		queue_free()
		return
	global_position = _ArrowTrajectory.sample(_from, _to, _peak, _t)
	_update_facing(_t)

func _update_facing(t: float) -> void:
	var eps := 0.02
	var t1 := clampf(t, 0.0, 1.0)
	var t2 := clampf(t + eps, 0.0, 1.0)
	var vel := _ArrowTrajectory.sample(_from, _to, _peak, t2) - _ArrowTrajectory.sample(_from, _to, _peak, t1)
	if vel.length_squared() < 0.0001:
		return
	var x_axis := vel.normalized()
	var z_axis := x_axis.cross(Vector3.UP)
	if z_axis.length_squared() < 0.0001:
		z_axis = Vector3.FORWARD
	z_axis = z_axis.normalized()
	var y_axis := z_axis.cross(x_axis)
	global_transform.basis = Basis(x_axis, y_axis, z_axis)
