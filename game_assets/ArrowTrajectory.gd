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
