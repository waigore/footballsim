extends GdToolsTest

## Sheet geometry without a renderer: every layout branch gets a state — empty
## hub, compact and wide, watched and suggested fixtures, no saves, a full load
## list, an event report, a roundup, a podium with and without a summary, and
## calendar months at the edges of the year.

func _fixture(i: int, watched: int = 0, suggested: int = 0) -> Dictionary:
	return {
		"id": "gw01-A%d-B%d" % [i, i], "matchday": 1, "kickoff": "2026-08-15",
		"kickoff_time": "15:00", "home_club_id": "A%d" % i, "away_club_id": "B%d" % i,
		"home_abbr": "HOM", "away_abbr": "AWY", "home_name": "Home %d" % i,
		"away_name": "Away %d" % i, "home_goals": 0, "away_goals": 0,
		"status": "pending", "watched": watched, "suggested": suggested,
	}

func _table(rows: int = 20) -> Array:
	var out: Array = []
	for i in range(rows):
		out.append({
			"position": i + 1, "club_id": "C%d" % i, "club_abbr": "C%d" % i,
			"club_name": "Club %d" % i, "played": 0, "won": 0, "drawn": 0, "lost": 0,
			"gf": 0, "ga": 0, "points": 0,
		})
	return out

func _state(plan: Array, table: Array, complete: bool = false) -> Dictionary:
	return {
		"name": "Sheet Season", "day": "SAT 15 AUG", "matchday": 1, "played": 0,
		"total": 380, "plan": plan, "table": table, "rules": LeagueRules.defaults(),
		"can_suggest": true, "complete": complete, "advance_mode": "fixture_days",
	}

func test_the_hub_lays_out_a_full_plan_wide_and_compact() -> void:
	var sheet := LeagueSheet.new()
	var plan: Array = []
	for i in range(10):
		plan.append(_fixture(i, i % 2, 0))
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var items: Array = sheet.hub_layout(vp, _state(plan, _table()))
		var kinds := {}
		for item in items:
			kinds[str(item["kind"])] = true
			var rect: Rect2 = item["rect"]
			assert_lte(rect.end.y, vp.y + 0.5, "a hub item runs off the bottom at %s" % vp)
			assert_gte(rect.size.y, 16.0, "a hub item is too short at %s" % vp)
		assert_true(kinds.has("row"), "the plan laid out no rows")
		assert_true(kinds.has("chip"), "the plan laid out no AUTO/WATCH chips")
		assert_true(kinds.has("button"), "the hub laid out no doors")

func test_the_hub_lays_out_an_empty_day_and_no_table() -> void:
	var sheet := LeagueSheet.new()
	var items: Array = sheet.hub_layout(Vector2(1600, 900), _state([], _table()))
	var rows := 0
	var tables := 0
	for item in items:
		if str(item["kind"]) == "row":
			rows += 1
		if str(item["kind"]) == "table_row":
			tables += 1
	assert_eq(rows, 0, "an empty day laid out fixture rows")
	assert_eq(tables, 20, "a wide hub lost its table")
	var compact: Array = sheet.hub_layout(Vector2(913, 411), _state([], _table()))
	for item in compact:
		assert_eq(str(item["kind"]) != "table_row", true, "a phone hub tried to draw the table")

func test_the_wizard_lays_out_both_choices_and_the_doors() -> void:
	var sheet := LeagueSheet.new()
	for mode in ["real", "generated"]:
		for advance in ["fixture_days", "every_day"]:
			var items: Array = sheet.wizard_layout(Vector2(1280, 720),
				{"name": "Save", "calendar_mode": mode, "advance_mode": advance, "error": ""})
			var chosen := 0
			for item in items:
				if str(item["kind"]) == "choice" and bool(item["selected"]):
					chosen += 1
			assert_eq(chosen, 2, "one choice per group should be selected")
			assert_eq(items.size(), 7, "the wizard is missing a control")

