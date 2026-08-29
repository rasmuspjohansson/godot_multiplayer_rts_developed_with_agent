extends RefCounted
## Parabolic arrow flight: launch angle scales with horizontal distance.

const CLOSE_DIST := 18.0
const MAX_DIST := 120.0
const ANGLE_CLOSE := 5.0
const ANGLE_MAX := 45.0

static func launch_angle_deg(dist: float) -> float:
	var t := clampf((dist - CLOSE_DIST) / (MAX_DIST - CLOSE_DIST), 0.0, 1.0)
	return lerpf(ANGLE_CLOSE, ANGLE_MAX, t)

static func peak_height(dist: float) -> float:
	return dist * tan(deg_to_rad(launch_angle_deg(dist))) / 4.0

static func flight_duration(dist: float) -> float:
	return clampf(dist / 200.0, 0.30, 0.70)

static func sample(from: Vector3, to: Vector3, peak: float, t: float) -> Vector3:
	var p := from.lerp(to, t)
	p.y += peak * 4.0 * t * (1.0 - t)
	return p

static func arrow_endpoints(archer_pos: Vector3, target_pos: Vector3) -> Dictionary:
	var delta_xz := Vector2(target_pos.x - archer_pos.x, target_pos.z - archer_pos.z)
	var dist: float = delta_xz.length()
	var dir_xz := Vector2.ZERO
	if dist > 0.01:
		dir_xz = delta_xz / dist
	var from := archer_pos + Vector3(dir_xz.x * 3.0, 2.0, dir_xz.y * 3.0)
	return {
		"from": from,
		"to": target_pos,
		"dist": dist,
		"peak": peak_height(dist),
		"duration": flight_duration(dist),
	}
