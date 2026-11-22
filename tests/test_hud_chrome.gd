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
