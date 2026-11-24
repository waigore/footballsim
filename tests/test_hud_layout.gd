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
	# The stats card grew by the momentum footer (DR-20261125-02); its top-left
	# and width are unchanged, so every stats row sits where it did.
	assert_eq(HudLayout.stats_rect(vp), Rect2(1276.0, 24.0, 300.0, 132.0 + HudLayout.MOMENTUM_H), "desktop stats card moved")
	# Eight doors: the encyclopedia's league door and the menu door ride the bar.
	assert_eq(HudLayout.controls_rect(vp), Rect2(347.0, 834.0, 906.0, 46.0), "desktop control bar moved")
	assert_eq(HudLayout.commentary_rect(vp), Rect2(24.0, 774.0, 620.0, 52.0), "desktop ticker moved")
	assert_false(HudLayout.is_compact(vp), "the desktop viewport must not switch to phone metrics")

func test_the_momentum_footer_sits_inside_the_stats_card() -> void:
	# The meter is a reading, not a door: it must stay inside the card it is
	# part of, and the card must still clear the scoreboard and the bar.
	for vp in SIZES + COMPACT_SIZES:
		var card: Rect2 = HudLayout.stats_rect(vp)
		var meter: Rect2 = HudLayout.momentum_rect(vp)
		assert_true(card.encloses(meter), "the momentum meter left the stats card at %s" % vp)
		assert_gte(meter.size.x, 24.0, "the meter collapsed at %s" % vp)
		var rule_y: float = HudLayout.momentum_rule_y(vp)
		assert_lt(rule_y, meter.position.y, "the footer rule is below its meter at %s" % vp)
		assert_lte(card.end.y, vp.y, "the stats card runs off the bottom at %s" % vp)
		assert_gte(card.position.x, 0.0, "the stats card runs off the left at %s" % vp)

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
		var per: int = HudLayout.controls_per_row(vp)
		assert_gte(bar.size.x, float(per) * 44.0 + float(per - 1) * HudLayout.CONTROL_GAP, "the bar does not hold %d tappable doors at %s" % [per, vp])
		assert_gte(bar.size.y, float(HudLayout.control_rows(vp)) * 44.0, "the bar rows are too short to tap at %s" % vp)

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

func test_a_tablet_bar_counts_the_teams_door() -> void:
	# A wide touch viewport keeps the desktop metrics but still needs the door
	# on the bar, because the fixture panel's 20-unit row is not tappable.
	var vp := Vector2(1600, 900)
	assert_eq(HudLayout.control_count(vp), HudLayout.CONTROL_COUNT, "desktop count changed")
	assert_eq(HudLayout.control_count(vp, true), HudLayout.CONTROL_COUNT_TOUCH, "a touch bar is missing the teams door")
	assert_eq(HudLayout.controls_rect(vp), HudLayout.controls_rect(vp, false), "touch moved the desktop bar")
	assert_ne(HudLayout.controls_rect(vp, true), HudLayout.controls_rect(vp, false), "the touch bar did not grow")

func test_short_viewports_drop_stats_rows() -> void:
	var tall := Vector2(1000, 450)
	var short := Vector2(800, 360)
	assert_eq(HudLayout.stats_row_limit(tall), 5, "a tall phone should keep five rows")
	assert_eq(HudLayout.stats_row_limit(short), 3, "a short phone should drop to three rows")
	assert_gt(HudLayout.stats_rect(tall).size.y, HudLayout.stats_rect(short).size.y, "the short card did not shrink")
	assert_eq(HudLayout.stats_row_limit(Vector2(1600, 900)), 5, "desktop row count changed")

func test_pitch_fit_reads_the_touch_bar() -> void:
	# The seven-door bar is wider, so a coarse touch fit can differ from the
	# six-door one only by the band it measures; both must stay in range.
	var geo: Dictionary = HudLayout.pitch_fit(Vector2(2000, 900), 2.19, true)
	assert_between(float(geo["zoom"]), 3.0, 16.0, "touch fit out of range")
	# An absurdly small viewport must still yield a usable floor, not a zero.
	var tiny: Dictionary = HudLayout.pitch_fit(Vector2(640, 300), 1.0, true)
	assert_gte(float(tiny["zoom"]), 3.0, "the fit floor collapsed")

