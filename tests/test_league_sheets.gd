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

## #124: a played row is a result, not a plan — it keeps its row on the hub and
## loses the AUTO/WATCH chip, so the score sits where the chip was.
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
	# CONTINUE's caption only promises a hand-off while a watch is still unplayed.
	assert_false(LeagueSheet.watch_pending([played]), "a played watch still claims CONTINUE opens it")
	assert_true(LeagueSheet.watch_pending(plan), "an unplayed watch lost its CONTINUE caption")
	assert_false(LeagueSheet.watch_pending([]), "an empty day claims a pending watch")

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

## #102: the hub's side table carries the same compact record as the TABLE
## sheet (`#`, club, P W D L GF GA GD PTS). It paints the abbreviation, so the
## club column gives the numbers more of the lane, and every column stays inside
## the row it belongs to.
func test_the_hub_side_table_carries_the_compact_record() -> void:
	var sheet := LeagueSheet.new()
	var keys: Array = []
	for col in LeagueColumns.COMPACT_COLS:
		if bool(col["num"]):
			keys.append(str(col["key"]))
	assert_eq(keys, ["played", "won", "drawn", "lost", "gf", "ga", "gd", "points"],
		"the compact column order moved")
	for vp in [Vector2(760, 640), Vector2(1280, 720), Vector2(1600, 900)]:
		var item := {}
		for candidate in sheet.hub_layout(vp, _state([], _table())):
			if str(candidate["kind"]) == "table_row":
				item = candidate
				break
		assert_false(item.is_empty(), "the wide hub laid out no table at %s" % vp)
		var places: Dictionary = item["places"]
		var rect: Rect2 = item["rect"]
		var rail := places["cols"] as Array
		assert_eq(rail.size(), 8, "the hub side table lost a column at %s" % vp)
		assert_eq(rail.map(func(c): return str(c["key"])), keys,
			"the hub side table paints another column set at %s" % vp)
		assert_gt(float(places["club_x"]), float(places["pos_x"]), "# and club overlap at %s" % vp)
		var previous := float(places["club_x"]) + float(places["club_w"])
		for col in rail:
			assert_gt(float(col["right"]) - float(col["w"]), previous - 0.01,
				"%s overlaps the club abbreviation at %s" % [col["label"], vp])
			previous = float(col["right"])
		assert_lte(previous, rect.end.x + 0.01, "PTS is drawn outside the hub row at %s" % vp)
		assert_gte(float(places["club_w"]), LeagueSheet.HUB_CLUB_MIN - 0.01,
			"the abbreviation column is too narrow at %s" % vp)

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

## The compact column set (#, club, P W D L GF GA GD PTS) has to fit inside the
## row at every width the handheld overlay scale can produce: the numbers ride
## one rail measured from the row's own right edge, and the club column keeps
## whatever is left, so a long name is shortened instead of painted over the
## record.
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

## A portrait phone is laid out narrow by the handheld overlay scale. Where the
## window can hold the whole record at the rail's floor it all fits; where it
## cannot, the row keeps that floor and the sheet pans sideways, so the numbers
## never crowd the club name or each other.
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

## Columns must track the sheet, not sit on desktop-only offsets: a wider row
## moves the whole rail right with it.
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

## A name wider than its column must be shortened, not painted over the record.
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

## #126: the caption floor lifts the shortest type on the hub and the calendar to
## ten design units. The chip label and the day-cell counter must still fit the
## surface that carries them on a phone and on a desktop window.
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
			# Counter right-aligned 3 units in, day number 4 units from the left.
			assert_gte(rect.size.x, counter + 20.0,
				"the 10/10 counter overruns its cell at %s" % vp)
		assert_eq(cells, 31, "October should still have 31 cells at %s" % vp)

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

