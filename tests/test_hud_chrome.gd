extends GdToolsTest


class FakeGame:
	var engine = null
	var mode := "highlights"
	var fast_mode := false
	var paused := false
	var match_time := 12.0
	var in_highlight := false
	var replay_banner := 0.0
	var focus_id := -1
	var hover_id := -1
	var names_visible := true
	var camera_follow := false
	var speed := 1.0
	var token_scale := 1.0

	var result_hold := false

	var billing := MatchBilling.new()

func _hud(eng) -> Control:
	var game := FakeGame.new()
	game.engine = eng
	var hud := Control.new()
	hud.set_script(load("res://scripts/ui/hud.gd"))
	hud.size = Vector2(1280.0, 800.0)
	hud.game = game
	hud.engine = eng
	add_child(hud)
	return hud

func test_overlay_draws_and_ticker_sits_above_the_controls() -> void:
	var eng := MatchEngine.new(21)
	var hud := _hud(eng)
	assert_not_null(hud.ticker, "the ticker was not created")
	hud.ticker.tick(0.2, eng, hud.game)
	assert_ne(hud.ticker.text, "", "the ticker stayed empty with a kickoff in the log")
	hud.queue_redraw()
	await get_tree().process_frame
	var vp: Vector2 = get_viewport().get_visible_rect().size
	assert_false(HudLayout.commentary_rect(vp).intersects(HudLayout.controls_rect(vp)),
		"the commentary panel covers the control bar at %s" % vp)
	hud.queue_free()

func test_ticker_describes_a_fresh_match() -> void:
	var eng := MatchEngine.new(22)
	eng.events.clear()
	var hud := _hud(eng)
	hud.ticker.tick(0.2, eng, hud.game)
	assert_eq(hud.ticker.text, "", "a fresh match should start with no line")
	hud.queue_redraw()
	await get_tree().process_frame
	hud.queue_free()

func test_ticker_follows_events_then_live_play() -> void:
	var eng := MatchEngine.new(24)
	var hud := _hud(eng)
	eng.events = [{"id": 900, "type": "goal", "text": "GOAL! It's in.", "minute": 34}]
	hud.ticker.tick(0.1, eng, hud.game)
	assert_eq(hud.ticker.label, "GOAL", "a goal event did not take the ticker")
	assert_gt(hud.ticker.hold, hud.ticker._freshness("SHOT"), "a goal should hold longer than a shot")
	hud.ticker.hold = 0.0
	hud.ticker.tick(0.0, eng, hud.game)
	assert_eq(hud.ticker.label, "LIVE", "the ticker never fell back to live play")
	hud.game.in_highlight = true
	hud.queue_redraw()
	await get_tree().process_frame
	hud.queue_free()

func test_ticker_keeps_the_whistle_line_after_full_time() -> void:


	var eng := MatchEngine.new(277)
	eng.events = [{"id": 901, "type": "full_time", "text": "Full time: MUN 2-1 MCI.", "minute": 90}]
	eng.phase = "full_time"
	var hud := _hud(eng)
	hud.ticker.tick(0.1, eng, hud.game)
	var line: String = hud.ticker.text
	assert_eq(hud.ticker.label, "FULL TIME", "the whistle line did not take the ticker")
	hud.ticker.hold = 0.0
	hud.ticker.tick(0.0, eng, hud.game)
	assert_eq(hud.ticker.label, "FULL TIME", "the ticker fell back to LIVE on a finished match")
	assert_eq(hud.ticker.text, line, "the ticker replaced the whistle line on a finished match")
	hud.queue_free()

func test_manager_card_shows_without_blocking_the_match() -> void:
	var eng := MatchEngine.new(26)
	var hud := _hud(eng)
	eng.manager.demo()
	hud.manager_card.tick(0.1, eng, hud.game)
	assert_true(hud.manager_card.visible(), "the manager card did not show for a manager act")
	hud.queue_redraw()
	await get_tree().process_frame
	var vp: Vector2 = get_viewport().get_visible_rect().size
	assert_false(HudLayout.controls_rect(vp).intersects(hud.manager_card.box), "the manager card covers the control bar")
	assert_false(Rect2(0, 0, 300, 120).intersects(hud.manager_card.box), "the manager card covers the fixture panel")
	var mid: Vector2 = hud.manager_card.box.position + hud.manager_card.box.size * 0.5
	assert_eq(hud.button_at(mid), "manager_card", "the card is not tappable")
	hud.manager_card.dismiss()
	assert_false(hud.manager_card.visible(), "the manager card did not dismiss")
	hud.queue_free()