func test_the_scale_lands_a_phone_at_about_one_unit_per_point() -> void:
	# 1080 px tall at 420 dpi is 411 dp: the emulator this was tuned on.
	assert_almost_eq(HudLayout.scale_for(411.0), 2.19, 0.01, "a 411 dp screen did not land near 2.2")
	assert_almost_eq(HudLayout.scale_for(360.0), 2.5, 0.01, "a 360 dp screen did not land at the cap of the range")
	assert_almost_eq(HudLayout.scale_for(1080.0), 1.0, 0.01, "a desktop-height screen should not scale")
	assert_almost_eq(HudLayout.scale_for(0.0), 2.6, 0.01, "a zero height should clamp, not divide")
	assert_gte(HudLayout.scale_for(2400.0), 1.0, "the scale floor is below one unit per point")

# --------------------------------------------------- the whistle card ---

func test_the_whistle_card_keeps_its_shipped_desktop_numbers() -> void:
	# With no goals to list the card is the 190-unit scorecard every desktop
	# screenshot has (DR-20261125-04): same width, same centre, same height.
	var vp := Vector2(1600, 900)
	var m: Dictionary = HudLayout.break_metrics(vp, 0, 0)
	assert_eq(m["rect"], Rect2(570.0, 355.0, 460.0, 190.0), "the empty whistle card moved")
	assert_eq(int(m["rows"]), 0, "an empty sheet still asked for a goal row")
	# Three goals for the home side and one for the visitors: three rows, one per
	# line above the hint line.
	var m3: Dictionary = HudLayout.break_metrics(vp, 3, 1)
	assert_eq(int(m3["rows"]), 3, "the card did not grow a row per goal")
	assert_almost_eq(float(m3["rect"].size.y), 190.0 + 3.0 * 15.0, 0.01, "the card did not grow by its rows")

func test_the_whistle_card_clears_the_band_at_every_size() -> void:
	# The card grows with the score but must never cover the scoreboard, the
	# ticker or a control — a seven-goal game included, on both metrics.
	for vp in SIZES + COMPACT_SIZES:
		var board: Rect2 = HudLayout.scoreboard_rect(vp)
		var ticker: Rect2 = HudLayout.commentary_rect(vp)
		var bar: Rect2 = HudLayout.controls_rect(vp)
		for goals in [0, 1, 3, 7]:
			var m: Dictionary = HudLayout.break_metrics(vp, goals, goals)
			var card: Rect2 = m["rect"]
			var tag := "%s with %d goals" % [vp, goals]
			assert_gte(card.position.x, 0.0, "the whistle card runs off the left of %s" % tag)
			assert_lte(card.end.x, vp.x, "the whistle card runs off the right of %s" % tag)
			assert_lte(card.end.y, vp.y, "the whistle card runs off the bottom of %s" % tag)
			assert_lte(card.end.y, ticker.position.y, "the whistle card covers the ticker at %s" % tag)
			assert_lte(card.end.y, bar.position.y, "the whistle card covers a control at %s" % tag)
			assert_gte(card.position.y, 0.0, "the whistle card runs off the top at %s" % tag)
			# Only a card that still clears the scoreboard may sit under it: the
			# narrowest handset squeezes into whatever band is left.
			if card.size.y >= HudLayout.BREAK_BASE_H and not bool(m["compact"]):
				assert_gte(card.position.y, board.end.y, "the whistle card covers the scoreboard at %s" % tag)

func test_the_whistle_card_lists_what_fits_and_counts_the_rest() -> void:
	# The rows it draws are what it can hold: a phone lists two short entries per
	# row, a desktop one entry per column.
	var desktop := Vector2(1600, 900)
	assert_gte(int(HudLayout.break_metrics(desktop, 6, 6)["rows"]), 6, "desktop dropped rows it had room for")
	assert_eq(int(HudLayout.break_metrics(desktop, 6, 6)["per_row"]), 1, "desktop is not the two-column layout")
	var phone := Vector2(913, 411)
	var m: Dictionary = HudLayout.break_metrics(phone, 2, 2)
	assert_eq(int(m["per_row"]), 2, "a phone row is not two entries")
	assert_gte(int(m["rows"]), 2, "a phone dropped the rows it had room for")
	assert_lte(int(m["rows"]), int(m["capacity"]), "a phone drew more rows than fit")
	var squeezed := HudLayout.break_metrics(Vector2(640, 300), 4, 2)
	assert_eq(int(squeezed["rows"]), 0, "the narrowest handset drew goal rows it cannot fit")
	assert_lte(squeezed["rect"].end.y, HudLayout.commentary_rect(Vector2(640, 300)).position.y, "the squeezed card ran into the ticker")