func test_the_load_list_lays_out_zero_and_many_saves() -> void:
	var sheet := LeagueSheet.new()
	var empty: Array = sheet.load_layout(Vector2(1280, 720), {"saves": []})
	assert_eq(empty.size(), 1, "an empty load list should only have BACK")
	var saves: Array = []
	for i in range(9):
		saves.append({"slug": "s%d" % i, "name": "Save %d" % i, "status": "in_progress",
			"current_date": "2026-09-0%d" % (i + 1), "matchday": i + 1, "path": "",
			"modified": i})
	var items: Array = sheet.load_layout(Vector2(1280, 720), {"saves": saves})
	var open_doors := 0
	var delete_doors := 0
	for item in items:
		if str(item["kind"]) == "save_row":
			open_doors += 1
		if str(item["kind"]) == "delete":
			delete_doors += 1
	assert_eq(open_doors, 7, "the load list should show seven rows")
	assert_eq(delete_doors, 7, "every shown save needs a delete door")

## The compact column set (#, club, P, GD, PTS) has to fit inside the row at
## every width the handheld overlay scale can produce: the numbers ride one rail
## measured from the row's own right edge, and the club column keeps whatever is
## left, so a long name is shortened instead of painted over P and GD.
func test_the_table_columns_fit_a_phone_and_a_desktop_sheet() -> void:
	for vp in [Vector2(1600, 900), Vector2(913, 411), Vector2(873, 393), Vector2(360, 780), Vector2(320, 480)]:
		var row := Rect2(24.0, 80.0, vp.x - 48.0, 18.0)
		var cols: Dictionary = LeagueColumns.of(row)
		assert_gt(float(cols["club_x"]), float(cols["pos_x"]), "# and CLUB overlap at %s" % vp)
		assert_lte(float(cols["club_x"]) + float(cols["club_w"]), float(cols["p_r"]) - LeagueColumns.NUM_GAP + 0.01,
			"the club name may run into P at %s" % vp)
		assert_lt(float(cols["p_r"]), float(cols["gd_r"]), "P and GD share an edge at %s" % vp)
		assert_lt(float(cols["gd_r"]), float(cols["pts_r"]), "GD and PTS share an edge at %s" % vp)
		assert_lte(float(cols["pts_r"]), row.end.x, "PTS is drawn outside the row at %s" % vp)
		assert_gte(float(cols["club_w"]), 100.0, "the club column is unreadable at %s" % vp)

## Columns must track the sheet, not sit on desktop-only offsets: a phone-shrunk
## row moves the whole rail left and gives the slack to the club column.
func test_the_number_rail_follows_the_row_width() -> void:
	var wide: Dictionary = LeagueColumns.of(Rect2(24.0, 80.0, 1552.0, 20.0))
	var phone: Dictionary = LeagueColumns.of(Rect2(24.0, 80.0, 825.0, 20.0))
	assert_almost_eq(float(wide["pts_r"]) - float(phone["pts_r"]), 727.0, 0.01,
		"PTS did not track the sheet width")
	assert_almost_eq(float(wide["club_w"]) - float(phone["club_w"]), 727.0, 0.01,
		"the club column did not take the slack the numbers gave up")

## A name wider than its column must be shortened, not painted over P and GD.
## Headless text metrics are real (a dummy server would measure every string as
## zero width and this case would pass without testing anything).
func test_a_long_club_name_is_shortened_instead_of_overlapping() -> void:
	var font: Font = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	var longest := "Wolverhampton Wanderers"
	assert_gt(font.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 60.0,
		"the probe font measured every string as zero width")
	var shown := LeagueColumns.fit_name(longest, font, 12, 60.0)
	assert_ne(shown, longest, "a name wider than its column was drawn whole")
	assert_true(shown.ends_with("…"), "a shortened name needs an ellipsis")
	assert_lte(font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 60.0,
		"the shortened name still overflows its column")
	assert_eq(LeagueColumns.fit_name(longest, font, 12, 600.0), longest,
		"a name that fits was shortened anyway")
	assert_eq(LeagueColumns.fit_name(longest, null, 12, 60.0), longest,
		"a missing font must not drop the name")

