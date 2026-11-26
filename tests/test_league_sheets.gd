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

## #189: the hub keeps no side table. The standings live on the TABLES sheet, so
## a wide hub spends its whole width on the day's fixtures.
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
			# The default set is the Premier League, so one league toggle plus the
			# one selected reading of each shared pair.
			assert_eq(chosen, 3, "one choice per group should be selected")
			# NAME + LEAGUES caption + three country headers + eight league toggles
			# + two calendar + two advance + CREATE + BACK (#261).
			assert_eq(items.size(), 19, "the wizard is missing a control")

## #261: the wizard groups the leagues under their country and cascades the
## linked tiers, so a lower tier can never run without the tiers above it.
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
	# Turning a lower tier on selects every tier above it in that country.
	screen.wizard = {"competitions": ["PL"]}
	LeagueWizardActions.toggle_league(screen, "L2")
	assert_eq(screen.wizard["competitions"], ["PL", "CH", "L1", "L2"],
		"League Two did not bring the tiers above it")
	LeagueWizardActions.toggle_league(screen, "NL")
	assert_eq(screen.wizard["competitions"], ["PL", "CH", "L1", "L2", "NL"],
		"the National League did not complete the pyramid")
	# Turning a tier off clears it and everything below it.
	LeagueWizardActions.toggle_league(screen, "CH")
	assert_eq(screen.wizard["competitions"], ["PL"], "the English pyramid did not cascade off")
	# The top flight alone cannot be turned off: a save needs a competition.
	LeagueWizardActions.toggle_league(screen, "PL")
	assert_eq(screen.wizard["competitions"], ["PL"], "the wizard emptied itself")
	# Spain is one league under its own header; Germany cascades like England.
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
	# Every save is laid out: the body scrolls a long library instead of dropping
	# the rows past the seventh (REQ-P5-08).
	assert_eq(open_doors, 9, "the load list dropped a save")
	assert_eq(delete_doors, 9, "every save needs a delete door")
	assert_gte(last_row.end.y, LeagueChrome.HEADER + 26.0 + 46.0 * 8.0,
		"the ninth save was laid over an earlier row")

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

## The fixture picker's venue caption (#200): it sits in the centre column
## between the two club cards, so on a handset's narrowest gap a ground name
## must be shortened to the column instead of painted over both cards.
func test_a_venue_caption_is_fitted_to_its_centre_column() -> void:
	var font: Font = load("res://fonts/BarlowCondensed-Medium.ttf")
	# The gap on a handset is 130 design units, less 12 of air either side.
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