func test_manager_card_holds_when_paused_and_expires() -> void:
	var eng := MatchEngine.new(27)
	var hud := _hud(eng)
	eng.manager.demo()
	hud.manager_card.tick(0.1, eng, hud.game)
	assert_true(hud.manager_card.visible(), "the manager card did not show")
	hud.game.paused = true
	hud.manager_card.tick(30.0, eng, hud.game)
	assert_true(hud.manager_card.visible(), "the card vanished while paused")
	hud.game.paused = false
	hud.manager_card.tick(30.0, eng, hud.game)
	assert_false(hud.manager_card.visible(), "the card never faded")
	hud.queue_free()

func test_manager_card_draws_a_tactics_change() -> void:
	var eng := MatchEngine.new(28)
	var hud := _hud(eng)
	MatchManagerTactics.apply(eng.manager, 0, {"mentality": "attacking", "line_delta": 0.06}, "test")
	hud.manager_card.tick(0.1, eng, hud.game)
	assert_true(hud.manager_card.visible(), "the tactics card did not show")
	assert_eq(str(hud.manager_card.card.get("type", "")), "tactics", "tactics card not built")
	hud.queue_redraw()
	await get_tree().process_frame
	assert_gt(hud.manager_card.box.size.x, 0.0, "the tactics card never drew")
	hud.queue_free()

func test_referee_is_drawn_on_the_pitch() -> void:
	var eng := MatchEngine.new(25)
	for i in range(30):
		eng.tick()
	eng.referee.whistle = 0.5
	var layer := Node2D.new()
	layer.set_script(load("res://scripts/view/actor_layer.gd"))
	layer.engine = eng
	layer.focus_id = eng.players[0].id
	add_child(layer)
	layer.queue_redraw()
	await get_tree().process_frame
	assert_between(eng.referee.pos.x, 0.0, eng.L, "the official is off the pitch")
	layer.queue_free()

func test_phone_bar_carries_one_tappable_teams_door() -> void:
	var eng := MatchEngine.new(31)
	var hud := _hud(eng)
	hud.touch = true
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 411.0
	hud.queue_redraw()
	await get_tree().process_frame
	var vp: Vector2 = hud.design_vp()
	assert_true(HudLayout.is_compact(vp), "phone design space did not read as compact: %s" % vp)
	var ids := []
	for b in hud.buttons:
		ids.append(str(b["id"]))
	assert_eq(ids.count("teams"), 1, "expected exactly one teams door, got %s" % str(ids))


	assert_eq(ids.size(), HudLayout.CONTROL_COUNT_TOUCH + 2 + 1, "the phone should hold the bar, two club doors and the HUD pill: %s" % str(ids))
	for b in hud.buttons:
		var r: Rect2 = b["rect"]
		var mid: Vector2 = r.position + r.size * 0.5
		assert_eq(hud.button_at(mid), str(b["id"]), "%s is not tappable at its centre" % str(b["id"]))
		assert_lte(r.end.x, vp.x, "%s runs off the right edge" % str(b["id"]))
		if str(b["id"]) == "teams":
			assert_eq(str(b["label"]), "TEAMS", "the phone's teams door lost its caption")
	hud.queue_free()

func test_desktop_bar_keeps_the_fixture_panel_door() -> void:
	var eng := MatchEngine.new(32)
	var hud := _hud(eng)
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 900.0
	hud.queue_redraw()
	await get_tree().process_frame
	assert_false(HudLayout.is_compact(hud.design_vp()), "desktop design space read as compact")
	var ids := []
	for b in hud.buttons:
		ids.append(str(b["id"]))
	assert_eq(ids.count("teams"), 1, "expected the fixture panel's teams door only, got %s" % str(ids))
	assert_eq(ids.size(), HudLayout.CONTROL_COUNT + 1 + 2 + 1, "desktop should hold the bar, the fixture door, two club doors and the HUD pill")
	hud.queue_free()


class LabelSurface extends HudChrome:
	var texts: Array = []

	func text(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color, font: Font, outline: int = 0, outline_col: Color = Color(0, 0, 0, 0.5)) -> void:
		texts.append({"s": s, "pos": pos, "size": size, "color": color})


