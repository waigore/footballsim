extends SceneTree

const SEED := 4810042

var scene = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	var season := LeagueSeason.create("UEFA Season Two Evidence", "generated", "fixture_days", SEED,
		["PL"], true, [], true)
	if season == null:
		print("EXIT no season")
		quit()
		return
	_finish(season)
	var places := _places(season)
	_pin_cup_final("FAC", str(places[11]), str(places[13]))
	_pin_cup_final("EFLC", str(places[1]), str(places[14]))
	var result := SeasonRollover.apply(season)
	print("ROLLOVER %s carried %s" % [str(result.get("ok", false)),
		",".join(PackedStringArray(_strings(result.get("carried", []))))])
	if not bool(result.get("ok", false)):
		quit()
		return
	var league: LeagueHost = scene.menus.league
	league.show_season(season)
	var screen: LeagueScreen = league.screen
	LeagueEuropeActions.open(screen)
	await _shot("issue481_europe_hub")
	screen.europe = {"comp": "UCL", "tab": "entrants", "round": ""}
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE_STAGE)
	screen.refresh()
	await _shot("issue481_entrants")
	_phone()
	await _frames(6)
	league.show_season(season)
	screen = league.screen
	screen.touch = true
	LeagueEuropeActions.open(screen)
	await _shot("issue481_hub_phone")
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE_STAGE)
	screen.europe = {"comp": "UEL", "tab": "entrants", "round": ""}
	screen.refresh()
	await _shot("issue481_entrants_phone")
	scene.get_window().size = Vector2i(1600, 900)
	await _frames(6)
	scene.touch = false
	print("DONE")
	quit()


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(str(value))
	return out


func _places(season: LeagueSeason) -> Array:
	var out: Array = []
	for row in season.record.standings.table("PL"):
		out.append(str(row["club_id"]))
	return out


func _pin_cup_final(competition_id: String, winner: String, loser: String) -> void:
	PLDatabase.execute(
		"INSERT OR REPLACE INTO cup_tie (competition_id, round_id, tie_index, home_club_id, "
		+ "away_club_id, winner_club_id, home_goals, away_goals) VALUES (?, 'F', 0, ?, ?, ?, 2, 0);",
		[competition_id, winner, loser, winner])


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
		"UPDATE league_fixture SET status = 'played', home_goals = 2, away_goals = 1;")
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
