extends GdToolsTest

## Type density (issue #337): glyph atlases are rasterized at the density they
## are drawn at. A CanvasLayer transform is not part of a CanvasItem's global
## transform, so without this the font rasterizer rasters at the window's stretch
## alone and the GPU magnifies every glyph — the soft type on a high-DPI phone.

const REF := Vector2i(1600, 900)

func test_the_multiplier_is_the_window_stretch_times_the_layer_scale() -> void:
	# A Galaxy A56: 1080 px at 411 dp reads the overlay at 2.19, and the window
	# stretch of a 2400-wide screen over the 2000-unit design space is 1.2.
	assert_almost_eq(TypeDensity.multiplier(1.2, 2.19), 2.628, 0.001,
		"the phone overlay density is not the stretch times the layer")
	assert_almost_eq(TypeDensity.multiplier(1.0, 1.25), 1.25, 0.001,
		"a desktop sheet lost its own scale")
	assert_almost_eq(TypeDensity.multiplier(1.6, 1.6), 2.56, 0.001,
		"a 1440p window's sheet density is wrong")

func test_a_layer_at_or_below_one_unit_never_thins_the_type() -> void:
	# The desktop match HUD draws at 1.0 in a 1.0-stretch window: the stock path,
	# which must stay byte-for-byte what shipped. A window that stretches the
	# drawing *down* must not rasterize below one device pixel per unit either.
	assert_almost_eq(TypeDensity.multiplier(1.0, 1.0), 1.0, 0.001, "the desktop HUD moved off the stock path")
	assert_almost_eq(TypeDensity.multiplier(0.5, 1.0), 1.0, 0.001, "a shrinking window thinned the type")
	assert_almost_eq(TypeDensity.multiplier(1.0, 0.75), 1.0, 0.001, "a shrinking layer thinned the type")

func test_the_density_is_capped() -> void:
	# A 4K phone would ask for ~4x; past the cap the atlas memory buys no
	# legibility, so the factor stops there.
	assert_almost_eq(TypeDensity.multiplier(4.0, 2.6), TypeDensity.MAX, 0.001, "the cap did not hold")
	assert_gte(TypeDensity.MAX, 4.0, "the cap must still cover a 4K phone")

func test_a_headless_run_uses_the_stock_path() -> void:
	# Headless has no window: there is nothing to measure a stretch from, and the
	# suites must not read a stale density left by some other test.
	var host := Node2D.new()
	add_child(host)
	var view: Viewport = host.get_viewport()
	assert_almost_eq(TypeDensity.window_stretch(view), 1.0, 0.001, "a headless run invented a stretch")

func test_applying_the_density_moves_and_clears_the_viewport_override() -> void:
	var host := Node2D.new()
	add_child(host)
	var view: Viewport = host.get_viewport()
	var before: float = view.oversampling_override
	# A window with no size reports a stretch of 1.0, so the multiplier is capped
	# at the layer: the override is set to it and cleared again at 1.0.
	var applied: float = TypeDensity.apply(view, TypeDensity.MAX)
	assert_almost_eq(applied, TypeDensity.MAX, 0.001, "the applied factor is not the multiplier")
	assert_almost_eq(view.oversampling_override, TypeDensity.MAX, 0.001, "the viewport kept its old density")
	TypeDensity.apply(view, 1.0)
	assert_almost_eq(view.oversampling_override, 0.0, 0.001, "the override was not cleared at the stock density")
	view.oversampling_override = before
	host.queue_free()

## Glyph metrics must not move with the density: the overlay centres every
## caption on `font.get_string_size(...)`, so a drifting advance would shift
## every centred label off its panel.
func test_the_density_does_not_move_glyph_metrics() -> void:
	var host := Node2D.new()
	add_child(host)
	var view: Viewport = host.get_viewport()
	var font: Font = load("res://fonts/BarlowCondensed-Medium.ttf")
	var before: float = view.oversampling_override
	var samples := ["Brighton & Hove Albion", "MCI 44' HAALAND", "WWWWWWWWWW", "iiiiiiiiii"]
	var sizes := [9, 11, 15, 20, 30, 48]
	var measured := []
	for density in [1.0, 2.628]:
		view.oversampling_override = density
		var row := []
		for s in samples:
			for size in sizes:
				row.append(font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size))
		measured.append(row)
	assert_eq(measured[0], measured[1], "the atlas density moved a glyph's advance")
	view.oversampling_override = before
	host.queue_free()