func test_the_fixture_card_labels_its_change_teams_door() -> void:
	var eng := MatchEngine.new(357)
	var hud := _hud(eng)
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 900.0
	var surface := LabelSurface.new()
	var shipped: HudChrome = hud.chrome
	hud.chrome = surface
	hud.queue_redraw()
	await get_tree().process_frame
	hud.chrome = shipped
	var door := Rect2()
	var label := ""
	var hint := ""
	for b in surface.buttons:
		if str(b["id"]) != "teams":
			continue
		door = b["rect"]
		label = str(b["label"])
		hint = str(b["hint"])
	assert_eq(label, "CHANGE TEAMS", "the fixture door has no stored caption")
	assert_eq(hint, "T", "the fixture door lost its T shortcut")
	assert_eq(surface.button_at(door.get_center()), "teams", "the fixture door does not answer a press")
	var painted := 0
	var keyed := 0
	for t in surface.texts:
		var pos: Vector2 = t["pos"]
		if not door.has_point(pos):
			continue
		if str(t["s"]) == label:
			painted += 1
		elif str(t["s"]) == hint:
			keyed += 1
	assert_gte(painted, 1, "the fixture door drew no CHANGE TEAMS caption")
	assert_gte(keyed, 1, "the fixture door drew no T hint")
	var key_x: float = door.end.x - 10.0 - hud.f_med.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var caption_w: float = hud.f_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	assert_lte(door.position.x + 10.0 + caption_w, key_x, "the fixture door's caption runs under its T hint")
	surface.texts.clear()
	hud.mouse = door.get_center()
	hud.chrome = surface
	hud.queue_redraw()
	await get_tree().process_frame
	hud.chrome = shipped
	var lit := 0
	for t in surface.texts:
		if str(t["s"]) == label and door.has_point(t["pos"]) and (t["color"] as Color) == UiChrome.C_TEXT:
			lit += 1
	assert_gte(lit, 1, "a hovered fixture door kept its resting ink")
	hud.mouse = Vector2.ZERO
	hud.queue_free()

func test_phone_player_card_stays_clear_of_the_other_panels() -> void:
	var card := HudPlayerCard.new(Color.BLACK, Color.GOLD, Color.WHITE, Color.GRAY)
	for vp in [Vector2(913, 411), Vector2(800, 360), Vector2(1000, 450)]:
		var box: Rect2 = card.rect_for(vp)
		var ticker: Rect2 = HudLayout.commentary_rect(vp)
		var stats: Rect2 = HudLayout.stats_rect(vp)
		assert_false(box.intersects(ticker), "the card covers the ticker at %s" % vp)
		assert_false(box.intersects(stats), "the card covers the stats card at %s" % vp)
		assert_gte(box.position.x, 0.0, "the card starts off-screen at %s" % vp)
		assert_lte(box.end.x, vp.x, "the card runs off the right edge at %s" % vp)
		assert_gte(box.position.y, stats.end.y, "the card rises into the top bar at %s" % vp)
		assert_gte(box.size.y, 96.0, "the card is too short to hold its rows at %s" % vp)

func test_desktop_player_card_hangs_under_the_stats_card() -> void:


	var card := HudPlayerCard.new(Color.BLACK, Color.GOLD, Color.WHITE, Color.GRAY)
	for vp in [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080)]:
		var box: Rect2 = card.rect_for(vp)
		var stats: Rect2 = HudLayout.stats_rect(vp)
		assert_false(box.intersects(stats), "the dossier covers the stats card at %s" % vp)
		assert_gte(box.position.y, stats.end.y, "the dossier starts inside the stats card at %s" % vp)
		assert_false(box.intersects(HudLayout.commentary_rect(vp)), "the dossier covers the ticker at %s" % vp)
		assert_lte(box.end.x, vp.x, "the dossier runs off the right edge at %s" % vp)

func test_player_card_draws_in_both_layouts() -> void:
	var eng := MatchEngine.new(34)
	var hud := _hud(eng)
	hud.game.focus_id = eng.players[2].id
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 900.0
	hud.queue_redraw()
	await get_tree().process_frame
	assert_gt(hud.card.rect_for(hud.design_vp()).size.y, 300.0, "desktop card is not the column layout")
	hud.touch = true
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 411.0
	hud.queue_redraw()
	await get_tree().process_frame
	assert_lte(hud.card.rect_for(hud.design_vp()).size.y, 132.0, "phone card is not the strip layout")
	assert_eq(hud.button_at(hud.card.rect_for(hud.design_vp()).position + Vector2(4, 4)), "", "the card is not a door")
	hud.queue_free()

