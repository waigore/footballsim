extends GdToolsTest

## The broadcast overlay draws end to end: every panel, the ticker and the
## control bar. Geometry is asserted, not eyeballed, so the ticker can never
## creep back over a button.

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
	## The scene field the broadcast reads when a league watch holds its card (#124).
	var result_hold := false

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
	eng.manager._apply(0, {"mentality": "attacking", "line_delta": 0.06}, "test")
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
	# Seven bar doors plus the two club doors on the scoreboard chrome.
	assert_eq(ids.size(), HudLayout.CONTROL_COUNT_TOUCH + 2, "the phone bar should hold seven doors and two club doors: %s" % str(ids))
	for b in hud.buttons:
		var r: Rect2 = b["rect"]
		var mid: Vector2 = r.position + r.size * 0.5
		assert_eq(hud.button_at(mid), str(b["id"]), "%s is not tappable at its centre" % str(b["id"]))
		assert_lte(r.end.x, vp.x, "%s runs off the right edge" % str(b["id"]))
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
	assert_eq(ids.size(), HudLayout.CONTROL_COUNT + 1 + 2, "desktop bar should hold seven controls, the door and the two club doors")
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
	# The dossier is a column under the stats card; the card's momentum footer
	# grew it (DR-20261125-02), so the column must read its bottom, never a
	# constant it would now overlap.
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
	# #124: a league watch keeps this card, so its line points back at the season.
	hud.game.result_hold = true
	hud.queue_redraw()
	await get_tree().process_frame
	hud.game.result_hold = false
	assert_true(HudLayout.is_compact(hud.design_vp()), "banners were drawn in desktop metrics")
	hud.queue_free()

func test_the_momentum_meter_draws_inside_the_stats_card() -> void:
	# DR-20261125-02: the summary's momentum reading reaches the broadcast on
	# both metrics, and the meter is paint only — never a door.
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
	# The follow camera's zoom multiplier is what lifts labels above the gate.
	var cam := Camera2D.new()
	cam.zoom = Vector2(40.0, 40.0)
	add_child(cam)
	cam.make_current()
	hud.queue_redraw()
	await get_tree().process_frame
	assert_gt(hud.get_viewport().get_canvas_transform().get_scale().x, 14.0, "the follow zoom never reached the label gate")
	cam.queue_free()
	hud.queue_free()