## #163: every sheet that shows BACK keeps it in the top-left corner, the hub's
## CONTINUE and the pre-match kick door take the top-right corner, and the table
## keeps only its two readings in the bottom bar.
func test_the_sheet_chrome_keeps_back_top_left_and_the_primary_top_right() -> void:
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var book := LeagueBook.new()
		var sheets := {
			"table": book.table_layout(vp, {"table": _table(), "rules": LeagueRules.defaults()}),
			"calendar": book.calendar_layout(vp, {"month": "2026-10", "day": "", "days": {}, "day_fixtures": []}),
			"report": book.report_layout(vp, {"fixture": _fixture(1), "events": [], "day": "x"}),
			"podium": book.podium_layout(vp, {"summary": {}}),
			"system": LeagueSystemSheet.new().layout(vp, {"date": "2026-08-15", "name": "S"}),
			"stats": LeagueExtra.new().stats_layout(vp, {"name": "S", "reports": []}),
			"interest": LeagueExtra.new().interest_layout(vp, {"query": "", "results": [], "clubs": []}),
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
		assert_eq(SettingsScreen.back_rect(vp), Rect2(24.0, 12.0, 116.0, 44.0),
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

## The body clips the scrolling rows to the band between the header and the
## bottom bar, and Godot clips a Control's own draw along with its children's.
## The doors a sheet pins stand outside that band — BACK and CONTINUE in the
## header lane, the table's readings in the bottom bar — so they are laid out in
## screen space and the body must keep them out of its rows and out of its
## scroll: a door that rode the clip or the scroll would drift off the corner the
## layout put it in, and a door painted under the clip is a door the player never
## sees (#284). `LeaguePinned` paints them on the unclipped layer above.
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
		assert_eq(body.pinned.size(), 3, "the table lost a pinned door at %s" % vp)
		assert_gte(reading.position.y, window.end.y, "FULL is inside the scrolling band at %s" % vp)
		# A scroll moves the rows and leaves the pinned doors where they were.
		body.scroll_to(400.0)
		var door := _body_item(body.pinned, "back")
		var row := _body_item(body.button_rects(), "back")
		assert_eq(door["rect"], row["rect"], "the scroll carried BACK off its corner at %s" % vp)
		# The calendar pins chips instead of buttons; the body paints both.
		var calendar: Array = LeagueBook.new().calendar_layout(vp, {
			"month": "2026-10", "day": "", "days": {}, "day_fixtures": []})
		body.set_sheet(calendar, vp, true, 0.0)
		assert_false(_body_item(body.pinned, "month:1").is_empty(),
			"the calendar's month chips were not pinned at %s" % vp)
		body.free()

## A body with the window `_ready` would give it, so its hit test has the band
## the screen lays it in (a bare Control has no size yet).
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

## A frozen body answers nothing: the delete question or the long-press menu
## owns the press while it is up, and a door under it must never fire.
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

## A page taller than the window scrolls: a row comes to the pointer as it
## rides up, then goes quiet under the bar, and a point outside the body answers
## nothing even while the page is scrolled.
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

## #168: a fixture's events are read as two sides — each row sits under the
## club stored on it, and the columns are in minute order. The old mixed run
## needed a club label on every entry; a column is the label now.
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
	# The club is the column, not a prefix on every line.
	assert_eq(LeagueRoundup.line(home[0]), "6' Y. Pino", "an entry repeated its club")
	assert_eq(LeagueRoundup.line(away[0]), "23' M. Cunha", "an away entry repeated its club")

## A row with no club id (an older save, a hand-made report) still reads, under
## the home column rather than disappearing.
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

## An assist is a bracket on the goal it served, never a row of its own. The
## synthetic report writes the assist as its own event at the same minute.
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
	# An assist row that never found its goal is not printed alone either.
	var orphan := {"fixture": _fixture(1), "events": [
		{"id": 2, "minute": 6, "kind": "goal", "club_id": "A1", "player_name": "Y. Pino"},
		{"id": 3, "minute": 7, "kind": "assist", "club_id": "A1", "player_name": "J. Eze"},
	]}
	assert_eq(LeagueRoundup.line(LeagueRoundup.lines(orphan)[0]), "6' Y. Pino",
		"a mismatched assist was attached to a goal")

## An own goal counts for the side that gained it — the club on the row — and is
## marked so the reader still sees whose mistake it was. It takes no assist.
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

## #171: a converted penalty is marked on the scorer's name, the shape an own
## goal takes on the live HUD. The report row and the roundup read the mark from
## one helper, so desktop and phone cannot disagree about it.
func test_a_penalty_goal_is_marked_on_its_scorer() -> void:
	var fixture := _fixture(1)
	assert_eq(LeagueRoundup.line({"minute": 12, "club_id": "A1",
		"player_name": "A. Striker", "penalty": true}), "12' A. Striker (PEN)",
		"the report did not mark the penalty")
	# A reopened save hands the flag back as SQLite's 1, not a bool.
	assert_eq(LeagueRoundup.line({"minute": 12, "detail": "A. Striker", "penalty": 1}),
		"12' A. Striker (PEN)", "a stored penalty lost its mark")
	assert_eq(LeagueRoundup.line({"minute": 30, "player_name": "B. Winger",
		"assist_name": "C. Pivot"}), "30' B. Winger (C. Pivot)",
		"an open-play goal took a mark")
	assert_false(LeagueRoundup.is_penalty({"player_name": "A. Striker"}),
		"an open-play goal read as a penalty")
	# The report layout carries the flag through on both sheet sizes.
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
	# Three lines (the assist rides its goal) and the back door.
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
	# One result block, BACK, and the hub's CONTINUE (#180).
	assert_eq(roundup.size(), 3, "the roundup lost its row or a header door")

## #180: a settled day's RESULTS carries the hub's CONTINUE in the hub's corner;
## BACK stays the leave control beside it, and a single match report — a drill
## into one fixture, not a day to move on from — stays read-only.
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

## #180: whatever the save is called, the header's title and caption stay in the
## lane between BACK and the right-hand door. The title is shortened instead of
## painted under CONTINUE, and the caption starts only where the title ends.
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
	# A desktop lane leaves the name whole, so fitting only touches what cannot fit.
	var wide := LeagueExtra.header_band(Vector2(1280, 720), bold, long_name, "", 152.0)
	assert_eq(str(wide["title"]), long_name, "a name that fits was shortened")

## #162: the report keeps the league's chrome — BACK top-left, not a bottom door.
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

## #168: a played hub row is a block tall enough for both columns; a pending row
## keeps the planner's one line. The hub and the calendar read the same height.
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
	# The two event columns share the row and never overlap.
	var places := LeagueBlock.columns(played_row)
	assert_lt(float(places["home_x"]) + float(places["home_w"]), float(places["away_x"]),
		"the event columns overlap")
	assert_lte(float(places["away_x"]) + float(places["away_w"]), played_row.end.x + 0.01,
		"the away column runs off its row")
	# An empty result is still a block, and it prints no filler line.
	var bare := _fixture(3)
	bare["status"] = "played"
	assert_eq(LeagueBlock.height(bare), LeagueBlock.BASE, "an empty result lost its block")
	assert_eq(LeagueRoundup.lines({"fixture": bare, "events": []}).size(), 0,
		"an empty result grew a placeholder row")

## #168: the table is the one season pose that keeps abbreviations; the hub, the
## calendar, the roundup and the report print the club's full name.
func test_the_table_keeps_abbreviations_while_rows_print_names() -> void:
	var row: Dictionary = _table()[0]
	assert_eq(LeagueTableView.club_label(row), str(row["club_abbr"]),
		"the table dropped its abbreviation")
	assert_eq(LeagueTableView.club_label({"club_name": "Coventry City"}), "Coventry City",
		"a row with no short form lost its name")
	var fx := _fixture(1)
	assert_eq(str(fx["home_name"]), "Home 1", "the fixture row lost its full name")
	assert_ne(str(fx["home_name"]), str(fx["home_abbr"]),
		"a fixture row still reads only the abbreviation")

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
		"champion": {"club": "Arsenal", "club_id": "ARS", "points": 90},
		"runner_up": {"club": "Liverpool", "club_id": "LIV", "points": 88},
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

# ------------------------------------------------------------ row modules ---

## The plan rows carry the shortlist's mark and the hub's side table carries its
## own: split out of the hub, both still answer the same questions the hub's
## paint asks them.
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

## The paint path is one frame re-entering the `_draw` call it arrived from
## (see `LeagueBook._draw_calendar_body`); headless it is a straight call.
func test_the_calendar_paint_band_reuses_the_draw_call() -> void:
	var book := LeagueBook.new()
	var band := _PaintProbe.new()
	band.book = book
	add_child(band)
	await get_tree().process_frame
	assert_true(band.painted, "the calendar body never reached its paint")
	band.queue_free()

## A tiny canvas item the engine really paints, so the band's paint call runs
## under a frame rather than outside `_draw`.
class _PaintProbe extends Control:
	var book: LeagueBook = null
	var painted := false

	func _draw() -> void:
		book.draw_calendar_body(self, Vector2(1280, 800), UiChrome.fonts(), [], {"month": "2026-08"})
		painted = true

## #163: the table sheet keeps its chrome where the other sheets keep theirs —
## BACK top-left, the reading doors on the bottom bar — at both widths.
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

## The full table is wider than a portrait phone: the body offers the sideways
## pan and the last column is reachable by dragging.
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

func _item(items: Array, id: String) -> Dictionary:
	for item in items:
		if str(item["id"]) == id:
			return item
	return {}