func test_the_table_and_calendar_lay_out_at_both_sizes() -> void:
	var book := LeagueBook.new()
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var table: Array = book.table_layout(vp, {"table": _table(), "rules": LeagueRules.defaults()})
		var rows := 0
		var bottom := 0.0
		for item in table:
			if str(item["kind"]) == "table_row":
				rows += 1
				var rect: Rect2 = item["rect"]
				bottom = maxf(bottom, rect.end.y)
				assert_gte(rect.size.y, 20.0, "a table row lost its readable height at %s" % vp)
			elif str(item["id"]) == "back":
				assert_true(bool(item.get("pinned", false)), "BACK must stay out of the scroll")
		assert_eq(rows, 20, "the table screen lost rows")
		if vp.y < 620.0:
			assert_gt(bottom, vp.y - LeagueSheet.BAR_H, "a phone table must overflow so the body scrolls")
		else:
			assert_lte(bottom, vp.y - LeagueSheet.BAR_H, "a desktop table should fit in one window")
		var calendar: Array = book.calendar_layout(vp, {
			"month": "2026-10", "day": "2026-10-17",
			"days": {"2026-10-17": {"n": 10, "played": 4}},
			"day_fixtures": [_fixture(1), _fixture(2)],
		})
		var cells := 0
		var matches := 0
		for item in calendar:
			if str(item["kind"]) == "cell":
				cells += 1
			if str(item["kind"]) == "fixture":
				matches += 1
		assert_eq(cells, 31, "October should have 31 cells")
		assert_eq(matches, 2, "the day lost its fixtures")

func test_every_phone_sheet_overflows_into_the_scroll_window() -> void:
	var sheet := LeagueSheet.new()
	var book := LeagueBook.new()
	var vp := Vector2(913, 411)
	var window := vp.y - LeagueSheet.BAR_H
	var plan: Array = []
	for i in range(10):
		plan.append(_fixture(i))
	assert_gt(_bottom(sheet.hub_layout(vp, _state(plan, _table()))), window,
		"ten phone fixtures should scroll instead of being dropped")
	var saves: Array = []
	for i in range(7):
		saves.append({"slug": "s%d" % i, "name": "Save %d" % i, "status": "in_progress",
			"current_date": "2026-09-0%d" % (i + 1), "matchday": i + 1, "path": "", "modified": i})
	assert_gt(_bottom(sheet.load_layout(vp, {"saves": saves})), window,
		"a full load list should scroll on a phone")
	var events: Array = []
	for i in range(14):
		events.append({"minute": i, "kind": "goal", "player_name": "P%d" % i})
	assert_gt(_bottom(book.report_layout(vp, {"fixture": _fixture(1), "events": events, "day": "x"})),
		window, "a long report should scroll on a phone")
	var hub: Array = sheet.hub_layout(vp, _state(plan, _table()))
	for item in hub:
		if str(item["kind"]) == "button":
			assert_true(bool(item.get("pinned", false)), "a hub door was left to scroll away")

func test_a_goal_with_a_clip_gets_a_thumb_sized_play_door() -> void:
	var book := LeagueBook.new()
	var events := [
		{"minute": 12, "kind": "goal", "player_name": "A. Striker"},
		{"minute": 30, "kind": "yellow", "player_name": "C. Pivot"},
		{"minute": 61, "kind": "goal", "player_name": "B. Winger"},
	]
	var clips := [
		{"fixture_id": "gw01-A1-B1", "goal_index": 0, "minute": 12, "commentary": "GOAL! A. Striker scores."},
	]
	var vp := Vector2(1280, 720)
	var items: Array = book.report_layout(vp, {
		"fixture": _fixture(1), "events": events, "highlights": clips, "day": "2026-08-15",
	})
	var doors := {}
	var rows := {}
	for item in items:
		if str(item["kind"]) == "play":
			doors[str(item["id"])] = item["rect"]
		elif str(item["kind"]) == "event":
			rows[str(item["event"]["player_name"])] = item
	assert_eq(doors.size(), 1, "a goal without a clip was given a play door")
	assert_true(doors.has("goal:0"), "the play door is not on the first goal")
	var rect: Rect2 = doors["goal:0"]
	assert_gte(rect.size.x, 24.0, "the play door is too narrow for a thumb")
	assert_gte(rect.size.y, 24.0, "the play door is too short for a thumb")
	assert_true(rect.position.x + rect.size.x <= vp.x - 20.0, "the play door runs off the sheet")
	# The commentary line needs the room the door does not take.
	var goal_row: Dictionary = rows["A. Striker"]
	var other_row: Dictionary = rows["C. Pivot"]
	assert_gt((goal_row["rect"] as Rect2).size.y, (other_row["rect"] as Rect2).size.y,
		"the goal row is no taller than a plain event")
	assert_false(str(goal_row.get("clip", {}).get("commentary", "")) == "",
		"the goal row did not carry its commentary")
	assert_true((other_row.get("clip", {}) as Dictionary).is_empty(),
		"a card row was given a clip")
	assert_true((goal_row["rect"] as Rect2).encloses(rect), "the play door sits outside its goal row")

