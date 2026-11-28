extends GdToolsTest


const SEED := 515151


class PanelStub extends RefCounted:
	func close() -> void:
		pass


class Fake extends RefCounted:
	var season: LeagueSeason = null
	var touch := false
	var mode := LeagueScreen.MODE_HUB
	var panel := PanelStub.new()
	var europe := {"comp": "UCL", "tab": "", "round": ""}
	var europe_draw := {"competition": "UCL", "round": "Q1", "revealed": 0, "done": false,
		"t": 0.0}
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1

	func push_page() -> void:
		pass


func _screen(touch: bool = false) -> Fake:
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	var fake := Fake.new()
	fake.season = LeagueSeason.create("Europe UI", "generated", "fixture_days", SEED,
		["PL"], false, [], true)
	fake.touch = touch
	return fake


func _settle(season: LeagueSeason, competition_id: String, round_id: String) -> void:
	PLDatabase.execute(
		"UPDATE league_fixture SET status = 'played', home_goals = 2, away_goals = 1 "
		+ "WHERE competition_id = ? AND stage = ?;", [competition_id, round_id])
	if round_id == LeagueUefa.LEAGUE_STAGE:
		season.record.standings.recompute()
	else:
		PLDatabase.execute(
			"UPDATE cup_tie SET home_goals = 2, away_goals = 1, winner_club_id = home_club_id "
			+ "WHERE competition_id = ? AND round_id = ?;", [competition_id, round_id])
		if LeagueEurope.KO_ROUNDS.has(round_id):
			LeagueUefaKnockout.after_round(season, competition_id, round_id)
	LeagueUefaState.advance(season, competition_id, round_id)


func _run_to(season: LeagueSeason, competition_id: String, last: String) -> void:
	for rid in LeagueUefa.round_ids(competition_id):
		var round_id := str(rid)
		if not LeagueUefa.has_stage(competition_id, round_id):
			continue
		_settle(season, competition_id, round_id)
		if round_id == last:
			return


func _ids(items: Array) -> Array:
	var out: Array = []
	for item in items:
		out.append(str(item.get("id", "")))
	return out


func _kinds(items: Array) -> Dictionary:
	var out := {}
	for item in items:
		out[str(item.get("kind", ""))] = true
	return out


func test_the_hub_and_draw_lay_out_on_desktop_and_phone() -> void:
	var fake := _screen(false)
	var view: Dictionary = LeagueEuropeView.hub(fake)
	assert_eq((view["cards"] as Array).size(), 3, "the hub does not read three cards")
	assert_gte((view["tonight"] as Array).size(), 1, "the hub has no UEFA night on its opening day")
	assert_eq((view["draws"] as Array).size(), 1, "the hub does not show one pending draw door")
	assert_eq(int(view["draws_more"]), 2, "the hub does not count the other pending draws")
	var sheet := LeagueEuropeSheet.new()
	for touch in [false, true]:
		fake.touch = touch
		var vp := Vector2(1600, 900) if not touch else Vector2(913, 411)
		var items: Array = sheet.layout(vp, LeagueEuropeView.hub(fake))
		var ids := _ids(items)
		var kinds := _kinds(items)
		assert_true(kinds.has("europe_card"), "the hub laid out no competition cards")
		assert_true(ids.has("europe:comp:UCL"), "the UCL card has no door")
		assert_true(ids.has("europe:comp:UEL"), "the UEL card has no door")
		assert_true(ids.has("continue"), "the hub lost CONTINUE")
		assert_true(ids.has("back"), "the hub lost BACK")
		for item in items:
			var rect: Rect2 = item["rect"]
			assert_lte(rect.end.x, vp.x + 0.5, "a hub item runs off the right at %s" % vp)
	var draw_view: Dictionary = LeagueEuropeView.draw(fake)
	var draw := LeagueEuropeDraw.new()
	var empty: Array = draw.layout(Vector2(1600, 900), draw_view)
	var empty_kinds := _kinds(empty)
	assert_true(empty_kinds.has("draw_pot"), "the draw laid out no pot")
	assert_false(empty_kinds.has("draw_row"), "an unopened draw already shows fixtures")
	assert_true(_ids(empty).has("europe:draw:skip"), "the draw has no SKIP")
	fake.europe_draw["revealed"] = 3
	var opened: Array = draw.layout(Vector2(1600, 900), LeagueEuropeView.draw(fake))
	var rows := 0
	for item in opened:
		if str(item["kind"]) == "draw_row":
			rows += 1
	assert_eq(rows, 3, "the ceremony does not reveal one pair at a time")
	fake.europe_draw["done"] = true
	var settled: Array = draw.layout(Vector2(913, 411), LeagueEuropeView.draw(fake))
	assert_true(_ids(settled).has("europe:draw:open"), "a settled draw has no stage door")
	assert_false(_ids(settled).has("europe:draw:skip"), "a settled draw still offers SKIP")
	fake.season.close()


