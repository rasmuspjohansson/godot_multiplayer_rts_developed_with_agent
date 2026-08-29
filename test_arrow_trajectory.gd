extends SceneTree

const _ArrowTrajectory = preload("res://ArrowTrajectory.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var T = _ArrowTrajectory
	var angle_max := T.launch_angle_deg(120.0)
	if absf(angle_max - 45.0) > 0.01:
		print("TEST_ARROW_TRAJECTORY_FAIL: angle at max dist got %.2f want 45" % angle_max)
		quit(1)
		return
	var peak_max := T.peak_height(120.0)
	if absf(peak_max - 30.0) > 0.5:
		print("TEST_ARROW_TRAJECTORY_FAIL: peak at max dist got %.2f want ~30" % peak_max)
		quit(1)
		return
	var angle_close := T.launch_angle_deg(18.0)
	if absf(angle_close - 5.0) > 0.01:
		print("TEST_ARROW_TRAJECTORY_FAIL: angle at close dist got %.2f want 5" % angle_close)
		quit(1)
		return
	var mid := T.launch_angle_deg(60.0)
	if mid <= angle_close or mid >= angle_max:
		print("TEST_ARROW_TRAJECTORY_FAIL: mid-range angle not between close and max")
		quit(1)
		return
	var from := Vector3(0.0, 10.0, 0.0)
	var to := Vector3(120.0, 12.0, 0.0)
	var peak := T.peak_height(120.0)
	if from.distance_to(T.sample(from, to, peak, 0.0)) > 0.01:
		print("TEST_ARROW_TRAJECTORY_FAIL: sample t=0 != from")
		quit(1)
		return
	if to.distance_to(T.sample(from, to, peak, 1.0)) > 0.01:
		print("TEST_ARROW_TRAJECTORY_FAIL: sample t=1 != to")
		quit(1)
		return
	var mid_y := T.sample(from, to, peak, 0.5).y
	var base_mid_y := from.lerp(to, 0.5).y
	if mid_y <= base_mid_y + peak * 0.9:
		print("TEST_ARROW_TRAJECTORY_FAIL: arc peak not near t=0.5")
		quit(1)
		return
	if absf(T.flight_duration(120.0) - 0.6) > 0.01:
		print("TEST_ARROW_TRAJECTORY_FAIL: duration at 120 got %.2f want 0.6" % T.flight_duration(120.0))
		quit(1)
		return
	if absf(T.flight_duration(18.0) - 0.3) > 0.01:
		print("TEST_ARROW_TRAJECTORY_FAIL: duration at 18 got %.2f want 0.3" % T.flight_duration(18.0))
		quit(1)
		return
	print("TEST_ARROW_TRAJECTORY_OK")
	quit(0)
