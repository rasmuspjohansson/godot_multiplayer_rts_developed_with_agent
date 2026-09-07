extends SceneTree
## Headless: SpatialHash radius queries must match brute force exactly.

const SpatialHash := preload("res://sim/SpatialHash.gd")

func _init():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var n := 3000
	var w := 3840.0
	var h := 2160.0
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var alive := PackedByteArray()
	xs.resize(n)
	zs.resize(n)
	alive.resize(n)
	for i in range(n):
		xs[i] = rng.randf_range(-10.0, w + 10.0)
		zs[i] = rng.randf_range(-10.0, h + 10.0)
		alive[i] = 1 if rng.randf() > 0.1 else 0
	var hash := SpatialHash.new()
	hash.setup(w, h, 40.0)
	var t0 := Time.get_ticks_usec()
	hash.build(xs, zs, alive, n)
	var build_us := Time.get_ticks_usec() - t0
	var failures := 0
	var queries := 300
	var t1 := Time.get_ticks_usec()
	for q in range(queries):
		var qx := rng.randf_range(0.0, w)
		var qz := rng.randf_range(0.0, h)
		var r := rng.randf_range(5.0, 150.0)
		var cnt := hash.query_radius(qx, qz, r, xs, zs)
		var got := {}
		for k in range(cnt):
			got[hash.scratch[k]] = true
		var expected := {}
		for i in range(n):
			if alive[i] == 0:
				continue
			var dx := xs[i] - qx
			var dz := zs[i] - qz
			if dx * dx + dz * dz <= r * r:
				expected[i] = true
		if got.size() != expected.size():
			failures += 1
			continue
		for id in expected.keys():
			if not got.has(id):
				failures += 1
				break
	var query_us := Time.get_ticks_usec() - t1
	# nearest() sanity
	var nid := hash.nearest(xs[0], zs[0], 1.0, xs, zs)
	if alive[0] != 0 and nid != 0:
		failures += 1
	print("TEST_SPATIAL_HASH: n=%d build_us=%d queries=%d query_avg_us=%.1f failures=%d" % [
		n, build_us, queries, float(query_us) / float(queries), failures
	])
	if failures == 0:
		print("TEST_SPATIAL_HASH_OK")
		quit(0)
	else:
		print("TEST_SPATIAL_HASH_FAIL")
		quit(1)