func test_the_wizard_offers_europe_and_the_panel_fits_a_phone() -> void:
	var start := LeagueStartSheet.new()
	var view := {"name": "", "competitions": ["PL"], "calendar_mode": "generated",
		"advance_mode": "fixture_days", "uefa": true, "touch": true}
	var items: Array = start.wizard_layout(Vector2(913, 411), view)
	var found: Dictionary = {}
	for item in items:
		if str(item.get("id", "")) == "wuefa":
			found = item
	assert_false(found.is_empty(), "the wizard has no UEFA toggle")
	assert_true(bool(found.get("selected", false)), "the UEFA toggle does not default on")
	var phone := Vector2(913, 411)
	var fit: Dictionary = LeaguePanel.metrics(phone, LeaguePanel.ITEMS.size())
	var lines: int = int(ceil(float(LeaguePanel.ITEMS.size()) / float(fit["cols"])))
	assert_lte(float(fit["head"]) + float(lines) * (float(fit["row"]) + float(fit["gap"])) - float(fit["gap"]),
		phone.y - LeaguePanel.FOOT, "the drawer's items do not fit a phone")
	assert_gte(float(fit["row"]), LeaguePanel.TAP_FLOOR, "a phone row fell under the tap floor")
	var panel := LeaguePanel.new()
	var total := LeaguePanel.ITEMS.size()
	panel.cups = true
	panel.europe_on = true
	assert_eq(panel.items().size(), total, "the drawer lost a door")
	panel.europe_on = false
	assert_eq(panel.items().size(), total - 1,
		"the drawer still offers EUROPE on a domestic-only save")
	panel.cups = false
	assert_eq(panel.items().size(), total - 2,
		"the drawer still offers CUPS or EUROPE on a save without them")


func test_every_panel_row_fits_a_phone_and_keeps_its_tap() -> void:
	var panel := LeaguePanel.new()
	panel.touch = true
	panel.cups = true
	panel.europe_on = true
	panel.open()
	panel.settle()
	var rows: Array = panel.items()
	for vp in [Vector2(913, 411), Vector2(411, 914), Vector2(1024, 600)]:
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var rect: Rect2 = panel.item_rect(vp, i)
			assert_gte(rect.size.y, LeaguePanel.TAP_FLOOR,
				"%s is below the tap floor at %s" % [row["id"], vp])
			assert_lte(rect.end.y, vp.y - 12.0, "%s falls off the panel at %s" % [row["id"], vp])
			assert_eq(panel.hit(rect.get_center(), vp), str(row["id"]),
				"%s is not hittable at %s" % [row["id"], vp])


