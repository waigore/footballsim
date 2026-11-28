extends GdToolsTest


func test_bake_fills_the_requested_canvas() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var tex := PitchStadium.bake(80, 60, rng)
	assert_not_null(tex, "bake returned no texture")
	var img := tex.get_image()
	assert_not_null(img, "bake texture had no image")
	assert_eq(img.get_width(), 80, "bake width drifted")
	assert_eq(img.get_height(), 60, "bake height drifted")
	assert_eq(img.get_pixel(40, 30).a, 1.0, "baked stadium must be opaque")


func test_bake_is_seed_stable() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 11
	b.seed = 11
	var left := PitchStadium.bake(40, 30, a).get_image()
	var right := PitchStadium.bake(40, 30, b).get_image()
	assert_eq(left.get_pixel(20, 15), right.get_pixel(20, 15), "same seed must paint the same seat")


func test_world_rect_matches_the_pitch_apron() -> void:
	assert_eq(PitchStadium.WORLD, Rect2(-36, -36, 182, 132), "stadium world drifted from the pitch apron")
