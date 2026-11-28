extends GdToolsTest


func _rows(date: String) -> Array:
	return LeagueWindowsView.rows(date)


func _state(windows: Array, touch := false) -> Dictionary:
	return {"name": "S", "day": "15/AUG/2026", "date": "2026-08-15", "matchday": 1,
		"played": 0, "total": 380, "plan": [], "table": [], "rules": LeagueRules.defaults(),
		"can_suggest": false, "complete": false, "advance_mode": "fixture_days",
		"touch": touch, "windows": windows}


func _chips(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if str(item.get("kind", "")) == "window_chip":
			out.append(item)
	return out


func test_the_hub_lays_one_chip_per_association() -> void:
	for date in ["2026-08-01", "2026-09-02", "2027-07-05"]:
		var rows := _rows(date)
		assert_eq(rows.size(), 4, "%s did not draw four associations" % date)
		var items: Array = LeagueSheet.new().hub_layout(Vector2(1600, 900), _state(rows))
		assert_eq(_chips(items).size(), 4, "%s laid %d chips" % [date, _chips(items).size()])


func test_an_open_association_says_a_deal_can_be_made_today() -> void:
	var rows := _rows("2026-08-01")
	var eng: Dictionary = {}
	for row in rows:
		if str((row as Dictionary)["country"]) == "ENG":
			eng = row
	assert_eq(LeagueWindowsView.chip_text(eng), "FA DEAL TODAY",
		"an open association does not say a deal can be made")
	for item in _chips(LeagueSheet.new().hub_layout(Vector2(1600, 900), _state(rows))):
		assert_true(bool(item["open"]), "an August chip reads closed")


func test_a_closed_association_names_the_day_it_opens() -> void:
	var rows := _rows("2026-09-02")
	var by_code := {}
	for row in rows:
		by_code[MarketWindows.code(str((row as Dictionary)["country"]))] = row
	assert_eq(LeagueWindowsView.chip_text(by_code["FA"]),
		"FA NO DEAL · OPENS 1/JAN/2027", "England's closed chip promises the wrong day")
	assert_eq(LeagueWindowsView.chip_text(by_code["RFEF"]), "RFEF NO DEAL · OPENS 2/JAN/2027",
		"Spain's closed chip promises the wrong day")
	for item in _chips(LeagueSheet.new().hub_layout(Vector2(1600, 900), _state(rows))):
		assert_false(bool(item["open"]), "a September chip reads open")


func test_the_band_sits_above_the_plan_and_never_holds_a_fixture_row() -> void:
	var fixture := {"id": "gw01-A-B", "matchday": 1, "kickoff": "2026-08-15",
		"kickoff_time": "15:00", "home_club_id": "A", "away_club_id": "B",
		"home_abbr": "HOM", "away_abbr": "AWY", "home_name": "Home", "away_name": "Away",
		"home_goals": 0, "away_goals": 0, "status": "pending", "watched": 0, "suggested": 0}
	for vp in [Vector2(1600, 900), Vector2(913, 411), Vector2(411, 914)]:
		var state := _state(_rows("2026-09-02"), true)
		state["plan"] = [fixture]
		var items: Array = LeagueSheet.new().hub_layout(vp, state)
		var band_bottom := 0.0
		for item in _chips(items):
			band_bottom = maxf(band_bottom, (item["rect"] as Rect2).end.y)
		assert_gt(band_bottom, 0.0, "no band laid out at %s" % vp)
		for item in items:
			if str(item.get("kind", "")) != "row":
				continue
			assert_gte((item["rect"] as Rect2).position.y, band_bottom,
				"a fixture row sits under the window band at %s" % vp)


func test_the_band_wraps_to_two_lines_on_a_narrow_sheet() -> void:
	var wide: Array = _chips(LeagueSheet.new().hub_layout(Vector2(1600, 900),
		_state(_rows("2026-08-01"))))
	var narrow: Array = _chips(LeagueSheet.new().hub_layout(Vector2(411, 914),
		_state(_rows("2026-08-01"))))
	var wide_lines := {}
	var narrow_lines := {}
	for item in wide:
		wide_lines[int((item["rect"] as Rect2).position.y)] = true
	for item in narrow:
		narrow_lines[int((item["rect"] as Rect2).position.y)] = true
	assert_eq(wide_lines.size(), 1, "the wide band wrapped to %d lines" % wide_lines.size())
	assert_eq(narrow_lines.size(), 2, "the narrow band laid %d lines" % narrow_lines.size())
	for item in narrow:
		assert_lte((item["rect"] as Rect2).end.x, 411.0 - 24.0 + 0.01,
			"a narrow chip runs off the sheet")


func test_every_chip_fits_its_rect_at_every_viewport() -> void:
	var bold: Font = UiChrome.fonts()["bold"]
	for vp in [Vector2(1600, 900), Vector2(913, 411), Vector2(600, 900), Vector2(411, 914)]:
		for item in _chips(LeagueSheet.new().hub_layout(vp, _state(_rows("2026-09-02"), true))):
			var rect: Rect2 = item["rect"]
			var text_w: float = UiChrome.text_width(bold, str(item["text"]), 8)
			assert_lte(text_w, rect.size.x - 4.0,
				"a chip overruns its rect at %s" % vp)


func test_a_surface_with_no_date_draws_no_band() -> void:
	assert_eq(LeagueWindowsView.rows("").size(), 0, "a blank date drew a board")
	var items: Array = LeagueSheet.new().hub_layout(Vector2(1600, 900), _state([]))
	assert_eq(_chips(items).size(), 0, "a boardless hub laid window chips")
	assert_eq(LeagueSheet.window_height(Vector2(1600, 900), []), 0.0,
		"an empty band still reserves height")


func test_the_isolated_run_reports_open_and_closed_without_the_deal_modules() -> void:
	var open_run := _verb_run("2026-08-01")
	assert_true(bool(open_run.get("ok", false)), "the isolated run refused an August date")
	assert_eq(int(open_run.get("open", -1)), 4, "August does not open all four associations")
	var shut_run := _verb_run("2026-09-02")
	assert_true(bool(shut_run.get("ok", false)), "the isolated run refused a September date")
	assert_eq(int(shut_run.get("open", -1)), 0, "2 September still opens an association")
	var fee: Dictionary = shut_run.get("fee", {})
	assert_false(bool(fee.get("ok", true)), "a fee deal signed outside a window")
	assert_eq(str(fee.get("reason", "")), "window_closed", "the isolated refusal has no reason")
	assert_eq(str(fee.get("opens_on", "")), "2027-01-01", "the isolated refusal loses the opening")


func _verb_run(date: String) -> Dictionary:
	var exe := OS.get_executable_path()
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/market_sim.gd", "--", "windows", "--date", date]
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	assert_eq(code, 0, "the isolated windows verb exited %d for %s" % [code, date])
	var text := "".join(out)
	var marker := text.find("market_sim windows: ")
	assert_gte(marker, 0, "the isolated verb printed no result for %s" % date)
	var json_text := text.substr(marker + "market_sim windows: ".length())
	var parsed: Variant = JSON.parse_string(json_text.strip_edges())
	assert_true(parsed is Dictionary, "the isolated verb printed no dictionary for %s" % date)
	return parsed if parsed is Dictionary else {}