func test_the_stage_reads_its_table_qualifying_and_bracket() -> void:
	var fake := _screen(false)
	_run_to(fake.season, "UCL", "LP")
	assert_true(LeagueUefa.has_stage("UCL", "KOPO"), "the knockout play-off never opened")
	LeagueEurope.mark_seen(fake.season.save, "UCL", "KOPO")
	var stage := LeagueEuropeStage.new()
	var settled: Dictionary = LeagueEuropeView.stage(fake)
	assert_eq(str(settled["draw_round"]), "KOPO", "a shown draw has no re-read door")
	assert_true(_ids(stage.layout(Vector2(1600, 900), settled)).has("europe:draw:UCL:KOPO"),
		"the stage has no door to the settled draw")
	fake.europe["tab"] = "table"
	var view: Dictionary = LeagueEuropeView.stage(fake)
	assert_eq((view["table"] as Array).size(), 36, "the league phase table lost a club")
	var items: Array = stage.layout(Vector2(1600, 900), view)
	var rows: Array = []
	for item in items:
		if str(item["kind"]) == "eu_row":
			rows.append(item)
	assert_eq(rows.size(), 36, "the table laid out %d rows" % rows.size())
	for i in range(rows.size()):
		var zone := str(rows[i]["zone"])
		var want := "r16" if i < 8 else ("kopo" if i < 24 else "out")
		assert_eq(zone, want, "row %d paints the wrong band" % (i + 1))
	fake.europe["tab"] = "bracket"
	var bracket: Dictionary = LeagueEuropeView.stage(fake)
	var cols: Array = stage.layout(Vector2(1600, 900), bracket)
	var ties := 0
	var heads := 0
	for item in cols:
		if str(item["kind"]) == "eu_tie":
			ties += 1
		if str(item["kind"]) == "eu_col":
			heads += 1
	assert_eq(heads, 1, "the bracket does not open on one round")
	assert_eq(ties, 8, "the bracket does not show eight play-off ties")
	fake.touch = true
	fake.europe["tab"] = "qualifying"
	fake.europe["round"] = "Q1"
	var phone: Array = stage.layout(Vector2(913, 411), LeagueEuropeView.stage(fake))
	var phone_cols := 0
	for item in phone:
		if str(item["kind"]) == "eu_col":
			phone_cols += 1
			assert_eq(str(item["round"]["id"]), "Q1", "the phone shows the wrong round")
		if str(item["kind"]) == "eu_badge":
			assert_true(str(item["id"]).begins_with("europe:comp:"),
				"a drop badge is not a door")
	assert_eq(phone_cols, 1, "the phone stacks every qualifying round at once")
	fake.europe["tab"] = "table"
	var touch_rows: Array = stage.layout(Vector2(913, 411), LeagueEuropeView.stage(fake))
	var widest := 0.0
	for item in touch_rows:
		if str(item["kind"]) == "eu_row":
			widest = maxf(widest, (item["rect"] as Rect2).size.x)
	assert_gte(widest, 380.0, "the phone table truncates instead of scrolling sideways")
	fake.season.close()


func test_europe_actions_open_stage_draw_and_tick() -> void:
	var fake := _screen(false)
	LeagueEuropeActions.open(fake)
	assert_eq(fake.mode, LeagueScreen.MODE_EUROPE, "EUROPE did not open the hub")
	assert_eq(str(fake.europe["comp"]), "UCL", "the hub did not pick the first competition")
	assert_true(LeagueEuropeActions.press(fake, "europe:comp:UEL"), "a card press was ignored")
	assert_eq(fake.mode, LeagueScreen.MODE_EUROPE_STAGE, "a card did not open its stage")
	assert_eq(str(fake.europe["comp"]), "UEL", "the stage kept the wrong competition")
	assert_eq(str(fake.europe["tab"]), "qualifying", "qualifying did not open for UEL")
	assert_true(LeagueEuropeActions.press(fake, "europe:tab:bracket"), "a tab press was ignored")
	assert_eq(str(fake.europe["tab"]), "bracket", "BRACKET did not stick")
	assert_true(LeagueEuropeActions.press(fake, "europe:round:Q1"), "a round press was ignored")
	assert_eq(str(fake.europe["round"]), "Q1", "the phone round did not stick")
	assert_true(LeagueEuropeActions.press(fake, "europe:draw:UEL:Q1"), "DRAW did not open")
	assert_eq(fake.mode, LeagueScreen.MODE_EUROPE_DRAW, "DRAW did not open the ceremony")
	assert_eq(str(fake.europe_draw["competition"]), "UEL", "the draw kept the wrong competition")
	assert_eq(int(fake.europe_draw["revealed"]), 0, "an unseen draw starts revealed")
	assert_false(bool(fake.europe_draw["done"]), "an unseen draw starts settled")
	assert_true(LeagueEuropeActions.tick(fake, LeagueEuropeActions.STEP), "the first tick did nothing")
	assert_eq(int(fake.europe_draw["revealed"]), 1, "the ceremony did not reveal a pair")
	assert_true(LeagueEuropeActions.press(fake, "europe:draw:skip"), "SKIP was ignored")
	assert_true(bool(fake.europe_draw["done"]), "SKIP did not settle the draw")
	assert_true(LeagueEurope.seen(fake.season.save, "UEL", "Q1"), "SKIP did not mark the draw")
	assert_false(LeagueEuropeActions.tick(fake, 1.0), "a settled draw still ticks")
	assert_true(LeagueEuropeActions.press(fake, "europe:draw:open"), "OPEN was ignored")
	assert_eq(fake.mode, LeagueScreen.MODE_EUROPE_STAGE, "OPEN did not return to the stage")
	_run_to(fake.season, "UCL", "POLP")
	var after_po := LeagueEurope.stage_of("UCL")
	LeagueEuropeActions.open_stage(fake, "UCL")
	var want_po := "bracket" if LeagueEurope.KO_ROUNDS.has(after_po) \
		else ("table" if after_po == LeagueUefa.LEAGUE_STAGE else "qualifying")
	assert_eq(str(fake.europe["tab"]), want_po, "open_stage misread the post-play-off stage")
	_run_to(fake.season, "UCL", "KOPO")
	LeagueEuropeActions.open_stage(fake, "UCL")
	assert_eq(str(fake.europe["tab"]), "bracket", "a knockout stage did not open as a bracket")
	assert_false(LeagueEuropeActions.press(fake, "other"), "an unknown id was claimed")
	fake.mode = LeagueScreen.MODE_HUB
	LeaguePanelDoors.nav(fake, "europe")
	assert_eq(fake.mode, LeagueScreen.MODE_EUROPE, "the drawer EUROPE pose did not open the hub")
	LeagueEuropeActions.open_draw(fake, "UEL", "Q1")
	assert_true(bool(fake.europe_draw["done"]), "a seen draw did not open settled")
	assert_gt(int(fake.europe_draw["revealed"]), 0, "a seen draw opened with no pairs")
	fake.season.close()
	var bare := Fake.new()
	LeagueEuropeActions.open(bare)
	assert_eq(bare.mode, LeagueScreen.MODE_HUB, "an empty save still opened Europe")


