extends GdToolsTest


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
			"home_played": 0, "home_won": 0, "home_drawn": 0, "home_lost": 0,
			"home_gf": 0, "home_ga": 0, "away_played": 0, "away_won": 0,
			"away_drawn": 0, "away_lost": 0, "away_gf": 0, "away_ga": 0,
		})
	return out

func _state(plan: Array, table: Array, complete: bool = false) -> Dictionary:
	return {
		"name": "Sheet Season", "day": "15/AUG/2026", "date": "2026-08-15", "matchday": 1,
		"played": 0, "total": 380, "plan": plan, "table": table, "rules": LeagueRules.defaults(),
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


func test_a_played_fixture_loses_its_watch_chip() -> void:
	var sheet := LeagueSheet.new()
	var played := _fixture(1, 1)
	played["status"] = "played"
	played["home_goals"] = 2
	played["away_goals"] = 1
	var pending := _fixture(2, 1, 0)
	var plan := [played, pending]
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var items: Array = sheet.hub_layout(vp, _state(plan, _table()))
		var chips: Array = []
		var rows := 0
		for item in items:
			if str(item["kind"]) == "row":
				rows += 1
			if str(item["kind"]) == "chip" and str(item["id"]).begins_with("toggle:"):
				chips.append(str(item["id"]))
		assert_eq(rows, 2, "a played row left the hub at %s" % vp)
		assert_false(chips.has("toggle:" + str(played["id"])), "a played row offers a watch chip at %s" % vp)
		assert_true(chips.has("toggle:" + str(pending["id"])), "a pending row lost its watch chip at %s" % vp)

	assert_false(LeagueChrome.watch_pending([played]), "a played watch still claims CONTINUE opens it")
	assert_true(LeagueChrome.watch_pending(plan), "an unplayed watch lost its CONTINUE caption")
	assert_false(LeagueChrome.watch_pending([]), "an empty day claims a pending watch")

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
	assert_eq(tables, 0, "the hub drew a side table")
	var compact: Array = sheet.hub_layout(Vector2(913, 411), _state([], _table()))
	for item in compact:
		assert_eq(str(item["kind"]) != "table_row", true, "a phone hub tried to draw the table")


func test_the_hub_has_no_side_table() -> void:
	var sheet := LeagueSheet.new()
	for vp in [Vector2(760, 640), Vector2(1280, 720), Vector2(1600, 900)]:
		for item in sheet.hub_layout(vp, _state([], _table())):
			assert_eq(str(item["kind"]) != "table_row", true,
				"the hub drew a side table at %s" % vp)

func test_the_wizard_lays_out_both_choices_and_the_doors() -> void:
	var sheet := LeagueStartSheet.new()
	for mode in ["real", "generated"]:
		for advance in ["fixture_days", "every_day"]:
			var items: Array = sheet.wizard_layout(Vector2(1280, 720),
				{"name": "Save", "calendar_mode": mode, "advance_mode": advance, "error": ""})
			var chosen := 0
			for item in items:
				if str(item["kind"]) == "choice" and bool(item["selected"]):
					chosen += 1


			assert_eq(chosen, 3, "one choice per group should be selected")


			assert_eq(items.size(), 19, "the wizard is missing a control")


func test_the_wizard_cascades_a_country_chain() -> void:
	var sheet := LeagueStartSheet.new()
	var items: Array = sheet.wizard_layout(Vector2(1280, 720),
		{"name": "Save", "calendar_mode": "real", "advance_mode": "fixture_days",
		"competitions": ["PL"]})
	var ids: Array = []
	var countries: Array = []
	for item in items:
		if str(item["id"]).begins_with("wleague:"):
			ids.append(str(item["id"]))
		elif str(item["kind"]) == "country":
			countries.append(str(item["label"]))
	assert_eq(ids, ["wleague:PL", "wleague:CH", "wleague:L1", "wleague:L2", "wleague:NL",
		"wleague:LL", "wleague:BL", "wleague:BL2"], "the wizard did not list every league")
	assert_eq(countries, ["ENGLAND", "SPAIN", "GERMANY"], "the country headers are wrong")
	var screen := FakeWizard.new()

	screen.wizard = {"competitions": ["PL"]}
	LeagueWizardActions.toggle_league(screen, "L2")
	assert_eq(screen.wizard["competitions"], ["PL", "CH", "L1", "L2"],
		"League Two did not bring the tiers above it")
	LeagueWizardActions.toggle_league(screen, "NL")
	assert_eq(screen.wizard["competitions"], ["PL", "CH", "L1", "L2", "NL"],
		"the National League did not complete the pyramid")

	LeagueWizardActions.toggle_league(screen, "CH")
	assert_eq(screen.wizard["competitions"], ["PL"], "the English pyramid did not cascade off")

	LeagueWizardActions.toggle_league(screen, "PL")
	assert_eq(screen.wizard["competitions"], ["PL"], "the wizard emptied itself")

	screen.wizard = {"competitions": ["PL"]}
	LeagueWizardActions.toggle_league(screen, "BL2")
	assert_eq(screen.wizard["competitions"], ["PL", "BL", "BL2"],
		"2. Bundesliga did not bring the Bundesliga")
	LeagueWizardActions.toggle_league(screen, "BL")
	assert_eq(screen.wizard["competitions"], ["PL"], "the German pair did not cascade off")
	screen.wizard = {"competitions": ["BL", "BL2"]}
	LeagueWizardActions.toggle_league(screen, "BL")
	assert_eq(screen.wizard["competitions"], ["BL", "BL2"], "the wizard emptied itself")
func test_the_save_keeps_the_leagues_in_the_published_order() -> void:
	var season := LeagueSeason.create("Order", "real", "every_day", 240, ["BL2", "LL", "BL", "PL"])
	assert_not_null(season, "the four-league save did not build")
	assert_eq(season.save.competition_ids(), ["PL", "LL", "BL", "BL2"],
		"the save kept the wizard's pick order instead of the fixture order")
	season.close()

class FakeWizard extends RefCounted:
	var wizard: Dictionary = {}
	func refresh() -> void:
		pass

func test_the_load_list_lays_out_zero_and_many_saves() -> void:
	var sheet := LeagueStartSheet.new()
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
	var last_row := Rect2()
	for item in items:
		if str(item["kind"]) == "save_row":
			open_doors += 1
			last_row = item["rect"]
		if str(item["kind"]) == "delete":
			delete_doors += 1


	assert_eq(open_doors, 9, "the load list dropped a save")
	assert_eq(delete_doors, 9, "every save needs a delete door")
	assert_gte(last_row.end.y, LeagueChrome.HEADER + 26.0 + 46.0 * 8.0,
		"the ninth save was laid over an earlier row")


func test_a_phone_load_row_and_its_delete_door_are_finger_sized() -> void:
	var sheet := LeagueStartSheet.new()
	var saves: Array = [{"slug": "s0", "name": "Save 0", "status": "in_progress",
		"current_date": "2026-09-01", "matchday": 1, "path": "", "modified": 0}]
	var desk: Array = sheet.load_layout(Vector2(913, 411), {"saves": saves})
	var phone: Array = sheet.load_layout(Vector2(913, 411), {"saves": saves, "touch": true})
	var desk_row: Rect2 = desk[0]["rect"]
	var phone_row: Rect2 = phone[0]["rect"]
	var phone_delete: Rect2 = phone[1]["rect"]
	assert_lt(desk_row.size.y, UiChrome.TAP_H, "the desktop row grew to a finger's pitch")
	assert_gte(phone_row.size.y, UiChrome.TAP_H, "the save row is under a finger")
	assert_gte(phone_delete.size.y, UiChrome.TAP_H, "the delete door is under a finger")
	assert_true(phone_row.encloses(phone_delete), "the delete door left its row")
	assert_false(phone_row.intersects(phone[2]["rect"] as Rect2),
		"two save rows overlap, so one press answers two lanes")
	assert_gte((phone[phone.size() - 1]["rect"] as Rect2).size.y, UiChrome.TAP_H,
		"the load list's BACK is under a finger")


func test_a_phone_hub_lays_every_row_and_door_for_a_finger() -> void:
	var sheet := LeagueSheet.new()
	var plan: Array = []
	for i in range(6):
		plan.append(_fixture(i, i % 2, 0))
	var vp := Vector2(913.0, 411.0)
	var wide: Array = sheet.hub_layout(vp, _state(plan, _table()))
	var state := _state(plan, _table())
	state["touch"] = true
	var narrow: Array = sheet.hub_layout(vp, state)
	assert_eq(_item_rect(wide, "fixture:gw01-A0-B0").size.y, LeagueChrome.ROW_H,
		"the desktop row left its own pitch")
	for item in narrow:
		if str(item["kind"]) == "row" or str(item["kind"]) == "chip":
			assert_gte((item["rect"] as Rect2).size.y, UiChrome.TAP_H,
				"%s is under a finger at %s" % [item["id"], vp])
	var first := _item_rect(narrow, "fixture:gw01-A0-B0")
	var suggest := _item_rect(narrow, "suggest")
	assert_gte(suggest.size.y, UiChrome.TAP_H, "SUGGEST WATCHES is under a finger")
	assert_false(suggest.intersects(first), "the suggest door sits on the first fixture")
	assert_gte(first.position.y, LeagueChrome.HEADER, "the first row rose into the header")
	assert_gte(_item_rect(narrow, "back").size.y, UiChrome.TAP_H, "the hub's BACK is under a finger")
	assert_gte(_item_rect(narrow, "continue").size.y, UiChrome.TAP_H, "CONTINUE is under a finger")
	assert_lte(_item_rect(narrow, "continue").end.x, vp.x, "CONTINUE ran off the sheet")
	assert_false(_item_rect(narrow, "continue").intersects(_item_rect(narrow, "back")),
		"the hub's header doors overlap")


func test_a_phone_plan_row_keeps_its_toggle_inside_the_row() -> void:
	var plan: Array = [_fixture(1), _fixture(2)]
	var items: Array = LeaguePlanSheet.layout(plan, {}, 24.0, 600.0, 72.0, true)
	var row: Rect2 = items[0]["rect"]
	var chip: Rect2 = items[1]["rect"]
	assert_gte(row.size.y, UiChrome.TAP_H, "the phone row is under a finger")
	assert_gte(chip.size.y, UiChrome.TAP_H, "the AUTO/WATCH door is under a finger")
	assert_true(row.encloses(chip), "the toggle left its row, so a press can sim the wrong game")
	assert_false(row.intersects(items[2]["rect"] as Rect2), "two phone rows share a band")


func test_the_table_columns_fit_a_phone_and_a_desktop_sheet() -> void:
	var cols := LeagueTableView.COMPACT_COLS
	for vp in [Vector2(1600, 900), Vector2(913, 411), Vector2(873, 393)]:
		var row := Rect2(24.0, 80.0, vp.x - 48.0, 18.0)
		var places: Dictionary = LeagueColumns.of(row, cols)
		assert_eq((places["cols"] as Array).size(), 8,
			"compact should paint every overall column at %s" % vp)
		assert_gt(float(places["club_x"]), float(places["pos_x"]), "# and CLUB overlap at %s" % vp)
		var previous := float(places["club_x"]) + float(places["club_w"])
		for col in places["cols"]:
			assert_gt(float(col["right"]) - float(col["w"]), previous - 0.01,
				"%s overlaps the club name at %s" % [col["label"], vp])
			previous = float(col["right"])
		assert_lte(float(places["club_w"]), row.size.x * 0.5,
			"the club column took more than half the row at %s" % vp)
		assert_lte(previous, row.end.x + 0.01, "PTS is drawn outside the row at %s" % vp)
		assert_gte(float(places["club_w"]), 100.0, "the club column is unreadable at %s" % vp)
		var first: Dictionary = (places["cols"] as Array)[0]
		var last: Dictionary = (places["cols"] as Array)[7]
		assert_gte(float(last["right"]) - float(first["right"]) + float(last["w"]), 400.0,
			"the record is still bunched in a corner at %s" % vp)


func test_the_compact_rail_tightens_on_a_portrait_phone() -> void:
	var cols := LeagueTableView.COMPACT_COLS
	var floor_w: float = LeagueColumns.min_row(cols)
	for vp in [Vector2(1280, 780), Vector2(360, 780), Vector2(320, 480)]:
		var row_w := maxf(vp.x - 48.0, floor_w)
		var places: Dictionary = LeagueColumns.of(Rect2(24.0, 80.0, row_w, 18.0), cols)
		var previous := float(places["club_x"]) + float(places["club_w"])
		for col in places["cols"]:
			assert_gt(float(col["right"]) - float(col["w"]), previous - 0.01,
				"%s overlaps the club name at %s" % [col["label"], vp])
			assert_gte(float(col["w"]), LeagueColumns.MIN_NUM_W - 0.01,
				"the %s box is too narrow to read at %s" % [col["label"], vp])
			previous = float(col["right"])
		assert_lte(previous, row_w + 24.0 + 0.01, "PTS is drawn outside the row at %s" % vp)
		assert_gte(float(places["club_w"]), LeagueColumns.MIN_CLUB_W,
			"the club column is unreadable at %s" % vp)
		if vp.x - 48.0 >= floor_w:
			assert_eq(row_w, vp.x - 48.0, "a sheet that fits was widened anyway at %s" % vp)
		else:
			assert_gt(row_w, vp.x - 48.0, "a sheet too narrow for the record did not pan at %s" % vp)


func test_the_number_rail_follows_the_row_width() -> void:
	var cols := LeagueTableView.COMPACT_COLS
	var wide: Dictionary = LeagueColumns.of(Rect2(24.0, 80.0, 1552.0, 20.0), cols)
	var phone: Dictionary = LeagueColumns.of(Rect2(24.0, 80.0, 825.0, 20.0), cols)
	var wide_last: float = float((wide["cols"] as Array)[7]["right"])
	var phone_last: float = float((phone["cols"] as Array)[7]["right"])
	assert_almost_eq(wide_last - phone_last, 727.0, 0.01, "PTS did not track the sheet width")
	var wide_first: float = float((wide["cols"] as Array)[0]["right"])
	var phone_first: float = float((phone["cols"] as Array)[0]["right"])
	assert_gt(wide_first, phone_first, "the whole rail did not move with the sheet")
	assert_lte(float(wide["club_w"]), 1552.0 * 0.5,
		"a wide sheet left the record in the corner")


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


func test_a_venue_caption_is_fitted_to_its_centre_column() -> void:
	var font: Font = load("res://fonts/BarlowCondensed-Medium.ttf")

	var room := 130.0 - 24.0
	assert_gt(font.get_string_size("COVENTRY BUILDING SOCIETY ARENA", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 10).x, room, "the probe font measured every venue as zero width")
	assert_eq(LeagueColumns.fit_caption("OLD TRAFFORD", font, 10, room), "OLD TRAFFORD",
		"a venue that fits its column was altered")
	var shown := LeagueColumns.fit_caption("COVENTRY BUILDING SOCIETY ARENA", font, 10, room)
	assert_true(shown.ends_with("…"), "a venue wider than its column was not shortened")
	assert_lte(font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x, room,
		"the shortened venue still runs out of the centre column")
	assert_eq(LeagueColumns.fit_caption("COVENTRY BUILDING SOCIETY ARENA", font, 10, 196.0),
		"COVENTRY BUILDING SOCIETY ARENA", "a wide column shortened a venue that fits it")
	assert_eq(LeagueColumns.fit_caption("OLD TRAFFORD", font, 10, 0.0), "",
		"a column with no room still painted a venue")
	assert_eq(LeagueColumns.fit_caption("", font, 10, room), "",
		"a club with no ground name painted one anyway")

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
			assert_gt(bottom, vp.y - LeagueChrome.BAR_H, "a phone table must overflow so the body scrolls")
		else:
			assert_lte(bottom, vp.y - LeagueChrome.BAR_H, "a desktop table should fit in one window")
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


func test_the_calendar_names_what_its_day_counters_count() -> void:
	var fonts: Dictionary = UiChrome.fonts()
	var view := {"month": "2026-08", "days": {"2026-08-15": {"n": 10, "played": 0}}}
	for vp in [Vector2(1600, 900), Vector2(913, 411), Vector2(640, 360)]:
		for touch in [false, true]:
			view["touch"] = touch
			var legend: Dictionary = LeagueCalendarView.legend_rect(vp, view, fonts)
			assert_false(legend.is_empty(), "the day counters are unlabelled at %s (touch %s)" % [vp, touch])
			var rect: Rect2 = legend["rect"]
			var text := str(legend["text"])
			assert_true(text.contains("PLAYED") and text.contains("TOTAL"),
				"the legend does not name the pair it explains: " + text)
			assert_eq(text, LeagueCalendarView.LEGEND, "a roomy sheet shortened the legend at %s" % vp)
			assert_almost_eq(rect.position.x, 24.0 + UiChrome.text_width(fonts["bold"],
				LeagueMonth.label("2026-08"), 13) + 12.0, 0.01, "the legend does not sit by the month")
			assert_almost_eq(rect.end.y, LeagueCalendarView.HEADER + 25.0, 0.01,
				"the legend left the month's line")
			assert_lt(rect.end.y, LeagueCalendarView.grid_top(touch), "the legend crowds the day grid")
			assert_lte(rect.end.x, LeagueCalendarView.month_door_rects(vp, touch)[0].position.x - 12.0,
				"the legend runs into the month doors at %s" % vp)
			assert_lte(rect.end.x, vp.x - 24.0, "the legend runs off the sheet at %s" % vp)


func test_a_month_with_no_counters_carries_no_legend() -> void:
	var fonts: Dictionary = UiChrome.fonts()
	var vp := Vector2(1600, 900)
	assert_true(LeagueCalendarView.legend_rect(vp, {"month": "2026-07", "days": {}}, fonts).is_empty(),
		"an empty month explained a counter it does not draw")
	assert_true(LeagueCalendarView.legend_rect(vp,
		{"month": "2026-07", "days": {"2026-07-04": {"n": 0, "played": 0}}}, fonts).is_empty(),
		"a day with no fixtures raised a legend")
	var narrow: Dictionary = LeagueCalendarView.legend_rect(Vector2(240, 411),
		{"month": "2026-08", "touch": true, "days": {"2026-08-15": {"n": 10, "played": 0}}}, fonts)
	assert_true(narrow.is_empty(), "a sheet too narrow for the legend painted one anyway")


func test_the_sheet_chrome_keeps_back_top_left_and_the_primary_top_right() -> void:
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var book := LeagueBook.new()
		var sheets := {
			"table": book.table_layout(vp, {"table": _table(), "rules": LeagueRules.defaults()}),
			"calendar": book.calendar_layout(vp, {"month": "2026-10", "day": "", "days": {}, "day_fixtures": []}),
			"report": book.report_layout(vp, {"fixture": _fixture(1), "events": [], "day": "x"}),
			"podium": book.podium_layout(vp, {"summary": {}}),
			"system": LeagueSystemSheet.new().layout(vp, {"date": "2026-08-15", "name": "S"}),
			"stats": LeagueStatsSheet.new().layout(vp, {"name": "S", "reports": []}),
			"interest": LeagueInterestSheet.new().layout(vp, {"query": "", "results": [], "clubs": []}),
			"hub": LeagueSheet.new().hub_layout(vp, _state([_fixture(1)], _table())),
		}
		for label in sheets:
			assert_eq(_item_rect(sheets[label], "back"), LeagueExtra.back_rect(),
				"%s: BACK is not in the top-left corner at %s" % [label, vp])
		var cont := _item_rect(sheets["hub"], "continue")
		var kick := _item_rect(sheets["table"], "tbl:mode:full")
		assert_almost_eq(cont.end.x, vp.x - 24.0, 0.5, "CONTINUE is not top-right")
		assert_lte(cont.end.y, LeagueChrome.HEADER, "CONTINUE left the header")
		assert_gt(kick.position.y, LeagueChrome.HEADER, "the reading doors left the bottom bar")
		assert_almost_eq(_item_rect(sheets["table"], "tbl:mode:compact").end.y, vp.y - 8.0, 0.5,
			"COMPACT left the bottom bar")
		assert_almost_eq(kick.end.y, vp.y - 8.0, 0.5, "FULL left the bottom bar")
		assert_eq(SettingsLayout.back_rect(vp), Rect2(24.0, 12.0, 116.0, 44.0),
			"settings BACK is not top-left")
		var picker = load("res://scripts/ui/team_select.gd").new()
		assert_almost_eq(picker.back_rect(vp).position.x, 24.0, 0.5, "the picker's BACK is not top-left")
		picker.free()
		var pre := PreMatchScreen.new()
		pre.setup({"kick": "KICK OFF"})
		var doors: Array = pre.layout(vp)["buttons"]
		assert_eq(_item_rect(doors, "back"), LeagueExtra.back_rect(), "pre-match BACK is not top-left")
		assert_almost_eq(_item_rect(doors, "kick").end.x, vp.x - 24.0, 0.5, "the kick is not top-right")
		assert_lte(_item_rect(doors, "kick").end.y, LeagueChrome.HEADER, "the kick left the header")
		assert_gt(_item_rect(doors, "kick").position.x, _item_rect(doors, "back").end.x,
			"the kick sits on BACK at %s" % vp)
		pre.free()

func _item_rect(items: Array, id: String) -> Rect2:
	for item in items:
		if str(item["id"]) == id:
			return item["rect"]
	return Rect2()


func test_the_hub_hint_names_the_pointer() -> void:
	assert_eq(LeagueSheet.plan_hint(true), "TAP A GAME TO SWITCH AUTO / WATCH",
		"a touch hub stopped naming the tap")
	assert_eq(LeagueSheet.plan_hint(false), "CLICK A GAME TO SWITCH AUTO / WATCH",
		"a desktop hub tells a mouse user to tap")
	for touch in [true, false]:
		var hint := LeagueSheet.body_hint({"touch": touch, "can_suggest": true, "plan": [_fixture(1)]})
		assert_false(hint.begins_with(" · ") or hint.contains("TODAY'S FIXTURES"),
			"the body line still carries a caption or the page's own title: %s" % hint)


	assert_eq(LeagueSheet.body_hint({"touch": false, "can_suggest": false, "plan": []}), "",
		"a hub with no hint painted a line")
	assert_eq(LeagueSheet.body_hint({"touch": false, "can_suggest": true, "plan": [_fixture(1, 1)]}),
		"CONTINUE OPENS THE NEXT WATCH", "a pending watch lost its CONTINUE line")


func test_the_hub_names_today_and_its_ledger() -> void:
	var state := _state([_fixture(1)], _table())
	state["name"] = "LEAGUE 1"
	state["competitions"] = [{"id": "PL", "short": "PREMIER LEAGUE", "matchday": 7},
		{"id": "LL", "short": "LA LIGA", "matchday": 7},
		{"id": "BL", "short": "BUNDESLIGA", "matchday": 7},
		{"id": "BL2", "short": "2. BUNDESLIGA", "matchday": 7}]
	state["played"] = 120
	state["total"] = 760
	var caption := LeagueSheet.hub_caption(state)
	assert_eq(caption, "15/AUG/2026 · 120 OF 760 PLAYED",
		"the hub caption is not the day and the ledger: %s" % caption)
	assert_false(caption.contains("GW"), "the caption still lists a league's gameweek")
	for short in ["PREMIER LEAGUE", "LA LIGA", "BUNDESLIGA"]:
		assert_false(caption.contains(short), "the caption still lists %s's gameweek" % short)

	state["settling"] = true
	assert_true(LeagueSheet.hub_caption(state).ends_with(" · FINISHING THE WATCHED MATCH"),
		"the settling caption lost its suffix")

	var bold: Font = UiChrome.fonts()["bold"]
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var band := LeagueExtra.header_band(vp, bold, LeagueSheet.HUB_TITLE, caption,
			LeagueExtra.primary_rect(vp).size.x + 12.0, false)
		assert_eq(str(band["title"]), "Today's Fixtures",
			"the hub header does not read Today's Fixtures at %s" % vp)
		assert_false(str(band["title"]).contains("LEAGUE 1"), "the hub title is the save name")
	var caps := LeagueExtra.header_band(Vector2(1600, 900), bold, "TODAY'S FIXTURES", "", 152.0)
	assert_eq(str(caps["title"]), "TODAY'S FIXTURES", "a kicker lost its upper case")


func test_every_plan_group_opens_with_its_league_heading() -> void:
	var sheet := LeagueSheet.new()
	for count in [1, 2]:
		var plan: Array = []
		for i in range(count):
			var fx := _fixture(i + 1)
			fx["competition_id"] = "PL" if i == 0 else "LL"
			fx["matchday"] = 4 + i
			plan.append(fx)
		var heads: Array = []
		for item in sheet.hub_layout(Vector2(1280, 720), _state(plan, _table())):
			if str(item["kind"]) == "league_head":
				heads.append("%s/%d" % [str(item["competition"]), int(item["matchday"])])
		assert_eq(heads, ["PL/4"] if count == 1 else ["PL/4", "LL/5"],
			"a %d-league day is not headed by its league" % count)


func test_a_new_league_opens_on_a_blank_field_naming_my_league_sim() -> void:
	assert_eq(LeagueStartSheet.SAVE_NAME, "My League Sim", "the wizard's default name moved")
	assert_eq(str(LeagueScreen.new().wizard["name"]), "",
		"a fresh screen opens on a name instead of letting the player type one")
	var start := LeagueStartSheet.new()
	var field := {}
	for item in start.wizard_layout(Vector2(1280, 720),
			{"name": "", "calendar_mode": "generated", "advance_mode": "fixture_days"}):
		if str(item["id"]) == "name":
			field = item
	assert_true(not field.is_empty(), "the wizard laid out no name field")
	assert_eq(str(field["value"]), "", "an empty field paints its placeholder state")
	for vp in [Vector2(1280, 720), Vector2(913, 411)]:
		var rect := Rect2()
		for item in start.wizard_layout(vp,
				{"name": "", "calendar_mode": "generated", "advance_mode": "fixture_days"}):
			if str(item["id"]) == "name":
				rect = item["rect"]
		assert_gt(rect.size.y, 0.0, "the blank field lost its box at %s" % vp)


func test_an_untouched_name_falls_back_to_my_league_sim() -> void:
	assert_eq(LeagueStartSheet.save_name(""), LeagueStartSheet.SAVE_NAME,
		"a player who types nothing does not get the suggested name")
	assert_eq(LeagueStartSheet.save_name("   "), LeagueStartSheet.SAVE_NAME,
		"a field holding only spaces made a nameless save")
	assert_eq(LeagueStartSheet.save_name("  Winter League  "), "Winter League",
		"the typed name kept padding a table header would print")
	assert_eq(LeagueStartSheet.save_name("Q"), "Q", "a one-letter name was rewritten")


func test_the_load_row_status_reads_as_player_copy() -> void:
	assert_eq(LeagueStartSheet.status_label("in_progress"), "IN PROGRESS",
		"an unfinished save still prints its stored token")
	assert_eq(LeagueStartSheet.status_label("complete"), "COMPLETE",
		"a complete save prints its stored token")
	assert_eq(LeagueStartSheet.status_label(""), "", "an empty status grew words")
	assert_eq(LeagueStartSheet.status_label("paused_by_user"), "PAUSED BY USER",
		"an unknown token is not read as words")
	for token in ["in_progress", "complete", "paused_by_user"]:
		assert_false(LeagueStartSheet.status_label(token).contains("_"),
			"a raw token reached the load row: %s" % token)


func test_the_month_stepper_binds_its_label_and_chevrons() -> void:
	for vp in [Vector2(1280, 720), Vector2(1600, 900), Vector2(913, 411), Vector2(360, 780)]:
		var items: Array = LeagueStatsSheet.new().layout(vp, {"name": "S", "reports": [],
			"filters": {"league": "", "month": "2026-09", "team": "", "stat": "goals"}})
		var prev := _item_rect(items, "statsmonth:-1")
		var next := _item_rect(items, "statsmonth:1")
		var read := _item_rect(items, "")
		var goals := _item_rect(items, "statsstat:goals")
		assert_true(read.size.x >= 72.0, "the readout has no width at %s" % vp)
		assert_almost_eq(read.position.x, prev.end.x + LeagueStatsSheet.STEP_GAP, 0.01,
			"the readout does not follow its back arrow at %s" % vp)
		assert_almost_eq(next.position.x, read.end.x + LeagueStatsSheet.STEP_GAP, 0.01,
			"the forward arrow does not hug its readout at %s" % vp)
		assert_almost_eq(prev.position.y, next.position.y, 0.01,
			"the stepper cells do not share a row at %s" % vp)
		assert_almost_eq(prev.size.y, read.size.y, 0.01,
			"the readout left the arrows' height at %s" % vp)
		if goals.position.y == next.position.y:
			assert_gte(goals.position.x - next.end.x, LeagueStatsSheet.STEP_AFTER,
				"the stat chips crowd the stepper at %s" % vp)
		else:
			assert_gte(goals.position.y, next.end.y,
				"the wrapped stat chips sit on the stepper at %s" % vp)
			assert_almost_eq(goals.position.x, 24.0, 0.01,
				"the wrapped stat chips left the sheet's inset at %s" % vp)
		assert_lte(_item_rect(items, "statsstat:assists").end.x, vp.x - 24.0 + 0.01,
			"the stat chips run off the sheet at %s" % vp)
		assert_lte(next.end.x, vp.x - 24.0, "the stepper runs off the sheet at %s" % vp)


func test_the_body_keeps_the_pinned_doors_outside_the_clipped_window() -> void:
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var hub: Array = LeagueSheet.new().hub_layout(vp, _state([_fixture(1)], _table()))
		var table: Array = LeagueBook.new().table_layout(vp, {
			"table": _table(), "rules": LeagueRules.defaults()})
		var cont: Rect2 = _item_rect(hub, "continue")
		var reading: Rect2 = _item_rect(table, "tbl:mode:full")
		var body := _body(vp)
		body.set_sheet(hub, vp, true, 0.0)
		assert_lte(cont.end.y, LeagueChrome.HEADER, "CONTINUE left the header at %s" % vp)
		assert_true(cont.end.y <= body.position.y, "CONTINUE sits inside the body's band at %s" % vp)
		assert_eq(body.content.size(), hub.size() - body.pinned.size(),
			"a pinned door rode the scrolling rows at %s" % vp)
		body.set_sheet(table, vp, true, LeagueChrome.BAR_H)
		var window := Rect2(body.position, body.size)
		assert_eq(window.end.y, vp.y - LeagueChrome.BAR_H, "the wrong band is clipped at %s" % vp)
		assert_eq(body.pinned.size(), 4, "the table lost a pinned door at %s" % vp)
		assert_gte(reading.position.y, window.end.y, "FULL is inside the scrolling band at %s" % vp)
		var form: Rect2 = _item_rect(table, "tbl:mode:form")
		assert_gte(form.position.y, window.end.y, "FORM is inside the scrolling band at %s" % vp)
		assert_gte(form.position.x, reading.end.x, "the reading doors crowd each other at %s" % vp)
		assert_lte(form.end.x, vp.x - 24.0, "the form door runs off the sheet at %s" % vp)

		body.scroll_to(400.0)
		var door := _body_item(body.pinned, "back")
		var row := _body_item(body.button_rects(), "back")
		assert_eq(door["rect"], row["rect"], "the scroll carried BACK off its corner at %s" % vp)

		var calendar: Array = LeagueBook.new().calendar_layout(vp, {
			"month": "2026-10", "day": "", "days": {}, "day_fixtures": []})
		body.set_sheet(calendar, vp, true, 0.0)
		assert_false(_body_item(body.pinned, "month:1").is_empty(),
			"the calendar's month chips were not pinned at %s" % vp)
		body.free()


func _body(vp: Vector2) -> LeagueBody:
	var body := LeagueBody.new()
	body.position = Vector2(0.0, LeagueChrome.HEADER)
	body.size = Vector2(vp.x, vp.y - LeagueChrome.HEADER)
	return body

func _body_item(items: Array, id: String) -> Dictionary:
	for item in items:
		if str(item["id"]) == id:
			return item
	return {}


func test_a_frozen_body_answers_no_door() -> void:
	var vp := Vector2(1600, 900)
	var hub: Array = LeagueSheet.new().hub_layout(vp, _state([_fixture(1)], _table()))
	var body := _body(vp)
	body.set_sheet(hub, vp, true, 0.0)
	var at: Vector2 = _item_rect(hub, "continue").get_center() + Vector2(0.0, -6.0)
	assert_eq(body.hit(at), "continue", "an unfrozen body lost its pinned door")
	body.frozen = true
	assert_eq(body.hit(at), "", "a frozen body still answered its doors")
	body.free()


func test_a_scrolling_page_claims_its_rows_only_inside_the_window() -> void:
	var vp := Vector2(1600, 260)
	var body := _body(vp)
	var items: Array = LeagueBook.new().table_layout(vp,
		{"table": _table(), "rules": LeagueRules.defaults()})
	body.set_sheet(items, vp, true, LeagueChrome.BAR_H)
	assert_gt(body.max_scroll(), 0.0, "the page never needed a scroll")
	var row: Rect2 = _item_rect(items, "club:C10")
	assert_gte(row.position.y, LeagueChrome.HEADER, "the probe row starts on screen")
	body.scroll_to(row.position.y + 10.0 - LeagueChrome.HEADER)
	var at := Vector2(row.get_center().x, row.position.y + 10.0 - body.scroll)
	assert_eq(body.hit(at), "club:C10", "a row that scrolled into the window did not answer")
	assert_eq(body.hit(Vector2(at.x, vp.y - 8.0)), "",
		"a row under the bottom bar still answered")
	assert_eq(body.hit(Vector2(vp.x + 40.0, at.y)), "", "a point outside the body answered")
	body.free()


func test_the_shortest_captions_fit_after_the_floor() -> void:
	var bold: Font = UiChrome.fonts()["bold"]
	var sheet := LeagueSheet.new()
	var plan: Array = [_fixture(1, 0, 1)]
	var chip_w := -1.0
	for item in sheet.hub_layout(Vector2(1600, 900), _state(plan, _table())):
		if str(item["id"]).begins_with("toggle:"):
			chip_w = (item["rect"] as Rect2).size.x
	assert_gt(chip_w, 0.0, "the hub laid out no AUTO/WATCH chip")
	for label in ["AUTO", "WATCH"]:
		assert_lte(UiChrome.text_width(bold, label, ChromeDensity.MIN_READ), chip_w - 6.0,
			"the %s caption no longer fits its chip" % label)
	var book := LeagueBook.new()
	var counter := UiChrome.text_width(bold, "10/10", ChromeDensity.MIN_READ)
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var cells := 0
		for item in book.calendar_layout(vp, {
			"month": "2026-10", "day": "", "days": {}, "day_fixtures": [],
		}):
			if str(item["kind"]) != "cell":
				continue
			cells += 1
			var rect: Rect2 = item["rect"]

			assert_gte(rect.size.x, counter + 20.0,
				"the 10/10 counter overruns its cell at %s" % vp)
		assert_eq(cells, 31, "October should still have 31 cells at %s" % vp)

func test_every_phone_sheet_overflows_into_the_scroll_window() -> void:
	var sheet := LeagueSheet.new()
	var start := LeagueStartSheet.new()
	var book := LeagueBook.new()
	var vp := Vector2(913, 411)
	var window := vp.y - LeagueChrome.BAR_H
	var plan: Array = []
	for i in range(10):
		plan.append(_fixture(i))
	assert_gt(_bottom(sheet.hub_layout(vp, _state(plan, _table()))), window,
		"ten phone fixtures should scroll instead of being dropped")
	var saves: Array = []
	for i in range(7):
		saves.append({"slug": "s%d" % i, "name": "Save %d" % i, "status": "in_progress",
			"current_date": "2026-09-0%d" % (i + 1), "matchday": i + 1, "path": "", "modified": i})
	assert_gt(_bottom(start.load_layout(vp, {"saves": saves})), window,
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


func test_a_roundup_card_centers_its_score_between_the_columns() -> void:
	var played := _fixture(1)
	played["status"] = "played"
	played["home_goals"] = 2
	played["away_goals"] = 1
	var book := LeagueBook.new()
	for vp in [Vector2(1280, 720), Vector2(730, 411)]:
		var items: Array = book.report_layout(vp, {"roundup": [{"fixture": played, "events": []}]})
		var cards: Array = []
		for item in items:
			if str(item["kind"]) == "result":
				cards.append(item)
		assert_eq(cards.size(), 1, "the roundup lost its card at %s" % vp)
		var card: Dictionary = cards[0]
		assert_true(bool(card.get("centered_score", false)),
			"a RESULTS card pinned its score to the right edge at %s" % vp)
		var rect: Rect2 = card["rect"]
		var places := LeagueBlock.columns(rect)
		assert_almost_eq(float(places["mid_x"]), rect.get_center().x, 0.01,
			"the column midline left the card's middle at %s" % vp)
		var centered: float = LeagueBlock.score_x(rect, true)
		assert_almost_eq(centered, rect.get_center().x, 0.01,
			"the RESULTS score is not on the midline at %s" % vp)
		assert_gt(centered, float(places["home_x"]) + float(places["home_w"]),
			"the RESULTS score sits in the home column at %s" % vp)
		assert_lt(centered, float(places["away_x"]),
			"the RESULTS score sits in the away column at %s" % vp)

		var sheet := LeagueSheet.new()
		var hub: Array = sheet.hub_layout(Vector2(913, 411),
			_state([played, _fixture(2)], _table()))
		var rows := 0
		for item in hub:
			if str(item["kind"]) == "row":
				rows += 1
				var row: Rect2 = item["rect"]
				assert_almost_eq(LeagueBlock.score_x(row), row.end.x - 12.0, 0.01,
					"a plan row stopped right-aligning its score at %s" % row)
		assert_eq(rows, 2, "the plan lost a row")


func test_a_pending_row_without_a_kickoff_starts_its_clubs_at_the_inset() -> void:
	var med: Font = UiChrome.fonts()["med"]
	for row in [Rect2(24.0, 72.0, 1552.0, LeagueChrome.ROW_H),
			Rect2(24.0, 72.0, 865.0, LeagueChrome.ROW_H)]:
		var bare := LeaguePlanRows.clubs_x(row, "", med)
		assert_almost_eq(bare, row.position.x + LeagueBlock.INSET, 0.01,
			"a row with no kick-off time left a blank gutter at %s" % row)

		assert_almost_eq(bare, float(LeagueBlock.columns(row)["home_x"]), 0.01,
			"the pending row and its result block disagree about the club column at %s" % row)
		for kick in ["12:30", "15:00", "17:30"]:
			var ink := InterestNames.width(med, kick, 10)
			assert_almost_eq(LeaguePlanRows.clubs_x(row, kick, med), row.position.x + 8.0 + ink + 8.0,
				0.01, "%s did not set its own gutter at %s" % [kick, row])
			assert_gt(LeaguePlanRows.clubs_x(row, kick, med), row.position.x + 8.0 + ink,
				"the home name sits on the %s kick-off at %s" % [kick, row])


func test_a_fixture_reads_as_two_event_columns() -> void:
	var fixture := _fixture(1)
	var report := {
		"fixture": fixture,
		"events": [
			{"id": 5, "minute": 23, "kind": "goal", "club_id": "B1", "player_name": "M. Cunha"},
			{"id": 6, "minute": 30, "kind": "yellow", "club_id": "B1", "player_name": "D. Back"},
			{"id": 2, "minute": 6, "kind": "goal", "club_id": "A1", "player_name": "Y. Pino"},
			{"id": 3, "minute": 7, "kind": "goal", "club_id": "A1", "player_name": "J. Mateta"},
			{"id": 9, "minute": 58, "kind": "goal", "club_id": "A1", "player_name": "J. Mateta"},
		],
	}
	var sides: Dictionary = LeagueRoundup.sides(report)
	var home: Array = sides["home"]
	var away: Array = sides["away"]
	assert_eq(home.map(func(e): return "%d' %s" % [int(e["minute"]), str(e["player_name"])]),
		["6' Y. Pino", "7' J. Mateta", "58' J. Mateta"], "the home column lost its minute order")
	assert_eq(away.map(func(e): return "%d' %s" % [int(e["minute"]), str(e["player_name"])]),
		["23' M. Cunha", "30' D. Back"], "the away column lost a row")

	assert_eq(LeagueRoundup.line(home[0]), "6' Y. Pino", "an entry repeated its club")
	assert_eq(LeagueRoundup.line(away[0]), "23' M. Cunha", "an away entry repeated its club")


func test_an_event_with_no_known_club_still_reads() -> void:
	var fixture := _fixture(1)
	var report := {"fixture": fixture, "events": [
		{"id": 1, "minute": 12, "kind": "goal", "player_name": "A. Striker"},
		{"id": 2, "minute": 40, "kind": "goal", "club_id": "ZZ", "detail": "B. Stranger"},
	]}
	var sides: Dictionary = LeagueRoundup.sides(report)
	assert_eq((sides["home"] as Array).size(), 2, "a clubless row vanished")
	assert_eq((sides["away"] as Array).size(), 0, "a stranger took the away column")
	assert_eq(LeagueRoundup.line((sides["home"] as Array)[0]), "12' A. Striker",
		"a clubless goal invented a club")


func test_an_assist_rides_the_goal_line_in_brackets() -> void:
	var report := {"fixture": _fixture(1), "events": [
		{"id": 2, "minute": 6, "kind": "goal", "club_id": "A1", "player_name": "Y. Pino"},
		{"id": 3, "minute": 6, "kind": "assist", "club_id": "A1", "player_name": "J. Eze"},
		{"id": 4, "minute": 23, "kind": "goal", "club_id": "B1", "player_name": "M. Cunha"},
		{"id": 5, "minute": 23, "kind": "assist", "club_id": "B1", "player_name": "B. Saka"},
	]}
	var lines: Array = LeagueRoundup.lines(report)
	assert_eq(lines.size(), 2, "an assist took a line of its own")
	assert_eq(LeagueRoundup.line(lines[0]), "6' Y. Pino (J. Eze)", "the home assist was lost")
	assert_eq(LeagueRoundup.line(lines[1]), "23' M. Cunha (B. Saka)", "the away assist was lost")

	var orphan := {"fixture": _fixture(1), "events": [
		{"id": 2, "minute": 6, "kind": "goal", "club_id": "A1", "player_name": "Y. Pino"},
		{"id": 3, "minute": 7, "kind": "assist", "club_id": "A1", "player_name": "J. Eze"},
	]}
	assert_eq(LeagueRoundup.line(LeagueRoundup.lines(orphan)[0]), "6' Y. Pino",
		"a mismatched assist was attached to a goal")


func test_an_own_goal_is_credited_to_the_side_that_gained_it() -> void:
	var fixture := _fixture(1)
	var report := {"fixture": fixture, "events": [
		{"id": 1, "minute": 12, "kind": "own_goal", "club_id": "A1", "player_name": "D. Back",
			"assist_name": "B. Saka"},
		{"id": 2, "minute": 30, "kind": "goal", "club_id": "A1", "player_name": "Y. Pino"},
	]}
	var sides: Dictionary = LeagueRoundup.sides(report)
	assert_eq((sides["home"] as Array).size(), 2, "the own goal left the gaining side")
	assert_eq((sides["away"] as Array).size(), 0, "the own goal was credited to the conceding side")
	assert_eq(LeagueRoundup.goals(report).size(), 2, "an own goal stopped counting as a goal")
	assert_eq(LeagueRoundup.line((sides["home"] as Array)[0]), "12' D. Back (OG)",
		"the own goal lost its mark")
	assert_eq(LeagueRoundup.line((sides["home"] as Array)[1]), "30' Y. Pino",
		"a normal goal took an own-goal mark")


func test_a_penalty_goal_is_marked_on_its_scorer() -> void:
	var fixture := _fixture(1)
	assert_eq(LeagueRoundup.line({"minute": 12, "club_id": "A1",
		"player_name": "A. Striker", "penalty": true}), "12' A. Striker (PEN)",
		"the report did not mark the penalty")

	assert_eq(LeagueRoundup.line({"minute": 12, "detail": "A. Striker", "penalty": 1}),
		"12' A. Striker (PEN)", "a stored penalty lost its mark")
	assert_eq(LeagueRoundup.line({"minute": 30, "player_name": "B. Winger",
		"assist_name": "C. Pivot"}), "30' B. Winger (C. Pivot)",
		"an open-play goal took a mark")
	assert_false(LeagueRoundup.is_penalty({"player_name": "A. Striker"}),
		"an open-play goal read as a penalty")

	for vp in [Vector2(1280, 720), Vector2(913, 411)]:
		var book := LeagueBook.new()
		var items: Array = book.report_layout(vp, {
			"fixture": fixture, "day": "2026-08-15", "events": [
				{"minute": 12, "kind": "goal", "player_name": "A. Striker", "penalty": true},
			],
		})
		var marked := false
		for item in items:
			if str(item["kind"]) == "event" and bool(item["event"].get("penalty", false)):
				marked = true
		assert_true(marked, "the report dropped the penalty flag at %s" % vp)

func _bottom(items: Array) -> float:
	var bottom := 0.0
	for item in items:
		if not bool(item.get("pinned", false)):
			bottom = maxf(bottom, (item["rect"] as Rect2).end.y)
	return bottom

func test_the_report_lays_out_events_and_a_roundup() -> void:
	var book := LeagueBook.new()
	var events := [
		{"minute": 12, "kind": "goal", "club_id": "A1", "player_name": "A. Striker"},
		{"minute": 12, "kind": "assist", "club_id": "A1", "player_name": "B. Winger"},
		{"minute": 30, "kind": "yellow", "club_id": "B1", "player_name": "C. Pivot"},
		{"minute": 77, "kind": "red", "club_id": "B1", "player_name": "D. Back"},
	]
	var single: Array = book.report_layout(Vector2(1280, 720), {
		"fixture": _fixture(1), "events": events, "day": "2026-08-15",
	})

	assert_eq(single.size(), 4, "the report lost an event or the back door")
	var places := LeagueReportSheet.columns(Vector2(1280, 720))
	var xs := {}
	for item in single:
		if str(item["kind"]) != "event":
			continue
		xs[str(item["side"])] = (item["rect"] as Rect2).position.x
		assert_ne(str(item["event"].get("kind", "")), "assist", "an assist took a row of its own")
	assert_eq(xs.get("home", -1.0), float(places["home_x"]), "the home column moved")
	assert_eq(xs.get("away", -1.0), float(places["away_x"]), "the away column moved")
	var roundup: Array = book.report_layout(Vector2(1280, 720), {
		"roundup": [{"fixture": _fixture(1), "events": events, "score": [1, 0], "played": true}],
	})

	assert_eq(roundup.size(), 3, "the roundup lost its row or a header door")


func test_the_results_sheet_adds_the_hubs_continue_beside_back() -> void:
	var book := LeagueBook.new()
	for vp in [Vector2(1600, 900), Vector2(913, 411), Vector2(730, 411)]:
		var items: Array = book.report_layout(vp, {
			"roundup": [{"fixture": _fixture(1), "events": [], "score": [1, 0], "played": true}],
			"day": "2026-08-15",
		})
		var cont := _item_rect(items, "continue")
		assert_eq(cont, LeagueExtra.primary_rect(vp), "RESULTS: CONTINUE is not in the hub's corner at %s" % vp)
		assert_almost_eq(cont.end.x, vp.x - 24.0, 0.5, "RESULTS: CONTINUE is not top-right at %s" % vp)
		assert_lte(cont.end.y, LeagueChrome.HEADER, "RESULTS: CONTINUE left the header at %s" % vp)
		assert_eq(_item_rect(items, "back"), LeagueExtra.back_rect(), "RESULTS: BACK moved at %s" % vp)
		assert_gt(cont.position.x, LeagueExtra.back_rect().end.x,
			"RESULTS: the two header doors sit on each other at %s" % vp)
		var pinned := 0
		for item in items:
			if str(item["id"]) in ["back", "continue"] and bool(item.get("pinned", false)):
				pinned += 1
		assert_eq(pinned, 2, "a RESULTS header door scrolls away at %s" % vp)
	var single: Array = book.report_layout(Vector2(1280, 720), {
		"fixture": _fixture(1), "events": [], "day": "2026-08-15",
	})
	assert_eq(_item_rect(single, "continue"), Rect2(), "a single match report gained CONTINUE")


func test_a_phone_header_hangs_the_drawer_door_beside_back() -> void:
	var bold: Font = UiChrome.fonts()["bold"]
	var sheet := LeagueSheet.new()
	for vp in [Vector2(913, 411), Vector2(640, 360), Vector2(1280, 720)]:
		var state := _state([_fixture(1)], _table())
		var cont := _item_rect(sheet.hub_layout(vp, state), "continue")
		var band := LeagueExtra.header_band(vp, bold, LeagueSheet.HUB_TITLE,
			LeagueSheet.hub_caption(state), cont.size.x + 12.0, false, true)
		var door := LeagueExtra.nav_rect(vp)
		assert_false(door == Rect2(), "no header lane for the drawer door at %s" % vp)
		assert_almost_eq(door.position.x, LeagueExtra.back_rect(true).end.x + LeagueExtra.NAV_GAP, 0.01,
			"the drawer door left BACK's shoulder at %s" % vp)
		assert_gte(door.size.x, 44.0, "the drawer door is narrower than a finger at %s" % vp)
		assert_lte(door.end.x, cont.position.x, "the drawer door sits under CONTINUE at %s" % vp)
		var title: Rect2 = band["title_rect"]
		assert_gte(title.position.x, door.end.x, "the title sits on the drawer door at %s" % vp)
		assert_lte(title.end.x, cont.position.x, "the title runs under CONTINUE at %s" % vp)
		assert_eq(str(band["title"]), LeagueSheet.HUB_TITLE,
			"a phone header with room for its title lost it at %s" % vp)
		var strip: Rect2 = band["caption_rect"]
		if strip != Rect2():
			assert_lte(strip.end.x, cont.position.x - 12.0, "the caption runs under CONTINUE at %s" % vp)
			assert_gte(strip.position.x, title.end.x, "the caption is painted through the title at %s" % vp)

	var desk := LeagueExtra.header_band(Vector2(1600, 900), bold, LeagueSheet.HUB_TITLE, "", 152.0)
	assert_almost_eq((desk["title_rect"] as Rect2).position.x, LeagueExtra.TITLE_X, 0.01,
		"the desktop title lane moved")
	var desk_hub := LeagueExtra.header_band(Vector2(1600, 900), bold, LeagueSheet.HUB_TITLE, "",
		152.0, false, false)
	assert_almost_eq((desk_hub["title_rect"] as Rect2).position.x, LeagueExtra.TITLE_X, 0.01,
		"a desktop header made room for a door it does not paint")


func test_a_header_that_cannot_hold_its_title_shortens_or_drops_it() -> void:
	var bold: Font = UiChrome.fonts()["bold"]
	for vp in [Vector2(411, 914), Vector2(375, 812), Vector2(320, 480)]:
		var door := LeagueExtra.nav_rect(vp)
		assert_false(door == Rect2(), "a narrow sheet lost the drawer door at %s" % vp)
		var cont := LeagueExtra.primary_rect(vp, 140.0, true)
		assert_lte(door.end.x, cont.position.x, "the drawer door sits under CONTINUE at %s" % vp)
		var band := LeagueExtra.header_band(vp, bold, LeagueSheet.HUB_TITLE,
			LeagueSheet.hub_caption(_state([_fixture(1)], _table())), cont.size.x + 12.0, false, true)
		var title: Rect2 = band["title_rect"]
		assert_gte(title.position.x, door.end.x, "the title starts on the drawer door at %s" % vp)
		assert_lte(title.end.x, cont.position.x, "the title runs under CONTINUE at %s" % vp)
		var drawn := str(band["title"])
		assert_true(drawn == "" or drawn.begins_with("Today"),
			"a narrow header drew neither its page name nor nothing at %s: '%s'" % [vp, drawn])
		if drawn.length() > 1:
			assert_true(drawn == LeagueSheet.HUB_TITLE or drawn.ends_with("…"),
				"a narrow header lost its name instead of being shortened at %s" % vp)
		assert_eq(str(band["caption"]), "", "a caption was drawn without a title at %s" % vp)


func test_a_phone_header_never_lays_a_row_under_the_drawer_door() -> void:
	var panel := LeaguePanel.new()
	panel.touch = true
	var vp := Vector2(913, 411)
	var door := panel.tab_rect(vp)
	assert_almost_eq(door.end.y, LeagueExtra.nav_rect(vp).end.y, 0.01,
		"the painted door and the answer box disagree")
	assert_lte(door.end.y, LeagueChrome.HEADER, "the door reached into the body")
	assert_gte(LeagueBody.TOP, door.end.y, "the body starts above the drawer door")
	assert_eq(LeagueBody.TOP, LeagueChrome.HEADER, "the body top left the header band")


func test_the_header_title_and_caption_clear_the_header_doors() -> void:
	var bold: Font = UiChrome.fonts()["bold"]
	var long_name := "MANCHESTER DERBY LEAGUE"
	var caption := "15/AUG/2026 · GW 1 · 0 OF 380 PLAYED"
	var sheet := LeagueSheet.new()
	for vp in [Vector2(1600, 900), Vector2(913, 411), Vector2(730, 411), Vector2(460, 400)]:
		var state := _state([_fixture(1)], _table())
		state["name"] = long_name
		var cont := _item_rect(sheet.hub_layout(vp, state), "continue")
		var band := LeagueExtra.header_band(vp, bold, long_name, caption, cont.size.x + 12.0)
		var title: Rect2 = band["title_rect"]
		assert_gte(title.position.x, LeagueExtra.back_rect().end.x,
			"the title starts on BACK at %s" % vp)
		assert_lte(title.end.x, cont.position.x, "the title runs under CONTINUE at %s" % vp)
		assert_true(str(band["title"]) == long_name or str(band["title"]).ends_with("…"),
			"the title lost its name instead of being shortened at %s" % vp)
		if str(band["caption"]) != "":
			var strip: Rect2 = band["caption_rect"]
			assert_lte(strip.end.x, cont.position.x - 12.0,
				"the caption runs under CONTINUE at %s" % vp)
			assert_gte(strip.position.x, title.end.x,
				"the caption is painted through the title at %s" % vp)

	var wide := LeagueExtra.header_band(Vector2(1280, 720), bold, long_name, "", 152.0)
	assert_eq(str(wide["title"]), long_name, "a name that fits was shortened")


func test_the_report_keeps_back_in_the_top_left_chrome() -> void:
	var book := LeagueBook.new()
	var vp := Vector2(1280, 720)
	var events := [{"minute": 12, "kind": "goal", "player_name": "A. Striker"}]
	var items: Array = book.report_layout(vp, {
		"fixture": _fixture(1), "events": events, "day": "2026-08-15",
	})
	var backs: Array = []
	for item in items:
		if str(item["id"]) == "back":
			backs.append(item)
	assert_eq(backs.size(), 1, "the report offers more than one BACK")
	var back: Dictionary = backs[0]
	assert_true(bool(back.get("pinned", false)), "the report's BACK scrolls away")
	assert_eq(back["rect"], LeagueExtra.back_rect(), "the report's BACK left the header lane")
	assert_lt((back["rect"] as Rect2).end.y, LeagueChrome.HEADER,
		"the report's BACK sits below the header rule")
	assert_lt((back["rect"] as Rect2).position.y, vp.y - LeagueChrome.BAR_H,
		"the report's BACK is still a bottom door")


func test_a_played_row_grows_for_its_events() -> void:
	var sheet := LeagueSheet.new()
	var played := _fixture(1)
	played["status"] = "played"
	played["home_goals"] = 1
	played["away_goals"] = 0
	played["events"] = [
		{"minute": 12, "kind": "goal", "club_id": "A1", "player_name": "A. Striker"},
		{"minute": 40, "kind": "yellow", "club_id": "B1", "player_name": "C. Pivot"},
		{"minute": 66, "kind": "injury", "club_id": "A1", "player_name": "D. Back"},
	]
	var pending := _fixture(2)
	var plan := [played, pending]
	var items: Array = sheet.hub_layout(Vector2(913, 411), _state(plan, _table()))
	var rows: Array = []
	for item in items:
		if str(item["kind"]) == "row":
			rows.append(item)
	assert_eq(rows.size(), 2, "the hub lost a row")
	var played_row: Rect2 = rows[0]["rect"]
	var pending_row: Rect2 = rows[1]["rect"]
	assert_eq(played_row.size.y, LeagueBlock.height(played), "the played row is not its block")
	assert_gt(played_row.size.y, pending_row.size.y, "a played row did not grow for its events")
	assert_eq(pending_row.size.y, LeagueChrome.ROW_H, "a pending row left the planner's line")

	var places := LeagueBlock.columns(played_row)
	assert_lt(float(places["home_x"]) + float(places["home_w"]), float(places["away_x"]),
		"the event columns overlap")
	assert_lte(float(places["away_x"]) + float(places["away_w"]), played_row.end.x + 0.01,
		"the away column runs off its row")

	var bare := _fixture(3)
	bare["status"] = "played"
	assert_eq(LeagueBlock.height(bare), LeagueBlock.BASE, "an empty result lost its block")
	assert_eq(LeagueRoundup.lines({"fixture": bare, "events": []}).size(), 0,
		"an empty result grew a placeholder row")


func test_the_table_reads_the_full_club_name_at_every_surface() -> void:
	var row: Dictionary = _table()[0]
	assert_eq(LeagueTableView.club_label(row), str(row["club_name"]),
		"the table dropped the full club name")
	assert_eq(LeagueTableView.club_label({"club_abbr": "ENG-MUN1"}), "ENG-MUN1",
		"a row with no name lost its short form")
	var fx := _fixture(1)
	assert_eq(str(fx["home_name"]), "Home 1", "the fixture row lost its full name")
	assert_ne(str(fx["home_name"]), str(fx["home_abbr"]),
		"a fixture row still reads only the abbreviation")


func test_no_table_surface_paints_a_short_code() -> void:
	for path in ["res://scripts/ui/league_table_view.gd", "res://scripts/ui/league_plan_rows.gd",
			"res://scripts/ui/league_side_table.gd", "res://scripts/ui/wiki_league.gd",
			"res://scripts/ui/wiki_ledger.gd", "res://scripts/ui/wiki_team.gd",
			"res://scripts/ui/wiki_player_log.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s did not load" % path)
		assert_eq(text.find("club_abbr"), -1,
			"%s paints a club's abbreviation on a table surface" % path)
		assert_eq(text.find("home_abbr"), -1,
			"%s paints a club's abbreviation on a table surface" % path)
		assert_eq(text.find("away_abbr"), -1,
			"%s paints a club's abbreviation on a table surface" % path)


func test_a_side_table_row_paints_the_full_name_inside_its_column() -> void:
	var font: Font = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	var rail := LeagueSideTable.places(LeagueSideTable.box(Vector2(1280.0, 800.0), 600.0))
	var room := float(rail["club_w"])
	assert_gte(room, 100.0, "the side table's club column is too tight for a full name")
	var fits := 0
	for name in ["Arsenal", "Manchester United", "Coventry City", "Wolverhampton Wanderers"]:
		if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= room:
			fits += 1
	assert_gte(fits, 3, "the side table's club column cuts most full names")
	var shown: String = LeagueColumns.fit_name("Wolverhampton Wanderers", font, 12, room)
	if font.get_string_size("Wolverhampton Wanderers", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > room:
		assert_true(shown.ends_with("…"), "a name too wide for the side table is not cut")
		assert_lte(font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, room,
			"the cut side-table name still overflows its column")

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
	assert_eq(doors, 3, "the podium lost a door (BACK, TABLE, MAIN MENU)")
	assert_eq(extent, 1, "the podium lost its measured summary height")
	var summary := {
		"champion": {"club": "Arsenal", "club_id": "ENG-ARS1", "points": 90},
		"runner_up": {"club": "Liverpool", "club_id": "ENG-LIV1", "points": 88},
		"europe": [], "relegated": [], "places": LeagueRules.places(LeagueRules.defaults()),
		"top_scorers": [{"name": "A. Striker", "goals": 24}],
	}
	assert_false(summary.is_empty(), "a podium summary should be usable")
	assert_gt(_bottom(book.podium_layout(Vector2(1280, 720), {"summary": summary})), 0.0,
		"a podium with a summary has no height for the scroll window")

func test_month_helpers_walk_the_year() -> void:
	assert_eq(LeagueMonth.shift("2026-01", -1), "2025-12", "January did not step back a year")
	assert_eq(LeagueMonth.shift("2026-12", 1), "2027-01", "December did not step forward a year")
	assert_eq(LeagueMonth.label("2026-08"), "AUGUST 2026", "the month label is wrong")
	assert_eq(LeagueMonth.days("2026-02"), 28, "February 2026 is not 28 days")
	assert_eq(LeagueMonth.days("2028-02"), 29, "February 2028 is not a leap month")
	assert_eq(LeagueMonth.days("2026-04"), 30, "April is not 30 days")
	assert_eq(LeagueMonth.parse("bad"), LeagueMonth.parse("bad"), "a bad month is unstable")
	assert_eq(LeagueMonth.parse_key("bad"), LeagueMonth.key(int(LeagueMonth.parse("bad")[0]),
		int(LeagueMonth.parse("bad")[1])), "a malformed month key does not round-trip")
	assert_eq(LeagueMonth.key(2026, 13), "2027-01", "December + 1 is not the next January")
	assert_eq(LeagueMonth.first_weekday("2026-08"), 6, "1 August 2026 is not a Saturday")

func test_zone_colours_cover_every_band() -> void:
	for band in ["ucl", "uel", "uecl", "relegation", ""]:
		var colour := LeagueChrome.zone_color(band)
		assert_true(colour.a > 0.0, "band %s has no colour" % band)
	assert_eq(LeagueRules.zone_label(""), "", "a neutral row has a label")


func test_the_plan_rows_and_side_table_carry_the_shortlist_mark() -> void:
	var plan: Array = [_fixture(1), _fixture(2)]
	var interest := LeagueInterestMark.set_of(["A1"])
	var rows: Array = LeaguePlanSheet.layout(plan, interest, 24.0, 600.0, 72.0)
	assert_eq(rows.size(), 4, "two pending rows lost a chip or a row")
	assert_eq(str(rows[0]["id"]), "fixture:gw01-A1-B1", "the first row is not the first fixture")
	var followed_ink: Color = LeagueInterestMark.ink(interest, "A1")
	assert_eq(rows[0]["home_ink"], followed_ink, "the followed club carries no interest ink")
	assert_eq(rows[0]["away_ink"], LeagueInterestMark.ink(interest, "B1"),
		"the unfollowed club picked up the mark")
	assert_true(bool(rows[1]["followed"]), "a followed club's game still offers a toggle")
	assert_eq(str(rows[1]["id"]), "", "the followed game's chip is still a door")
	assert_eq((rows[2]["rect"] as Rect2).position.x, 24.0, "the second row left the lane")
	var box := LeagueSideTable.box(Vector2(1280.0, 800.0), 600.0)
	var side: Array = LeagueSideTable.layout(_table(), LeagueRules.defaults(), interest, box, 72.0)
	assert_eq(side.size(), 20, "the side table lost a place")
	assert_eq((side[0]["rect"] as Rect2).size.y, LeagueSideTable.ROW_H, "a side row left the pitch")
	var rail := LeagueSideTable.places(box)
	assert_eq((side[0]["places"] as Dictionary), rail, "the rows disagree about the rail")


func test_the_calendar_paint_band_reuses_the_draw_call() -> void:
	var book := LeagueBook.new()
	var band := _PaintProbe.new()
	band.book = book
	add_child(band)
	await get_tree().process_frame
	assert_true(band.painted, "the calendar body never reached its paint")
	band.queue_free()


class _PaintProbe extends Control:
	var book: LeagueBook = null
	var painted := false

	func _draw() -> void:
		book.draw_calendar_body(self, Vector2(1280, 800), UiChrome.fonts(), [], {"month": "2026-08"})
		painted = true


func test_the_pinned_bar_paints_its_own_ground_under_the_door() -> void:
	var vp := Vector2(913, 411)
	var items: Array = LeagueStartSheet.new().wizard_layout(vp,
		{"name": "S", "competitions": ["PL"], "calendar_mode": "generated",
			"advance_mode": "fixture_days", "touch": true})
	var door: Dictionary = _body_item(items, "create")
	assert_true(bool(door.get("pinned", false)), "the short wizard did not pin CREATE SEASON")
	assert_gt(float(door.get("bar", 0.0)), 0.0, "the pinned door carries no bar to paint")
	var body := _body(vp)
	body.set_sheet(items, vp, true, LeagueStartSheet.bar_of(items))
	var layer := _PinnedProbe.new()
	layer.body = body
	layer.fonts = UiChrome.fonts()
	layer.size = vp
	add_child(layer)
	await get_tree().process_frame
	assert_true(layer.painted, "the pinned layer never reached its paint")

	var plain := door.duplicate()
	plain.erase("bar")
	var probe := _PinnedProbe.new()
	probe.fonts = UiChrome.fonts()
	probe.size = vp
	probe.body = _body(vp)
	probe.body.pinned = [plain]
	add_child(probe)
	await get_tree().process_frame
	assert_true(probe.painted, "a pinned door with no bar did not paint")
	layer.queue_free()
	probe.queue_free()


class _PinnedProbe extends Control:
	var body: LeagueBody = null
	var fonts: Dictionary = {}
	var painted := false

	func _draw() -> void:
		for item in body.pinned:
			LeagueChrome.pinned_door(self, {}, item, fonts, size)
		painted = true


func test_the_table_sheet_keeps_back_top_left_and_its_doors_on_the_bar() -> void:
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var table: Array = LeagueBook.new().table_layout(vp,
			{"table": _table(), "rules": LeagueRules.defaults()})
		assert_eq(_item_rect(table, "back"), LeagueExtra.back_rect(),
			"table BACK is not in the top-left corner at %s" % vp)
		assert_true(_item(table, "back").get("pinned", false), "table BACK is inside the scroll at %s" % vp)
		assert_gt(_item_rect(table, "tbl:mode:compact").position.y, LeagueChrome.HEADER,
			"the reading doors left the bottom bar at %s" % vp)
		assert_almost_eq(_item_rect(table, "tbl:mode:full").end.y, vp.y - 8.0, 0.5,
			"the readings left the bottom bar at %s" % vp)


func test_a_portrait_phone_pans_to_the_last_table_column() -> void:
	var vp := Vector2(360.0, 780.0)
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	var body := LeagueBody.new()
	body.set_sheet(view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults()}), vp, true)
	assert_gt(body.max_hscroll(), 0.0, "the full table does not offer a sideways pan")
	body.pan_by(Vector2(1000.0, 0.0))
	var last := _item(body.button_rects(), "tbl:sort:away_ga")
	assert_false(last.is_empty(), "the away goals column has no door")
	assert_lte((last["rect"] as Rect2).end.x, vp.x + 0.5, "the last column is still off the window")
	body.free()


func test_the_report_columns_start_below_their_club_captions() -> void:
	var book := LeagueBook.new()
	var events := [
		{"minute": 6, "kind": "goal", "club_id": "A1", "player_name": "A. Striker"},
		{"minute": 9, "kind": "yellow", "club_id": "B1", "player_name": "C. Pivot"},
		{"minute": 9, "kind": "red", "club_id": "B1", "player_name": "C. Pivot"},
		{"minute": 52, "kind": "injury", "club_id": "A1", "player_name": "D. Back"},
	]
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var items: Array = book.report_layout(vp, {
			"fixture": _fixture(1), "events": events, "day": "2026-08-15",
		})
		var rows := {"home": [], "away": []}
		for item in items:
			if str(item["kind"]) != "event":
				continue
			var rect: Rect2 = item["rect"]
			assert_gte(rect.position.y, LeagueReportSheet.CAPTION_Y + 12.0,
				"a %s row shares the club caption's line at %s" % [item["side"], vp])
			(rows[str(item["side"])] as Array).append(rect.position.y)
		assert_eq(float((rows["home"] as Array)[0]), LeagueReportSheet.EVENTS_TOP,
			"the home column did not start on its first row at %s" % vp)
		assert_eq(float((rows["away"] as Array)[0]), LeagueReportSheet.EVENTS_TOP,
			"the away column did not start on its first row at %s" % vp)
		var away: Array = rows["away"]
		assert_eq(away.size(), 2, "a card row was lost at %s" % vp)
		assert_ne(float(away[0]), float(away[1]),
			"two cards at the same minute shared a row at %s" % vp)
		assert_gte(float(away[1]) - float(away[0]), LeagueReportSheet.ROW_H,
			"two card rows crowd each other at %s" % vp)


func test_the_system_advance_hint_names_the_pointer() -> void:
	var sheet := LeagueSystemSheet.new()
	for pair in [[false, "click to switch to every day"], [true, "tap to switch to every day"]]:
		var items: Array = sheet.layout(Vector2(1280, 720), {
			"date": "2026-08-15", "name": "S", "advance_mode": "fixture_days",
			"touch": bool(pair[0]),
		})
		assert_eq(str(_item(items, "sys:advance").get("hint", "")), str(pair[1]),
			"the ADVANCE hint names the wrong pointer (touch=%s)" % pair[0])
	var mirrored: Array = sheet.layout(Vector2(1280, 720), {
		"date": "2026-08-15", "advance_mode": "every_day", "touch": false,
	})
	assert_eq(str(_item(mirrored, "sys:advance").get("hint", "")),
		"click to switch to fixture days", "the hint does not name the mode it switches to")


func test_the_stats_empty_state_names_the_season_not_the_filters() -> void:
	var sheet := LeagueStatsSheet.new()
	var vp := Vector2(1280, 720)
	var unplayed: Array = sheet.layout(vp, {"name": "S", "reports": [],
		"played": 0, "leaders": [],
		"filters": {"league": "", "month": "", "team": "", "stat": "goals"}})
	assert_eq(_note(unplayed), "No matchday has been played yet.",
		"an unplayed season blamed the filters")
	assert_false(_has_caption(unplayed, "LEADERS"), "an empty LEADERS chart printed a bare heading")
	var filtered: Array = sheet.layout(vp, {"name": "S", "reports": [],
		"played": 20, "leaders": [],
		"filters": {"league": "PL", "month": "", "team": "mun", "stat": "goals"}})
	assert_eq(_note(filtered), "No matchdays match these filters.",
		"a played season emptied by its filters lost its note")
	var charted: Array = sheet.layout(vp, {"name": "S", "reports": [],
		"played": 20, "leaders": [{"name": "A. Scorer", "abbr": "ENG-MUN1", "stat_value": 3}],
		"filters": {"league": "", "month": "", "team": "", "stat": "goals"}})
	assert_true(_has_caption(charted, "LEADERS  ·  GOALS"), "a chart with rows lost its caption")

func _note(items: Array) -> String:
	for item in items:
		if str(item["kind"]) == "note":
			return str(item["label"])
	return ""

func _has_caption(items: Array, prefix: String) -> bool:
	for item in items:
		if str(item["kind"]) == "caption" and str(item["label"]).begins_with(prefix):
			return true
	return false

func _item(items: Array, id: String) -> Dictionary:
	for item in items:
		if str(item["id"]) == id:
			return item
	return {}


func test_a_phone_stats_sheet_lays_its_chips_and_stepper_for_a_finger() -> void:
	var sheet := LeagueStatsSheet.new()
	var vp := Vector2(913, 411)
	var filters := {"league": "", "month": "2026-09", "team": "", "stat": "goals"}
	var view := {"name": "S", "reports": [], "filters": filters,
		"competitions": [{"id": "PL", "short": "PL"}, {"id": "LL", "short": "LL"}]}
	var desk: Array = sheet.layout(vp, view)
	assert_almost_eq(_item_rect(desk, "statsleague:").size.y, 30.0, 0.01,
		"the desktop league chip left its dense pitch")
	assert_almost_eq(_item_rect(desk, "statsstat:goals").size.y, LeagueStatsSheet.STEP_H, 0.01,
		"the desktop stat chip left its dense pitch")
	assert_almost_eq(_item_rect(desk, "statsmonth:-1").size.y, LeagueStatsSheet.STEP_H, 0.01,
		"the desktop month arrow left its dense pitch")
	assert_almost_eq(_item_rect(desk, "statsmonth:-1").size.x, LeagueStatsSheet.STEP_W, 0.01,
		"the desktop month arrow left its dense width")

	var phone_view: Dictionary = view.duplicate()
	phone_view["touch"] = true
	var phone: Array = sheet.layout(vp, phone_view)
	var chips := 0
	for item in phone:
		var id := str(item["id"])
		var control: bool = id.begins_with("statsleague:") or id.begins_with("statsstat:") \
			or id.begins_with("statsmonth:")
		if not control:
			continue
		var rect: Rect2 = item["rect"]
		assert_gte(rect.size.y, UiChrome.TAP_H, "%s is under a finger at %s" % [id, vp])
		assert_lte(rect.end.x, vp.x - 24.0 + 0.01, "%s runs off the sheet" % id)
		chips += 1
	assert_gte(chips, 6, "the phone stats sheet lost a chip")
	var prev: Rect2 = _item_rect(phone, "statsmonth:-1")
	var next: Rect2 = _item_rect(phone, "statsmonth:1")
	var goals: Rect2 = _item_rect(phone, "statsstat:goals")
	assert_false(prev.intersects(next), "the month arrows share a band")
	assert_false(next.intersects(goals), "the stat chips sit on the month arrows")
	assert_gte(goals.position.y, prev.position.y, "the stat chips rose above their row")


func test_a_narrow_phone_wraps_the_stat_chips_under_the_month_stepper() -> void:
	var sheet := LeagueStatsSheet.new()
	var vp := Vector2(360, 780)
	var items: Array = sheet.layout(vp, {"name": "S", "reports": [], "touch": true,
		"filters": {"league": "", "month": "2026-09", "team": "", "stat": "goals"}})
	var step: Rect2 = _item_rect(items, "statsmonth:1")
	var goals: Rect2 = _item_rect(items, "statsstat:goals")
	var assists: Rect2 = _item_rect(items, "statsstat:assists")
	for rect in [step, goals, assists]:
		assert_lte(rect.end.x, vp.x - 24.0 + 0.01, "a stats control runs off a 360-wide phone")
	assert_gte(goals.position.y, step.end.y, "the stat chips still crowd the stepper")
	assert_false(goals.intersects(assists), "the wrapped stat chips overlap")
	assert_gte(goals.size.y, UiChrome.TAP_H, "the wrapped stat chip is under a finger")


func test_a_phone_calendar_lays_day_cells_and_month_doors_for_a_finger() -> void:
	var book := LeagueBook.new()
	var vp := Vector2(913, 411)
	var view := {"month": "2026-10", "day": "2026-10-17", "days": {}, "day_fixtures": [_fixture(1)]}
	var desk: Array = book.calendar_layout(vp, view)
	assert_almost_eq(_item_rect(desk, "day:2026-10-01").size.y, 28.0, 0.01,
		"the desktop calendar cell left its dense pitch")
	assert_almost_eq(_item_rect(desk, "month:1").size.y, 24.0, 0.01,
		"the desktop month door left its dense pitch")

	var phone_view: Dictionary = view.duplicate()
	phone_view["touch"] = true
	var phone: Array = book.calendar_layout(vp, phone_view)
	var back: Rect2 = _item_rect(phone, "back")
	var cells := 0
	var first := Rect2()
	for item in phone:
		if str(item["kind"]) != "cell":
			continue
		var rect: Rect2 = item["rect"]
		if cells == 0:
			first = rect
		cells += 1
		assert_gte(rect.size.y, UiChrome.TAP_H, "%s is under a finger at %s" % [item["id"], vp])
		assert_lte(rect.end.x, vp.x - 24.0 + 0.01, "%s runs off the sheet" % item["id"])
	assert_eq(cells, 31, "October should still have 31 cells")
	var prev: Rect2 = _item_rect(phone, "month:-1")
	var next: Rect2 = _item_rect(phone, "month:1")
	for door in [prev, next]:
		assert_gte((door as Rect2).size.y, UiChrome.TAP_H, "a month door is under a finger")
		assert_gte((door as Rect2).size.x, UiChrome.TAP_H, "a month door is narrower than a finger")
		assert_false((door as Rect2).intersects(back), "a month door sits on BACK")
		assert_lte((door as Rect2).end.x, vp.x - 24.0 + 0.01, "a month door runs off the sheet")
	assert_false(prev.intersects(next), "the month doors overlap")
	assert_lte(prev.end.y, first.position.y, "the grid rose under the month doors")


func test_a_phone_interest_sheet_lays_its_rows_and_remove_doors_for_a_finger() -> void:
	var sheet := LeagueInterestSheet.new()
	var vp := Vector2(913, 411)
	var club := {"id": "ENG-MUN1", "name": "Manchester United", "abbr": "ENG-MUN1"}
	var view := {"query": "man", "clubs": [club], "results": [club]}
	var desk: Array = sheet.layout(vp, view)
	assert_almost_eq(_item_rect(desk, "interest:add:ENG-MUN1").size.y, LeagueExtra.ROW_H, 0.01,
		"the desktop result row left its dense pitch")
	assert_almost_eq(_item_rect(desk, "club:ENG-MUN1").size.y, LeagueExtra.ROW_H, 0.01,
		"the desktop shortlist row left its dense pitch")
	assert_almost_eq(_item_rect(desk, "interest:remove:ENG-MUN1").size.y, LeagueExtra.ROW_H - 8.0, 0.01,
		"the desktop REMOVE door left its dense pitch")

	var phone_view: Dictionary = view.duplicate()
	phone_view["touch"] = true
	var phone: Array = sheet.layout(vp, phone_view)
	var result: Rect2 = _item_rect(phone, "interest:add:ENG-MUN1")
	var row: Rect2 = _item_rect(phone, "club:ENG-MUN1")
	var door: Rect2 = _item_rect(phone, "interest:remove:ENG-MUN1")
	assert_gte(result.size.y, UiChrome.TAP_H, "the result row is under a finger")
	assert_gte(row.size.y, UiChrome.TAP_H, "the shortlist row is under a finger")
	assert_gte(door.size.y, UiChrome.TAP_H, "REMOVE is under a finger")
	assert_true(row.encloses(door), "REMOVE left its row")
	assert_lte(door.end.x, row.end.x - 8.0 + 0.01, "REMOVE grew into the row's edge")
	assert_false(result.intersects(row), "the result row sits on the shortlist")


func test_a_phone_new_league_lays_its_toggles_for_a_finger() -> void:
	var sheet := LeagueStartSheet.new()
	var vp := Vector2(913, 411)
	var view := {"name": "S", "competitions": ["PL"], "calendar_mode": "generated",
		"advance_mode": "fixture_days"}
	var desk: Array = sheet.wizard_layout(vp, view)
	assert_almost_eq(_item_rect(desk, "mode:real").size.y, LeagueStartSheet.TOGGLE_H, 0.01,
		"the desktop toggle left its dense pitch")
	assert_almost_eq(_item_rect(desk, "wleague:PL").size.y, LeagueStartSheet.TOGGLE_H, 0.01,
		"the desktop league toggle left its dense pitch")

	var phone_view: Dictionary = view.duplicate()
	phone_view["touch"] = true
	var phone: Array = sheet.wizard_layout(vp, phone_view)
	var toggles := 0
	for item in phone:
		var id := str(item["id"])
		if not (id.begins_with("wleague:") or id.begins_with("mode:") or id.begins_with("adv:")):
			continue
		var rect: Rect2 = item["rect"]
		assert_gte(rect.size.y, UiChrome.TAP_H, "%s is under a finger at %s" % [id, vp])
		assert_lte(rect.end.x, vp.x - 24.0 + 0.01, "%s runs off the sheet" % id)
		toggles += 1
	assert_gte(toggles, 4, "the phone wizard drew no toggles")
	var leagues: Rect2 = _item_rect(phone, "wleague:PL")
	var modes: Rect2 = _item_rect(phone, "mode:real")
	var advances: Rect2 = _item_rect(phone, "adv:fixture_days")
	assert_lte(leagues.end.y, modes.position.y, "the mode toggles sit on the league toggles")
	assert_lte(modes.end.y, advances.position.y, "the advance toggles sit on the mode toggles")
	assert_false(leagues.intersects(_item_rect(phone, "name")), "the league toggle sits on the name field")


func test_a_short_new_league_pins_create_above_the_scroll() -> void:
	var sheet := LeagueStartSheet.new()
	var view := {"name": "S", "competitions": ["PL"], "calendar_mode": "generated",
		"advance_mode": "fixture_days"}
	for vp in [Vector2(913, 411), Vector2(640, 360)]:
		var items: Array = sheet.wizard_layout(vp, view)
		var create: Dictionary = _body_item(items, "create")
		assert_false(create.is_empty(), "the wizard lost its CREATE SEASON door at %s" % vp)
		assert_true(bool(create.get("pinned", false)),
			"CREATE SEASON was left below the fold at %s" % vp)
		var rect: Rect2 = create["rect"]
		assert_lte(rect.end.y, vp.y + 0.01, "CREATE SEASON runs off the sheet at %s" % vp)
		assert_gte(rect.position.y, vp.y - LeagueStartSheet.bar_h(true),
			"CREATE SEASON left the bar it is pinned to at %s" % vp)
		var bar: float = LeagueStartSheet.bar_of(items)
		assert_gt(bar, 0.0, "the wizard reserved no bar for its own door at %s" % vp)
		var body := _body(vp)
		body.set_sheet(items, vp, true, bar)
		assert_lte(body.position.y + body.size.y, rect.position.y + 0.01,
			"the scrolling list runs under CREATE SEASON at %s" % vp)
		assert_true(body.can_scroll(), "the wizard's rows are not scrollable at %s" % vp)


func test_a_tall_new_league_leaves_create_in_the_flow() -> void:
	var sheet := LeagueStartSheet.new()
	var vp := Vector2(1600, 900)
	var items: Array = sheet.wizard_layout(vp, {"name": "S", "competitions": ["PL"],
		"calendar_mode": "generated", "advance_mode": "fixture_days"})
	var create: Dictionary = _body_item(items, "create")
	assert_false(bool(create.get("pinned", false)),
		"a desktop sheet pinned CREATE SEASON although it fits in the flow")
	assert_eq(LeagueStartSheet.bar_of(items), 0.0, "a desktop sheet reserved a bar it does not draw")


func test_the_wizard_names_a_clipped_sheet_with_a_scroll_cue() -> void:
	var body := _body(Vector2(913, 411))
	var bound = func(_c: CanvasItem) -> void:
		pass
	body.painter = bound
	var items: Array = LeagueStartSheet.new().wizard_layout(Vector2(913, 411),
		{"name": "S", "competitions": ["PL"], "calendar_mode": "generated",
			"advance_mode": "fixture_days"})
	body.set_sheet(items, Vector2(913, 411), true, LeagueStartSheet.bar_of(items))
	body.cue = true
	assert_true(body.can_scroll(), "the wizard does not overflow a 411-unit sheet")
	assert_true(body.more_below(), "a clipped wizard drew no cue that it continues")
	body.scroll_to(body.max_scroll())
	assert_false(body.more_below(), "the cue outlived the last row")

	var tall := _body(Vector2(1600, 900))
	tall.painter = bound
	tall.set_sheet(LeagueStartSheet.new().wizard_layout(Vector2(1600, 900),
		{"name": "S", "competitions": ["PL"], "calendar_mode": "generated",
			"advance_mode": "fixture_days"}), Vector2(1600, 900), true, 0.0)
	tall.cue = true
	assert_false(tall.more_below(), "an unclipped desktop sheet drew a scroll cue")
