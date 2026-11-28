extends SceneTree

## Evidence capture for #209 (one match names one competition) and #207 (a table
## place is a real ordinal).
##
## Boots the real game scene and shoots:
##
##   * the fixture picker's briefing, which is a **friendly** end to end,
##   * a league Watch's briefing, which names the competition and the round,
##   * the broadcast's fixture panel for the same friendly, then for the same
##     league fixture — one binding, two answers, never both at once,
##   * the club strip's table place, printed as an ordinal.
##
## Writes a PNG per pose into `res://shots/` and prints the copy it shot.
## Run it on a display; a headless run has no frame to read back.
##
##   godot --path . --script res://tools/competition_shots.gd

const SEED := 2031

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Billing Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	# Two played rounds so the strip has a real table place to print.
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
	# A league watch: the briefing names the competition and the round.
	scene.prematch.ask(PreMatchModel.build(home, away, fixture, season), Callable(), Callable())
	await _shot("issue209_briefing_league")
	_print_caption(scene.prematch.screen.view, "league briefing")
	season.save.set_date(str(fixture["kickoff"]))
	season.save.set_matchday(int(fixture["matchday"]))
	league.show_season(season)
	season.set_watch(str(fixture["id"]), true)
	MatchBilling.bind_scene(scene, home, fixture)
	scene.prematch.close()
	await _frames(2)

	# The broadcast's fixture panel for the league fixture. The season sheet is
	# stood down first: it is a modal over the broadcast.
	league.close()
	await _frames(2)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene.paused = true
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("issue209_card_league")
	print("CARD    league=", HudTopBand.billing_name(scene, scene.engine))

	# The picker's match: a friendly on every surface.
	scene._on_fixture_confirmed("ENG-MUN1", "ENG-MCI1")
	scene.prematch.screen.hold()
	await _shot("issue209_briefing_friendly")
	_print_caption(scene.prematch.screen.view, "friendly briefing")
	scene.prematch.close()
	await _frames(2)
	scene.hud_layer.visible = true
	scene.paused = true
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("issue209_card_friendly")
	print("CARD    friendly=", HudTopBand.billing_name(scene, scene.engine))

	# The place, as the strip prints it.
	print("STRIP   ", PreMatchScreen.strip_line(TeamData.get_team(home), 2, "W D L W W"))
	print("ORDINAL 1/2/3/11/21 -> ", PreMatchCopy.place(1), " ", PreMatchCopy.place(2), " ",
		PreMatchCopy.place(3), " ", PreMatchCopy.place(11), " ", PreMatchCopy.place(21))
	print("EXIT season=", season.save.slug)
	quit()

func _print_caption(view: Dictionary, label: String) -> void:
	print("BRIEF   %s caption=%s competition=%s matchday=%d friendly=%s" % [
		label, str(view.get("caption", "")), str(view.get("competition", "")),
		int(view.get("matchday", 0)), str(view.get("friendly", false))])
	print("BRIEF   %s news=%s" % [label, str((view.get("news", {}) as Dictionary).get("line", ""))])

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
