extends GdToolsTest

## Broadcast chrome: the commentary ticker sits above the control bar, so it
## must never cover a button and must stay inside the viewport at every size a
## desktop or handheld build can present. Handheld sizes are checked in design
## units — the space main.gd hands the overlay after scaling it up.

const SIZES := [
	Vector2(1600, 900),
	Vector2(1920, 1080),
	Vector2(1280, 720),
	Vector2(1024, 600),
	Vector2(720, 1280),
	Vector2(2560, 1440),
]

## Design viewports a phone presents once the overlay is scaled: 2400x1080 at
## 420 dpi, a 20:9 and a 16:9 handset, and the narrowest landscape we support.
const COMPACT_SIZES := [
	Vector2(913, 411),
	Vector2(1000, 450),
	Vector2(800, 360),
	Vector2(640, 300),
]

func test_ticker_never_covers_the_control_bar() -> void:
	for vp in SIZES:
		var panel: Rect2 = HudLayout.commentary_rect(vp)
		var bar: Rect2 = HudLayout.controls_rect(vp)
		assert_false(panel.intersects(bar), "the commentary panel covers a control at %s" % vp)
		assert_false(bar.intersects(panel), "a control covers the commentary panel at %s" % vp)

func test_bottom_strip_stays_inside_the_viewport() -> void:
	for vp in SIZES:
		var panel: Rect2 = HudLayout.commentary_rect(vp)
		var bar: Rect2 = HudLayout.controls_rect(vp)
		assert_gte(panel.position.x, 0.0, "panel starts off-screen at %s" % vp)
		assert_lte(panel.position.x + panel.size.x, vp.x, "panel runs off the right edge at %s" % vp)
		assert_lte(panel.position.y + panel.size.y, vp.y, "panel runs off the bottom at %s" % vp)
		assert_gte(bar.position.x, 0.0, "control bar starts off-screen at %s" % vp)
		assert_lte(bar.position.x + bar.size.x, vp.x, "control bar runs off the right edge at %s" % vp)

func test_desktop_metrics_are_the_shipped_ones() -> void:
	# The broadcast layout at 1600x900 must not drift: the overlay is scaled on
	# handhelds only, and these are the numbers every desktop screenshot has.
	var vp := Vector2(1600, 900)
	assert_eq(HudLayout.scoreboard_rect(vp), Rect2(480.0, 14.0, 640.0, 86.0), "desktop scoreboard moved")
	assert_eq(HudLayout.stats_rect(vp), Rect2(1276.0, 24.0, 300.0, 132.0), "desktop stats card moved")
	assert_eq(HudLayout.controls_rect(vp), Rect2(461.0, 834.0, 678.0, 46.0), "desktop control bar moved")
	assert_eq(HudLayout.commentary_rect(vp), Rect2(24.0, 774.0, 620.0, 52.0), "desktop ticker moved")
	assert_false(HudLayout.is_compact(vp), "the desktop viewport must not switch to phone metrics")

func test_compact_metrics_fit_the_design_viewport() -> void:
	for vp in COMPACT_SIZES:
		assert_true(HudLayout.is_compact(vp), "%s should use phone metrics" % vp)
		var board: Rect2 = HudLayout.scoreboard_rect(vp)
		var stats: Rect2 = HudLayout.stats_rect(vp)
		var bar: Rect2 = HudLayout.controls_rect(vp)
		var ticker: Rect2 = HudLayout.commentary_rect(vp)
		assert_false(board.intersects(stats), "scoreboard and stats collide at %s" % vp)
		assert_gte(stats.position.x, board.end.x, "stats card overlaps the scoreboard at %s" % vp)
		for r in [board, stats, bar, ticker]:
			assert_gte(r.position.x, 0.0, "panel starts off-screen at %s" % vp)
			assert_lte(r.end.x, vp.x, "panel runs off the right edge at %s" % vp)
			assert_lte(r.end.y, vp.y, "panel runs off the bottom at %s" % vp)
		assert_false(ticker.intersects(bar), "ticker covers a control at %s" % vp)
		# A phone bar carries the extra teams door, and every door is a tap
		# target: 44 design units is 44 dp once the layer is scaled back up.
		assert_eq(HudLayout.control_count(vp), HudLayout.CONTROL_COUNT_TOUCH, "phone bar is missing the teams door")
		var w: float = HudLayout.control_width(vp)
		assert_gte(w, 44.0, "control at %s is %.1f wide — too small to tap" % [vp, w])
		assert_gte(bar.size.y, 44.0, "control bar at %s is too short to tap" % vp)
		assert_gte(bar.size.x, 7.0 * 44.0 + 6.0 * HudLayout.CONTROL_GAP, "the bar does not hold seven tappable doors at %s" % vp)

func test_pitch_band_stays_between_the_full_width_bars() -> void:
	for vp in COMPACT_SIZES:
		var band: Rect2 = HudLayout.pitch_band(vp)
		assert_gte(band.position.y, HudLayout.scoreboard_rect(vp).end.y, "band starts under the scoreboard at %s" % vp)
		assert_lte(band.end.y, HudLayout.controls_rect(vp).position.y, "band runs into the control bar at %s" % vp)
		assert_gte(band.size.y, vp.y * 0.3, "band is only %.0f of %.0f tall at %s" % [band.size.y, vp.y, vp])

func test_pitch_fit_leaves_desktop_framing_alone() -> void:
	var vp := Vector2(1600, 900)
	var legacy: float = minf(vp.y / 102.0, (vp.x - 40.0) / 135.0)
	var geo: Dictionary = HudLayout.pitch_fit(vp, 1.0)
	assert_eq(float(geo["zoom"]), legacy, "desktop zoom changed")
	assert_eq(float(geo["offset"]), 0.0, "desktop pitch was shifted")

func test_pitch_fit_centres_the_pitch_on_a_phone() -> void:
	# Logical 2000x900 with a 2.19x overlay: the band is what limits the zoom,
	# and the pitch centre must move so the pitch sits inside it.
	var vp := Vector2(2000, 900)
	var scale := 2.19
	var geo: Dictionary = HudLayout.pitch_fit(vp, scale)
	var band: Rect2 = HudLayout.pitch_band(vp / scale)
	var pitch_px: float = 68.0 * float(geo["zoom"])
	assert_lte(pitch_px, band.size.y * scale, "the pitch is taller than the band")
	assert_lt(float(geo["zoom"]), minf(vp.y / 102.0, (vp.x - 40.0) / 135.0), "the band never bit")
	assert_ne(float(geo["offset"]), 0.0, "the pitch was not centred in its band")
	var centre: float = vp.y * 0.5 + float(geo["offset"]) * float(geo["zoom"])
	assert_almost_eq(centre, (band.position.y + band.size.y * 0.5) * scale, 1.0, "pitch centre missed the band centre")

func test_overlay_scale_is_a_sane_multiplier() -> void:
	# Headless has no touchscreen, so this is the desktop branch; the handheld
	# branch is bounded and monotonic in device density.
	var s: float = HudLayout.overlay_scale()
	assert_between(s, 1.0, 2.6, "overlay scale out of range")
