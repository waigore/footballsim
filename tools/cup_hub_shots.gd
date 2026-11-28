extends SceneTree


const SEED := 4591
const SHOTS := "res://shots"

var scene = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Cup Evidence", "generated", "fixture_days", SEED, ["PL"],
		true, ["England"])
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	var screen: LeagueScreen = league.screen
	await _shot("cup_wizard", _wizard_pose.bind(league))
	league.show_season(season)
	screen.click("panel")
	screen.panel.settle()
	await _shot("cup_panel", _plain.bind(screen))
	screen.click("nav:cups")
	await _shot("cup_hub", _plain.bind(screen))
	screen.click("cup:FAC")
	await _shot("cup_rounds", _plain.bind(screen))
	screen.click("cupbracket:FAC:R1")
	await _shot("cup_bracket", _plain.bind(screen))
	screen.click("cupround:FAC:QF")
	await _shot("cup_bracket_qf", _plain.bind(screen))
	screen.click("back")
	screen.click("cupdraw:FAC:R1")
	await _frames(30)
	await _shot("cup_draw", _plain.bind(screen))
	screen.click("skiptodraw")
	await _shot("cup_draw_settled", _plain.bind(screen))
	screen.click("back")
	await _shot("cup_revealed", _plain.bind(screen))
	_play_round(screen, "FAC", "R1")
	screen.open_season(season)
	screen.click("panel")
	screen.panel.settle()
	screen.click("nav:cups")
	await _shot("cup_hub_settled", _plain.bind(screen))
	screen.click("calendar")
	await _shot("cup_calendar", _calendar.bind(screen))
	screen.click("back")
	var guard := 0
	while season.matches_remaining() > 0 and guard < 200:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("cup_podium", _plain.bind(screen))
	_encyclopedia()
	await _shot("cup_encyclopedia", _enc.bind())
	print("EXIT done")
	quit()


func _play_round(screen: LeagueScreen, competition_id: String, round_id: String) -> void:
	for row in PLDatabase.rows(
			"SELECT * FROM league_fixture WHERE competition_id = ? AND stage = ?;",
			[competition_id, round_id]):
		LeagueSeasonSim.fixture(LeagueSeason.active, row)
	LeagueSeason.active.record.standings.recompute()
	screen.refresh()


func _encyclopedia() -> void:
	scene.wiki_host.open_page_over_league(WikiModel.CUP, "FAC")


func _wizard_pose(league: LeagueHost) -> void:
	scene.menus.open_menu()
	league.open_wizard()


func _calendar(screen: LeagueScreen) -> void:
	var day := ""
	for date in (screen.days_cache as Dictionary).keys():
		var info: Dictionary = screen.days_cache[date]
		var by: Dictionary = info.get("by_league", {})
		if by.has("CS") or by.has("EFLC") or by.has("FAC"):
			day = str(date)
			break
	if day != "":
		LeagueCalendar.pick(screen, day)
	screen.refresh()


func _plain(_screen: LeagueScreen) -> void:
	pass


func _enc() -> void:
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
