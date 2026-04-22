extends SceneTree
## Ad-hoc test: exercise Unit3D._update_facing through a "move right, then move
## left, then stand still" sequence and assert that the sprite is mirrored
## correctly via the material UV flip. Not run by verify_test_logs.sh.
##
## Run: godot --headless --path . -s test_facing_flip.gd

func _init() -> void:
	call_deferred("_begin")

func _begin() -> void:
	var Unit3DClass = load("res://Unit3D.gd")
	var u = Unit3DClass.new()
	# Build the client visual state by hand — we don't want _ready() to try to
	# load textures from disk in this logic-only test.
	u.name = "FacingTestUnit"
	u.owner_name = "A"
	u.army_id = "A1"
	u._mesh = MeshInstance3D.new()
	u._material = StandardMaterial3D.new()
	u._material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	u._texture_loaded = true
	u.global_position = Vector3(500.0, 20.0, 360.0)

	print("TEST_FACING_FLIP_BEGIN")

	# Step 1: army ordered right.
	u.has_move_goal = true
	u.sync_target_position = Vector3(900.0, 20.0, 360.0)
	u.velocity = Vector3(30.0, 0.0, 0.0)
	u._update_facing()
	var right_ok: bool = (u._facing_right == true) \
		and (u._material.uv1_scale.x < 0.0) \
		and is_equal_approx(u._material.uv1_offset.x, 1.0)
	print("TEST_FACING_FLIP_STEP: after_move_right facing_right=%s uv1_scale_x=%.2f uv1_offset_x=%.2f pass=%s" % [
		u._facing_right, u._material.uv1_scale.x, u._material.uv1_offset.x, right_ok
	])

	# Step 2: army ordered left.
	u.sync_target_position = Vector3(100.0, 20.0, 360.0)
	u.velocity = Vector3(-30.0, 0.0, 0.0)
	u._update_facing()
	var left_ok: bool = (u._facing_right == false) \
		and (u._material.uv1_scale.x > 0.0) \
		and is_equal_approx(u._material.uv1_offset.x, 0.0)
	print("TEST_FACING_FLIP_STEP: after_move_left facing_right=%s uv1_scale_x=%.2f uv1_offset_x=%.2f pass=%s" % [
		u._facing_right, u._material.uv1_scale.x, u._material.uv1_offset.x, left_ok
	])

	# Step 3: army stops (no velocity, no move goal). Facing must persist.
	var prev: bool = u._facing_right
	u.velocity = Vector3.ZERO
	u.has_move_goal = false
	u._update_facing()
	var idle_ok: bool = (u._facing_right == prev)
	print("TEST_FACING_FLIP_STEP: after_idle facing_right=%s pass=%s" % [u._facing_right, idle_ok])

	# Step 4: army ordered right again from idle.
	u.has_move_goal = true
	u.sync_target_position = Vector3(900.0, 20.0, 360.0)
	u.velocity = Vector3(30.0, 0.0, 0.0)
	u._update_facing()
	var right_again_ok: bool = (u._facing_right == true) and (u._material.uv1_scale.x < 0.0)
	print("TEST_FACING_FLIP_STEP: after_move_right_again facing_right=%s uv1_scale_x=%.2f pass=%s" % [
		u._facing_right, u._material.uv1_scale.x, right_again_ok
	])

	if right_ok and left_ok and idle_ok and right_again_ok:
		print("TEST_FACING_FLIP_OK")
		quit(0)
	else:
		print("TEST_FACING_FLIP_FAIL right=%s left=%s idle=%s right_again=%s" % [right_ok, left_ok, idle_ok, right_again_ok])
		quit(1)
