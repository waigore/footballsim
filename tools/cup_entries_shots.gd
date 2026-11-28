extends SceneTree


const SEED := 5063
const SHOTS := "res://shots"

var scene = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Cup Entries Evidence", "generated", "fixture_days", SEED,
		["PL"], true, ["England"])
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	_finish(season)
	var champion := _placed(1)
	var runner := _placed(2)
	var winner := _placed(6)
	PLDatabase.execute(
		"INSERT OR REPLACE INTO cup_tie (competition_id, round_id, tie_index, home_club_id, "
		+ "away_club_id, winner_club_id, home_goals, away_goals) "
		+ "VALUES ('FAC', 'F', 0, ?, ?, ?, 3, 1);", [winner, _placed(7), winner])
	print("ROLLOVER champion ", champion, " runner ", runner, " cup winner ", winner)
	var rolled := SeasonRollover.apply(season)
	print("ROLLOVER ok ", rolled.get("ok", false))
	print("SHIELD field ", str(LeagueCup.entrants("CS", "F")))
	print("SHIELD caption ", LeagueCupEntries.note(season.save, "CS"))
	league.show_season(season)
	var screen: LeagueScreen = league.screen
	screen.click("panel")
	await _frames(5)
	screen.panel.settle()
	screen.click("nav:cups")
	await _shot("cup_entries_hub", _plain.bind(screen))
	screen.click("cup:CS")
	await _shot("cup_entries_shield", _plain.bind(screen))
	screen.click("back")
	screen.click("cup:FAC")
	await _shot("cup_entries_fa_cup", _plain.bind(screen))
	print("EXIT shots done")
	quit()


func _finish(season: LeagueSeason) -> void:
	for row in PLDatabase.rows("SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		PLDatabase.execute(
			"UPDATE league_fixture SET status = 'played', home_goals = ?, away_goals = ? "
			+ "WHERE id = ?;", [3 if home < away else 1, 1 if home < away else 3, str(row["id"])])
	season.record.standings.recompute()
	season.save.set_status("complete")
	season.save.reload()
	SeasonSettle.apply(season)


func _placed(place: int) -> String:
	var season: LeagueSeason = LeagueSeason.active
	for row in season.record.standings.table("PL"):
		if int(row.get("position", 0)) == place:
			return str(row.get("club_id", ""))
	return ""


func _plain(_screen: LeagueScreen) -> void:
	pass


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String, pose: Callable) -> void:
	pose.call()
	await _frames(5)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [SHOTS, name]))
	print("SHOT ", name, " ", img.get_size())