class CalFake extends RefCounted:
	var season: LeagueSeason = null
	var calendar_filter := ""
	var days_cache := {}
	var month := "2026-07"
	var day := ""
	var day_fixtures: Array = []
	var touch := false

	func refresh() -> void:
		pass

	func push_page() -> void:
		pass


func test_calendar_filter_keeps_only_one_competition() -> void:
	var fake := CalFake.new()
	fake.season = LeagueSeason.create("Europe Cal", "generated", "fixture_days", SEED,
		["PL"], false, [], true)
	LeagueCalendar.open(fake)
	assert_gt(fake.days_cache.size(), 0, "the calendar has no UEFA nights")
	var before := fake.days_cache.size()
	LeagueCalendar.set_filter(fake, "UCL")
	assert_eq(str(fake.calendar_filter), "UCL", "the UCL chip did not stick")
	assert_lte(fake.days_cache.size(), before, "filtering UCL grew the calendar")
	assert_gt(fake.days_cache.size(), 0, "UCL nights vanished from the calendar")
	LeagueCalendar.set_filter(fake, "UCL")
	assert_eq(str(fake.calendar_filter), "UCL", "toggling the same chip cleared the filter")
	LeagueCalendar.set_filter(fake, "")
	assert_eq(str(fake.calendar_filter), "", "ALL did not clear the filter")
	fake.season.close()


class DoorFake extends RefCounted:
	var wizard := {"uefa": true, "competitions": ["PL"], "name": "Door",
		"calendar_mode": "generated", "advance_mode": "fixture_days"}
	var mode := LeagueScreen.MODE_WIZARD
	var season = null
	var europe := {}
	var europe_draw := {}
	var panel := PanelStub.new()
	var focus := _Focus.new()
	var delete := _Delete.new()
	var calendar_filter := ""
	var days_cache := {}
	var month := "2026-07"
	var day := ""
	var day_fixtures: Array = []
	var touch := false

	class _Focus extends RefCounted:
		func blur() -> void:
			pass

	class _Delete extends RefCounted:
		pass

	func refresh() -> void:
		pass

	func push_page() -> void:
		pass


func test_wizard_uefa_toggle_and_europe_press_route() -> void:
	var fake := DoorFake.new()
	LeagueDoors.press(fake, "wuefa")
	assert_eq(bool(fake.wizard["uefa"]), false, "wuefa did not flip the UEFA switch")
	LeagueDoors.press(fake, "wuefa")
	assert_eq(bool(fake.wizard["uefa"]), true, "wuefa did not flip UEFA back on")
	fake.season = LeagueSeason.create("Europe Door", "generated", "fixture_days", SEED,
		["PL"], false, [], true)
	fake.mode = LeagueScreen.MODE_HUB
	LeagueDoors.press(fake, "europe:comp:UCL")
	assert_eq(fake.mode, LeagueScreen.MODE_EUROPE_STAGE, "doors did not route a Europe card")
	LeagueDoors.press(fake, "cal:UEL")
	assert_eq(str(fake.calendar_filter), "UEL", "cal: did not set the calendar filter")
	fake.season.close()