func test_goal_and_half_time_banners_draw_on_a_phone() -> void:
	var eng := MatchEngine.new(35)
	var hud := _hud(eng)
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 411.0
	hud.touch = true
	eng.score = [2, 1]
	eng.phase = "goal"
	eng.last_goal = {"team": 0, "conceded_by": 1, "scorer": "B. Šeško", "minute": 63, "own_goal": false}
	hud.queue_redraw()
	await get_tree().process_frame
	assert_eq(eng.phase, "goal", "the goal banner case did not stage")
	eng.phase = "half_time"
	hud.queue_redraw()
	await get_tree().process_frame
	eng.phase = "full_time"
	hud.queue_redraw()
	await get_tree().process_frame

	hud.game.result_hold = true
	hud.queue_redraw()
	await get_tree().process_frame
	hud.game.result_hold = false
	assert_true(HudLayout.is_compact(hud.design_vp()), "banners were drawn in desktop metrics")
	hud.queue_free()

func test_extra_time_and_shootout_cards_draw_on_both_metrics() -> void:
	var eng := MatchEngine.new(38)
	eng.half = 3
	eng.clock = 5600.0
	eng.phase = "et_break"
	var hud := _hud(eng)
	hud.queue_redraw()
	await get_tree().process_frame
	hud.queue_free()
	eng.phase = "shootout"
	eng.shootout_score = [3, 2]
	eng.shootout = [{"team": 0, "player": "E. Haaland", "scored": true, "pens": [1, 0]}]
	var phone := _hud(eng)
	phone.touch = true
	phone.ui_scale = phone.get_viewport().get_visible_rect().size.y / 411.0
	phone.queue_redraw()
	await get_tree().process_frame
	assert_true(HudLayout.is_compact(phone.design_vp()), "the shootout card did not use phone metrics")
	phone.queue_free()
	eng.phase = "full_time"
	eng.shootout_score = [4, 3]
	var desk := _hud(eng)
	desk.queue_redraw()
	await get_tree().process_frame
	assert_eq(HudBannersBand.pens_line(eng), "PENS 4 – 3", "the card did not name the shootout")
	desk.queue_free()

func test_the_whistle_card_lists_its_goals_on_both_metrics() -> void:


	var short: Array = [
		{"team": 0, "minute": 12, "scorer": "E. Haaland", "own_goal": false},
		{"team": 1, "minute": 38, "scorer": "B. Šeško", "own_goal": false},
		{"team": 0, "minute": 71, "scorer": "P. Foden", "own_goal": true},
	]
	var long: Array = []
	for i in range(12):
		long.append({"team": 0, "minute": 5 + i * 6, "scorer": "E. Haaland", "own_goal": i == 11})
	for sheet in [short, long]:
		for phone in [false, true]:
			var eng := MatchEngine.new(36)
			eng.goal_sheet = sheet.duplicate(true)
			var home := 0
			for g in eng.goal_sheet:
				if int(g["team"]) == 0:
					home += 1
			eng.score = [home, eng.goal_sheet.size() - home]
			eng.phase = "full_time"
			var hud := _hud(eng)
			hud.touch = phone
			hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / (411.0 if phone else 900.0)
			hud.queue_redraw()
			await get_tree().process_frame
			var vp: Vector2 = hud.design_vp()
			var m: Dictionary = HudLayout.break_metrics(vp, eng.score[0], eng.score[1])
			assert_gte(int(m["rows"]), 1, "the card had no room for a goal row (phone=%s, %d goals)" % [phone, sheet.size()])
			assert_lte(float(m["rect"].end.y), HudLayout.commentary_rect(vp).position.y, "the card covers the ticker (phone=%s, %d goals)" % [phone, sheet.size()])
			hud.queue_free()

