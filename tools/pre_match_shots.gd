extends SceneTree

## Evidence capture for the pre-match briefing and season availability (#155–#157).
##
## Boots the real game, builds a season, plays two rounds, rules a few players out
## on both sides, and writes the poses the feature shows: the league briefing on
## a desktop window, the same briefing at handheld scale, and a single-match
## briefing. Run it on a display — a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/pre_match_shots.gd

const SEED := 2031

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Briefing Season", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	# Two played rounds, so the briefing has form and a table place to read.
	season.advance()
	season.advance()
	var fixture: Dictionary = {}
	for fx in season.record.fixtures.pending_upto("2027-06-01"):
		fixture = fx
		break
	if fixture.is_empty():
		print("EXIT no pending fixture")
		quit()
		return
	var home := str(fixture["home_club_id"])
	var away := str(fixture["away_club_id"])
	var date := str(fixture["kickoff"])
	_rule_out(home, date, 0)
	_rule_out(away, date, 1)
	season.save.set_date(date)
	season.save.set_matchday(int(fixture["matchday"]))
	league.show_season(season)
	await _frames(2)
	# A watched fixture goes Continue → briefing, exactly as a player sees it.
	season.set_watch(str(fixture["id"]), true)
	league.screen.refresh()
	league.screen.click("fixture:" + str(fixture["id"]))
	await _frames(4)
	print("BRIEFING open=", scene.prematch.is_open(), " fixture=", fixture["id"],
		" date=", FixtureCalendar.day_label(date), " md=", int(fixture["matchday"]))
	await _shot("prematch_desktop")
	# The same briefing at handheld scale: the phone layout, touch copy.
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
	scene._sync_overlay_scale()
	await _shot("prematch_phone")
	scene.prematch.close()
	# A single-match kick-off: the friendly caption, KICK OFF and no absences.
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	scene.prematch.ask(PreMatchModel.build("MUN", "MCI", {}, null), Callable(), Callable())
	await _shot("prematch_friendly")
	print("EXIT season=", season.save.slug, " date=", date)
	quit()

## One side of the briefing, ruled out three ways: a knock, a long term and a ban.
func _rule_out(club: String, date: String, side: int) -> void:
	var xi := StrongestXI.pick(TeamData.get_team(club))
	if xi.size() < 3:
		return
	if side == 0:
		SeasonAvailability.injure(str(xi[0]["id"]), club, date, "muscle", 21, 1.0)
		SeasonAvailability.injure(str(xi[1]["id"]), club, date, "ligament", 60, 1.0)
		SeasonAvailability.suspend(str(xi[2]["id"]), club, 2, "red", date)
	else:
		SeasonAvailability.injure(str(xi[0]["id"]), club, date, "knock", 6, 1.0)
		SeasonAvailability.suspend(str(xi[1]["id"]), club, 1, "second_yellow", date)

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(6)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("SHOT %s %dx%d" % [name, img.get_width(), img.get_height()])