## #125: the run mixes both sides' goals, so every entry names the club that
## scored it and the goals read in minute order — not in the order they were
## stored (head first, then away).
func test_a_roundup_row_names_the_club_of_every_scorer() -> void:
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
	var entries: Array = LeagueRoundup.entries(report)
	assert_eq(entries, [
		"HOM 6' Y. Pino", "HOM 7' J. Mateta", "AWY 23' M. Cunha", "HOM 58' J. Mateta",
	], "the roundup lost its clubs or its minute order")
	# A card is not a goal, and the away side's goals follow the home side's.
	assert_eq(entries.size(), 4, "the roundup listed something that was not a goal")
	var once := LeagueRoundup.run(report, UiChrome.fonts()["med"], 600.0, 10)
	assert_eq(once, "  ·  ".join(entries), "a run that fits dropped a goal")

## A row cannot grow, so a busy scoreline names what it can and counts the rest:
## the rule the whistle card uses (DR-20261125-04), never a silent drop.
func test_a_roundup_run_that_does_not_fit_counts_the_rest() -> void:
	var report := {"fixture": _fixture(1), "events": []}
	for i in range(6):
		(report["events"] as Array).append({
			"id": i, "minute": 5 + i, "kind": "goal", "club_id": "A1",
			"player_name": "A. Striker",
		})
	var all: Array = LeagueRoundup.entries(report)
	var font: Font = UiChrome.fonts()["med"]
	var wide := LeagueRoundup.run(report, font, 900.0, 10)
	assert_eq(wide, LeagueRoundup.SEP.join(all), "a run with room counted goals it could show")
	var narrow := LeagueRoundup.run(report, font, 160.0, 10)
	assert_ne(narrow, wide, "a run measured for 160 units kept every entry")
	var parts: PackedStringArray = narrow.split(LeagueRoundup.SEP)
	var shown := parts.size()
	assert_gte(shown, 1, "a run too wide for its row showed no scorer at all")
	assert_lt(shown, all.size(), "a run measured for 160 units kept every entry")
	for i in range(shown):
		assert_true(str(parts[i]).begins_with(str(all[i])), "the run reordered or dropped a goal")
	var tail := str(parts[shown - 1])
	assert_true(tail.ends_with("+%d" % (all.size() - shown)),
		"the run miscounted what it dropped: %s" % tail)
	var room := 160.0 + UiChrome.text_width(font, "  +5", 10)
	assert_lte(UiChrome.text_width(font, narrow, 10), room,
		"the counted run runs past the row it was measured for")
	assert_eq(LeagueRoundup.run({"fixture": _fixture(1), "events": []}, font, 900.0, 10), "",
		"a goalless report produced a run")

## Rows stored before a club id was written (and test rows) still read: the
## scorer is named, without a prefix the fixture cannot prove.
func test_a_scorer_with_no_known_club_still_reads() -> void:
	var fixture := _fixture(1)
	assert_eq(LeagueRoundup.entry(fixture, {"minute": 12, "player_name": "A. Striker"}),
		"12' A. Striker", "a clubless goal invented a club")
	assert_eq(LeagueRoundup.entry(fixture, {"minute": 12, "club_id": "ZZ", "player_name": "A. Striker"}),
		"12' A. Striker", "a stranger's goal took the home club's label")

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

# -------------------------------------------------------------- full table ---

## #72/#74: the full reading is the compact strip plus the overall, home and
## away columns. On the phone landscape design space (`--ui-scale` on a 1080p
## handset) every one of them has to sit inside the row.
func test_the_full_table_shows_every_column_on_a_phone_landscape() -> void:
	for vp in [Vector2(913, 411), Vector2(873, 393)]:
		var view := LeagueTableView.new()
		view.mode = LeagueTableView.FULL
		var items: Array = view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults()})
		var rows := 0
		var heads := []
		var widest := 0.0
		for item in items:
			if str(item["kind"]) == "table_row":
				rows += 1
				widest = maxf(widest, (item["rect"] as Rect2).end.x)
			elif str(item["kind"]) == "head":
				heads.append(str(item["id"]))
		assert_eq(rows, 20, "the full table lost rows at %s" % vp)
		assert_eq(heads.size(), 22, "the full header lost a column at %s" % vp)
		assert_true(heads.has("tbl:sort:points"), "PTS is not sortable at %s" % vp)
		assert_true(heads.has("tbl:sort:home_gf"), "the home goals are not sortable at %s" % vp)
		assert_true(heads.has("tbl:sort:away_ga"), "the away goals against are missing at %s" % vp)
		assert_lte(widest, vp.x - 24.0, "the full table runs off a phone landscape sheet at %s" % vp)