func test_the_momentum_meter_draws_inside_the_stats_card() -> void:


	for phone in [false, true]:
		var eng := MatchEngine.new(37)
		for i in range(4):
			eng._emit("shot", "Chance!", 0, null, {"xg": 0.3})
		var hud := _hud(eng)
		hud.touch = phone
		hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / (411.0 if phone else 900.0)
		hud.queue_redraw()
		await get_tree().process_frame
		var vp: Vector2 = hud.design_vp()
		var card: Rect2 = HudLayout.stats_rect(vp)
		var meter: Rect2 = HudLayout.momentum_rect(vp)
		assert_true(card.encloses(meter), "the meter left the stats card (phone=%s)" % phone)
		assert_eq(hud.button_at(meter.position + meter.size * 0.5), "", "the meter is a door (phone=%s)" % phone)
		assert_gt(eng.momentum_level().x, 0.5, "the meter had nothing to read (phone=%s)" % phone)
		hud.queue_free()

func test_zoomed_follow_view_draws_the_surname_labels() -> void:
	var eng := MatchEngine.new(36)
	var hud := _hud(eng)
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 411.0
	hud.touch = true
	hud.game.camera_follow = true

	var cam := Camera2D.new()
	cam.zoom = Vector2(40.0, 40.0)
	add_child(cam)
	cam.make_current()
	hud.queue_redraw()
	await get_tree().process_frame
	assert_gt(hud.get_viewport().get_canvas_transform().get_scale().x, 14.0, "the follow zoom never reached the label gate")
	cam.queue_free()
	hud.queue_free()


func test_the_fixture_card_and_team_sheet_follow_the_scene_billing() -> void:
	var eng := MatchEngine.new(4242)
	var hud := _hud(eng)


	assert_eq(HudTopBand.billing_name(BareScene.new(), eng), "PREMIER LEAGUE",
		"the card lost the home club's competition")

	var game := FakeGame.new()
	game.engine = eng
	assert_eq(HudTopBand.billing_name(game, eng), "FRIENDLY", "a friendly's card claims a league")


	MatchBilling.bind_scene(game, "ENG-MUN1", {"matchday": 5})
	assert_eq(HudTopBand.billing_name(game, eng), game.billing.chrome_name(),
		"the card disagrees with the briefing about the competition")
	assert_eq(game.billing.caption(), "PREMIER LEAGUE · MATCHDAY 5",
		"the briefing lost its round")

	for phone in [false, true]:
		hud.touch = phone
		hud.game = game
		hud.queue_redraw()
		await get_tree().process_frame
	hud.queue_free()


class BareScene extends RefCounted:
	pass


func test_every_whistle_hint_names_a_door_the_player_can_reach() -> void:


	assert_eq(HudBannersBand.break_hint("half_time", true, false, false), "SECOND HALF STARTS SHORTLY",
		"the half-time card offered a door")
	assert_eq(HudBannersBand.break_hint("full_time", true, false, false), "TAP PLAY AGAIN",
		"the shown chrome's card stopped naming the bar's PLAY AGAIN door")
	assert_eq(HudBannersBand.break_hint("full_time", true, true, false), "TAP THE CARD TO PLAY AGAIN",
		"a hidden chrome's card named a door that is not on screen")
	assert_eq(HudBannersBand.break_hint("full_time", false, true, false), "PRESS R TO PLAY AGAIN",
		"a keyboard lost its key hint with the chrome")
	assert_eq(HudBannersBand.break_hint("full_time", true, false, true), "TAP TO RETURN TO THE SEASON",
		"a held league result stopped pointing at the season")
	assert_eq(HudBannersBand.break_hint("full_time", false, true, true), "PRESS SPACE TO RETURN TO THE SEASON",
		"a held desktop result lost its SPACE hint")

func test_the_full_time_card_is_the_restart_door_only_with_the_chrome_hidden() -> void:
	var eng := MatchEngine.new(202)
	eng.phase = "full_time"
	var hud := _hud(eng)
	hud.touch = true
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 411.0
	hud.queue_redraw()
	await get_tree().process_frame
	var vp: Vector2 = hud.design_vp()
	var card: Rect2 = HudLayout.break_metrics(vp, 0, 0)["rect"]
	assert_eq(hud.button_at(card.get_center()), "", "the shown chrome's card answered a press")
	hud.set_hud_visible(false, true)
	hud.queue_redraw()
	await get_tree().process_frame
	assert_eq(hud.button_at(card.get_center()), "restart",
		"a hidden chrome left no way to play again from the card")

	assert_eq(hud.button_at(HudLayout.hud_toggle_rect(vp, true).get_center()), "hud",
		"the whistle card stole the HUD pill's press")


	hud.game.result_hold = true
	hud.queue_redraw()
	await get_tree().process_frame
	var live: Array = []
	for b in hud.buttons:
		var id := str(b["id"])
		if id in ["team_0", "team_1"]:
			continue
		live.append(id)
	assert_eq(live, [], "a held league result still answered bar doors: %s" % str(live))
	assert_eq(hud.button_at(card.get_center()), "", "a held league result restarted the match")
	hud.game.result_hold = false
	hud.set_hud_visible(true, true)
	hud.queue_redraw()
	await get_tree().process_frame


	assert_eq(hud.button_at(HudLayout.hud_toggle_rect(vp, true).get_center()), "hud",
		"the pill stayed dead after the season let go")
	hud.queue_free()


