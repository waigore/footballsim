extends SceneTree

const SEED := 4370437

var scene = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	var season := LeagueSeason.create("Europe Evidence", "generated", "fixture_days", SEED,
		["PL"], false, [], true)
	if season == null:
		print("EXIT no season")
		quit()
		return
	_run_to(season, "UCL", "POLP")
	var league: LeagueHost = scene.menus.league
	league.show_season(season)
	var screen: LeagueScreen = league.screen
	LeagueEuropeActions.open(screen)
	await _shot("issue437_europe_hub")
	LeagueEuropeActions.open_draw(screen, "UCL", "LP")
	screen.europe_draw["revealed"] = 12
	screen.refresh()
	await _shot("issue437_draw")
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE_STAGE)
	screen.europe = {"comp": "UCL", "tab": "table", "round": ""}
	screen.refresh()
	await _shot("issue437_league_phase")
	screen.europe["tab"] = "qualifying"
	screen.refresh()
	await _shot("issue437_qualifying")
	_settle(season, "UCL", "LP")
	LeagueEuropeDraws.mark_seen(season.save, "UCL", "KOPO")
	screen.europe["tab"] = "bracket"
	screen.europe["round"] = "KOPO"
	screen.refresh()
	await _shot("issue437_bracket")
	screen.mode = LeagueScreen.MODE_CALENDAR
	screen.calendar_filter = ""
	screen.month = "2026-07"
	LeagueCalendar.open(screen)
	await _shot("issue437_calendar")
	_phone()
	await _frames(4)
	screen.touch = true
	screen.mode = LeagueScreen.MODE_EUROPE
	screen.refresh()
	await _shot("issue437_hub_phone")
	screen.mode = LeagueScreen.MODE_EUROPE_STAGE
	screen.europe = {"comp": "UCL", "tab": "table", "round": ""}
	screen.refresh()
	await _shot("issue437_table_phone")
	scene.get_window().size = Vector2i(1600, 900)
	await _frames(6)
	screen.touch = false
	_finish(season)
	league.show_season(season, true)
	await _shot("issue437_podium")
	print("DONE")
	quit()


func _settle(season: LeagueSeason, competition_id: String, round_id: String) -> void:
	PLDatabase.execute(
		"UPDATE league_fixture SET status = 'played', home_goals = 2, away_goals = 1 "
		+ "WHERE competition_id = ? AND stage = ?;", [competition_id, round_id])
	if round_id == LeagueUefa.LEAGUE_STAGE:
		season.record.standings.recompute()
	else:
		PLDatabase.execute(
			"UPDATE cup_tie SET home_goals = 4, away_goals = 2, winner_club_id = home_club_id "
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


func _finish(season: LeagueSeason) -> void:
	for cid in LeagueUefa.IDS:
		_run_to(season, str(cid), "F")
	PLDatabase.execute(
		"UPDATE league_fixture SET status = 'played', home_goals = 2, away_goals = 1 "
		+ "WHERE competition_id = 'PL';")
	season.record.standings.recompute()
	season.save.set_status("complete")


func _phone() -> void:
	scene.touch = true
	scene.get_window().size = Vector2i(913, 411)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(shot_name: String) -> void:
	await _frames(6)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % shot_name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % shot_name)
		return
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % shot_name))
	print("SHOT %s %dx%d" % [shot_name, img.get_width(), img.get_height()])