func test_the_full_header_names_its_three_groups() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	var captions: Array = []
	for item in view.layout(Vector2(913, 411), {"table": _table(), "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "caption":
			captions.append(str(item["label"]))
	assert_eq(captions, ["OVERALL", "HOME", "AWAY"], "the full header lost a group caption")

func test_the_table_defaults_to_compact_on_a_phone_and_full_on_desktop() -> void:
	var phone := LeagueTableView.new()
	var heads: Array = []
	for item in phone.layout(Vector2(913, 411), {"table": _table(), "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "head":
			heads.append(str(item["id"]))
	assert_eq(phone.mode, LeagueTableView.COMPACT, "a phone did not open the compact table")
	assert_eq(heads.size(), 10, "the compact header should be #, club and the whole overall record")
	for key in ["played", "won", "drawn", "lost", "gf", "ga", "gd", "points"]:
		assert_true(heads.has("tbl:sort:" + key),
			"compact does not offer a %s column to sort by (#102)" % key)
	var desktop := LeagueTableView.new()
	desktop.layout(Vector2(1600, 900), {"table": _table(), "rules": LeagueRules.defaults()})
	assert_eq(desktop.mode, LeagueTableView.FULL, "a desktop did not open the full table")

## #102: a column Compact now shows is a column Compact sorts by — the whole
## overall record behaves like any other visible field.
func test_the_compact_strip_sorts_by_the_overall_columns_it_shows() -> void:
	var rows: Array = _table()
	rows[0]["gf"] = 3
	rows[1]["gf"] = 30
	rows[2]["gf"] = 10
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.COMPACT
	for key in ["won", "drawn", "lost", "gf", "ga"]:
		assert_true(view.press("tbl:sort:" + key, null), "compact did not take a %s sort" % key)
	view.sort = "gf"
	view.dir = -1
	var goals: Array = []
	for item in view.layout(Vector2(913, 411), {"table": rows, "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "table_row":
			goals.append(int((item["row"] as Dictionary)["gf"]))
	assert_eq(goals[0], 30, "the compact strip did not sort by goals scored")

## A full table is wider than a portrait phone: the body offers the sideways
## pan and every column is reachable by dragging.
func test_the_full_table_pans_sideways_on_a_portrait_phone() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	var vp := Vector2(360.0, 780.0)
	var items: Array = view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults()})
	var body := LeagueBody.new()
	body.set_sheet(items, vp, true)
	assert_gt(body.max_hscroll(), 0.0, "the full table does not offer a sideways pan")
	body.pan_by(Vector2(1000.0, 0.0))
	assert_almost_eq(body.hscroll, body.max_hscroll(), 0.5, "the pan did not reach the last column")
	var last: Dictionary = {}
	for item in body.button_rects():
		if str(item["id"]) == "tbl:sort:away_ga":
			last = item
	assert_false(last.is_empty(), "the away goals column has no door")
	var rect: Rect2 = last["rect"]
	assert_lte(rect.end.x, vp.x + 0.5, "the last column is still off the window after the pan")
	body.pan_by(Vector2(-1.0e7, 0.0))
	assert_eq(body.hscroll, 0.0, "the pan ran past the first column")
	body.free()

## Sorting is the player's order; the `#` column and the zone bands stay the
## league's official place, so a sorted table never lies about the standings.
func test_sorting_orders_the_rows_but_keeps_the_official_place() -> void:
	var rows: Array = _table()
	rows[0]["points"] = 10
	rows[1]["points"] = 30
	rows[2]["points"] = 20
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	view.sort = "points"
	view.dir = -1
	var items: Array = view.layout(Vector2(1600, 900),
		{"table": rows, "rules": LeagueRules.defaults()})
	var points: Array = []
	var by_position := {}
	for item in items:
		if str(item["kind"]) == "table_row":
			var row: Dictionary = item["row"]
			points.append(int(row["points"]))
			by_position[int(row["position"])] = str(item["zone"])
	assert_eq(points[0], 30, "the high side did not come first")
	assert_eq(points[1], 20, "the rows are not sorted by points")
	assert_eq(points[2], 10, "the rows are not sorted by points")
	assert_eq(by_position[1], "ucl", "the champion's band left its place")
	assert_eq(by_position[20], "relegation", "the drop lost its band")
	view.dir = 1
	var ascending: Array = []
	for item in view.layout(Vector2(1600, 900), {"table": rows, "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "table_row":
			ascending.append(int((item["row"] as Dictionary)["points"]))
	assert_eq(ascending[0], 0, "the low side did not come first when reversed")

func test_a_mode_press_flips_the_reading_and_a_header_press_sorts() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	assert_true(view.press("tbl:mode:compact", null), "the compact door did nothing")
	assert_eq(view.mode, LeagueTableView.COMPACT, "the compact door did not take")
	assert_false(view.press("tbl:mode:compact", null), "the reading already on screen was taken again")
	assert_true(view.press("tbl:mode:full", null), "the full door did nothing")
	assert_eq(view.mode, LeagueTableView.FULL, "the full door did not take")
	assert_false(view.press("tbl:mode:sideways", null), "an unknown reading was taken")
	assert_true(view.press("tbl:sort:points", null), "a header press did nothing")
	assert_eq(view.sort, "points", "the header press did not sort")
	assert_eq(view.dir, -1, "a numeric column should start on the high side")
	view.press("tbl:sort:points", null)
	assert_eq(view.dir, 1, "a second tap did not reverse")
	view.press("tbl:sort:club", null)
	assert_eq(view.dir, 1, "the club column should start A-Z")
	assert_false(view.press("tbl:sort:position", null), "the place column is not sortable")
	assert_false(view.press("nope", null), "an unknown door was taken")

## A sort is only worth honouring in a reading that shows the column: the
## compact strip keeps the player's full-table sort stored for when they come
## back to it, but lists the official order while it is hidden.
func test_a_hidden_sort_column_leaves_the_compact_strip_in_place() -> void:
	var rows: Array = _table()
	rows[0]["home_gf"] = 3
	rows[1]["home_gf"] = 30
	rows[2]["home_gf"] = 10
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.COMPACT
	view.sort = "home_gf"
	view.dir = -1
	var positions: Array = []
	for item in view.layout(Vector2(913, 411), {"table": rows, "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "table_row":
			positions.append(int((item["row"] as Dictionary)["position"]))
	assert_eq(positions[0], 1, "the compact strip sorted by a column it does not show")
	view.mode = LeagueTableView.FULL
	var by_home: Array = []
	for item in view.layout(Vector2(1600, 900), {"table": rows, "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "table_row":
			by_home.append(int((item["row"] as Dictionary)["home_gf"]))
	assert_eq(by_home[0], 30, "the full reading lost the sort it was given")

func test_attach_clears_a_reading_without_a_save() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	view.sort = "points"
	view.dir = 1
	view.attach(null)
	assert_eq(view.mode, "", "a table with no save kept a reading")
	assert_eq(view.sort, "", "a table with no save kept a sort")
	assert_eq(view.dir, -1, "a table with no save kept a direction")