func test_a_held_league_result_leaves_no_live_door_on_the_bar() -> void:
	var eng := MatchEngine.new(311)
	eng.phase = "full_time"
	var hud := _hud(eng)
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 900.0
	var vp: Vector2 = hud.design_vp()
	var paint := HudPaint.new(hud.chrome, vp)
	var friendly: Array = hud.controls_band.control_specs(paint, hud.game, false, "full_time")
	var held: Array = hud.controls_band.control_specs(paint, hud.game, false, "full_time", true)
	assert_eq(friendly.size(), held.size(), "a held result reflowed the strip")
	for i in range(friendly.size()):
		assert_eq(str(friendly[i][0]), str(held[i][0]), "door %d changed place under a held result" % i)
		assert_eq(str(friendly[i][1]), str(held[i][1]), "door %d lost its caption under a held result" % i)
		assert_false(bool(held[i][3]), "door %s answered over a held league result (#311)" % str(held[i][0]))


	var live: Array = []
	for spec in friendly:
		if bool(spec[3]):
			live.append(str(spec[0]))
	assert_eq(live, ["mode", "camera", "league", "restart", "menu"],
		"a friendly's whistle lost a door: %s" % str(live))

	var restart: Array = []
	for spec in friendly:
		if str(spec[0]) == "restart":
			restart = spec
	assert_eq(str(restart[1]), "PLAY AGAIN", "the friendly's restart door lost its whistle caption")
	assert_eq(str(restart[2]), "R", "the friendly's restart door lost its key")
	hud.queue_free()

func test_the_paused_banner_resumes_when_the_chrome_is_hidden() -> void:
	var eng := MatchEngine.new(203)
	var hud := _hud(eng)
	hud.touch = true
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 411.0
	hud.game.paused = true
	hud.set_hud_visible(false, true)
	hud.queue_redraw()
	await get_tree().process_frame
	var vp: Vector2 = hud.design_vp()
	var banner := Rect2(vp.x * 0.5 - 130.0, vp.y * 0.5 - 27.0, 260.0, 54.0)
	assert_eq(hud.button_at(banner.get_center()), "pause",
		"a hidden chrome's PAUSED banner pointed at a RESUME door that is not on screen")
	hud.queue_free()

func test_a_finished_match_offers_no_play_doors() -> void:


	var eng := MatchEngine.new(276)
	var hud := _hud(eng)
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 900.0
	var vp: Vector2 = hud.design_vp()
	hud.queue_redraw()
	await get_tree().process_frame
	var bar: Rect2 = HudLayout.controls_rect(vp, hud.touch)
	var bw: float = HudLayout.control_width(vp, hud.touch)
	var gap: float = HudLayout.CONTROL_GAP
	var ids: Array = []
	for b in hud.buttons:
		ids.append(str(b["id"]))
	assert_true(ids.has("pause") and ids.has("speed") and ids.has("skip"),
		"a live match lost its play doors: %s" % str(ids))
	eng.phase = "full_time"
	hud.queue_redraw()
	await get_tree().process_frame
	ids = []
	for b in hud.buttons:
		ids.append(str(b["id"]))
	for id in ["pause", "speed", "skip"]:
		assert_false(ids.has(id), "%s answered on a finished match: %s" % [id, str(ids)])
	for id in ["mode", "camera", "league", "restart", "menu"]:
		assert_true(ids.has(id), "%s left with the whistle: %s" % [id, str(ids)])


	for i in [0, 3]:
		var cell := Rect2(bar.position.x + float(i) * (bw + gap), bar.position.y, bw, HudLayout.CONTROL_H)
		assert_eq(hud.button_at(cell.get_center()), "", "dead door %d still answered a press" % i)
	assert_eq(hud.button_at(Rect2(bar.position.x + 6.0 * (bw + gap), bar.position.y, bw, HudLayout.CONTROL_H).get_center()), "restart",
		"a finished match lost its way to play again")
	var paint := HudPaint.new(hud.chrome, hud.design_vp())
	var restart_spec: Array = []
	for spec in hud.controls_band.control_specs(paint, hud.game, hud.touch, "full_time"):
		if str(spec[0]) == "restart":
			restart_spec = spec
			break
	assert_eq(str(restart_spec[1]), "PLAY AGAIN",
		"a finished match kept the live RESTART caption instead of PLAY AGAIN")
	assert_eq(hud.roster_band.state_label(hud.game, "SIM", "full_time"), "FULL TIME  ·  MATCH OVER",
		"the state line still calls a finished match live")
	hud.queue_free()


