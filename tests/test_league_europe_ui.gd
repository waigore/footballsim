extends GdToolsTest


const SEED := 515151


class Fake extends RefCounted:
	var season: LeagueSeason = null
	var touch := false
	var europe := {"comp": "UCL", "tab": "", "round": ""}
	var europe_draw := {"competition": "UCL", "round": "Q1", "revealed": 0, "done": false,
		"t": 0.0}


func _screen(touch: bool = false) -> Fake:
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	var fake := Fake.new()
	fake.season = LeagueSeason.create("Europe UI", "generated", "fixture_days", SEED,
		["PL"], false, true)
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
	var row := LeaguePanel.row_h(Vector2(913, 411))
	assert_lte(84.0 + float(LeaguePanel.ITEMS.size()) * (row + LeaguePanel.ROW_GAP), 411.0,
		"the drawer's items do not fit a phone")
	var panel := LeaguePanel.new()
	panel.europe_on = false
	assert_eq(panel.items().size(), LeaguePanel.ITEMS.size() - 1,
		"the drawer still offers EUROPE on a domestic-only save")
	panel.europe_on = true
	assert_eq(panel.items().size(), LeaguePanel.ITEMS.size(),
		"the drawer lost a door on a European save")


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