func test_a_roundup_offers_no_play_doors() -> void:
	var book := LeagueBook.new()
	var items: Array = book.report_layout(Vector2(1280, 720), {
		"roundup": [{"fixture": _fixture(1), "events": [
			{"minute": 12, "kind": "goal", "player_name": "A. Striker"}], "score": [1, 0], "played": true}],
	})
	for item in items:
		assert_ne(str(item["kind"]), "play", "a roundup row offered a play door")

func _bottom(items: Array) -> float:
	var bottom := 0.0
	for item in items:
		if not bool(item.get("pinned", false)):
			bottom = maxf(bottom, (item["rect"] as Rect2).end.y)
	return bottom

func test_the_report_lays_out_events_and_a_roundup() -> void:
	var book := LeagueBook.new()
	var events := [
		{"minute": 12, "kind": "goal", "player_name": "A. Striker"},
		{"minute": 12, "kind": "assist", "player_name": "B. Winger"},
		{"minute": 30, "kind": "yellow", "player_name": "C. Pivot"},
		{"minute": 77, "kind": "red", "player_name": "D. Back"},
	]
	var single: Array = book.report_layout(Vector2(1280, 720), {
		"fixture": _fixture(1), "events": events, "day": "2026-08-15",
	})
	assert_eq(single.size(), 5, "the report lost an event or the back door")
	var roundup: Array = book.report_layout(Vector2(1280, 720), {
		"roundup": [{"fixture": _fixture(1), "events": events, "score": [1, 0], "played": true}],
	})
	assert_eq(roundup.size(), 2, "the roundup lost its row or the back door")

func test_the_podium_lays_out_with_and_without_a_summary() -> void:
	var book := LeagueBook.new()
	var empty: Array = book.podium_layout(Vector2(1280, 720), {"summary": {}})
	var doors := 0
	var extent := 0
	for item in empty:
		if str(item["kind"]) == "button":
			doors += 1
		elif str(item["kind"]) == "extent":
			extent += 1
	assert_eq(doors, 2, "the podium lost its doors")
	assert_eq(extent, 1, "the podium lost its measured summary height")
	var summary := {
		"champion": {"club": "Arsenal", "club_id": "ARS", "points": 90},
		"runner_up": {"club": "Liverpool", "club_id": "LIV", "points": 88},
		"europe": [], "relegated": [], "places": LeagueRules.places(LeagueRules.defaults()),
		"top_scorers": [{"name": "A. Striker", "goals": 24}],
	}
	assert_false(summary.is_empty(), "a podium summary should be usable")
	assert_gt(_bottom(book.podium_layout(Vector2(1280, 720), {"summary": summary})), 0.0,
		"a podium with a summary has no height for the scroll window")

func test_month_helpers_walk_the_year() -> void:
	assert_eq(LeagueBook.shift_month("2026-01", -1), "2025-12", "January did not step back a year")
	assert_eq(LeagueBook.shift_month("2026-12", 1), "2027-01", "December did not step forward a year")
	assert_eq(LeagueBook.month_label("2026-08"), "AUGUST 2026", "the month label is wrong")
	assert_eq(LeagueBook.month_days("2026-02"), 28, "February 2026 is not 28 days")
	assert_eq(LeagueBook.month_days("2028-02"), 29, "February 2028 is not a leap month")
	assert_eq(LeagueBook.month_days("2026-04"), 30, "April is not 30 days")
	assert_eq(LeagueBook.parse_month("bad"), LeagueBook.parse_month("bad"), "a bad month is unstable")

func test_zone_colours_cover_every_band() -> void:
	for band in ["ucl", "uel", "uecl", "relegation", ""]:
		var colour := LeagueSheet.zone_color(band)
		assert_true(colour.a > 0.0, "band %s has no colour" % band)
	assert_eq(LeagueRules.zone_label(""), "", "a neutral row has a label")