func test_a_league_watch_takes_away_the_picker_and_restart() -> void:
	var eng := MatchEngine.new(418)
	var hud := _hud(eng)
	hud.ui_scale = hud.get_viewport().get_visible_rect().size.y / 900.0
	var paint := HudPaint.new(hud.chrome, hud.design_vp())
	hud.queue_redraw()
	await get_tree().process_frame
	var door := Rect2()
	for b in hud.buttons:
		if str(b["id"]) == "teams":
			door = b["rect"]
	assert_true(door.size.x > 0.0, "a single match has no CHANGE TEAMS door")
	assert_eq(hud.button_at(door.get_center()), "teams", "a single match's CHANGE TEAMS answered nothing")

	hud.game.billing.bind_fixture("ENG-MUN1", {"matchday": 3})
	hud.queue_redraw()
	await get_tree().process_frame
	var ids: Array = []
	for b in hud.buttons:
		ids.append(str(b["id"]))
	assert_false(ids.has("teams"), "a league watch drew the fixture picker: %s" % str(ids))
	for id in ["menu", "league", "mode", "camera"]:
		assert_true(ids.has(id), "a league watch lost %s: %s" % [id, str(ids)])
	assert_eq(hud.button_at(door.get_center()), "", "a league watch's CHANGE TEAMS still answered a press")

	for phase in ["play", "full_time"]:
		for touch in [false, true]:
			for spec in hud.controls_band.control_specs(paint, hud.game, touch, phase):
				if str(spec[0]) in ["restart", "teams"]:
					assert_false(bool(spec[3]), "%s stayed live over a league watch (touch=%s, phase=%s)" % [str(spec[0]), touch, phase])

	hud.game.billing.bind_friendly("ENG-MUN1", "ENG-MCI1")
	hud.queue_redraw()
	await get_tree().process_frame
	ids = []
	for b in hud.buttons:
		ids.append(str(b["id"]))
	assert_true(ids.has("teams"), "the picker did not come back for a single match: %s" % str(ids))
	var restart_live := false
	for spec in hud.controls_band.control_specs(paint, hud.game, true, "play"):
		if str(spec[0]) == "restart":
			restart_live = bool(spec[3])
	assert_true(restart_live, "a single match lost its RESTART")
	hud.queue_free()

func test_the_card_draws_the_full_sheet_on_a_desktop_and_keeps_its_bars_on_a_phone() -> void:
	var eng := MatchEngine.new(41)
	var hud := _hud(eng)
	hud.game.focus_id = eng.players[2].id
	hud.ui_scale = 1.0
	hud.card.mode = "FULL"
	hud.queue_redraw()
	await get_tree().process_frame
	assert_gt(hud.card.rect_for(hud.design_vp()).size.y, 300.0, "the Full reading left the desktop column")
	assert_gte(hud.card._subs(eng.players[2]).size(), 30, "the card found no sub-stat sheet")
	var door: Rect2 = hud.card.attrs_rect(hud.design_vp())
	assert_true(door.size.x > 100.0, "the desktop door is too narrow for its pair")
	hud.card.mode = "SIMPLIFIED"
	hud.queue_redraw()
	await get_tree().process_frame
	assert_eq(hud.card.rect_for(hud.design_vp()), hud.card.rect_for(hud.design_vp()),
		"the card moved when the reading changed")
	hud.queue_free()
