class_name MatchPlayback
extends RefCounted


const SKIP_BUDGET_USEC := 16000

const SKIP_TICK_CAP := 240

const BREAK_PHASES := ["half_time", "et_break", "full_time"]

var game = null

func _init(host: Node) -> void:
	game = host


func tick(delta: float) -> void:
	game.elapsed_real += delta
	game.match_time += delta
	game.dev.tick(game, delta)
	if game.prematch != null and game.prematch.is_open():
		return
	if game.wiki_host != null and game.wiki_host.is_open():
		return
	if game.menus != null and game.menus.active():
		return
	if game.select_open:
		return
	var zm: float = game.zoom_scale * (2.6 if game.camera_follow else (1.10 if game.in_highlight else 1.0))
	game.cam.zoom = game.cam.zoom.lerp(
		Vector2(game.base_zoom * zm, game.base_zoom * zm), clampf(delta * 3.0, 0.0, 1.0))
	if game.camera != null:
		game.camera.update(delta)
	game._apply_camera(false)
	if not game.dev.apply_hover(game):
		game.view.hover(game.mouse)

	if game.replay != null:
		if game.replay.step(delta):
			game.replay = null
		return
	if game.engine.phase == "full_time":
		game.skip_armed = false
		if game.highlights.flush():
			return
		if not game.result_recorded:
			game.result_recorded = PLSimStats.record_match(game.engine)
		return
	if game.engine.phase == "half_time" or game.engine.phase == "et_break":
		game.skip_armed = false
		if game.highlights.flush():
			return
		if game.half_time_timer < 0.0:
			game.half_time_timer = 4.0
		game.half_time_timer -= delta
		if game.half_time_timer <= 0.0 and not game.paused:
			game.engine.resume_after_break() if game.engine.phase == "et_break" else game.engine.begin_second_half()
			game.half_time_timer = -1.0
			game.highlights.restart()
		return
	if game.paused:
		game.skip_armed = false
		return

	if game.skip_armed:
		advance_skip()
		post_tick()
		return
	advance_ticks(game.view.ticks_this_frame(delta))
	post_tick()

func advance_ticks(n: int) -> void:
	var budget := Time.get_ticks_usec() + 9000
	for i in range(n):
		var stopped: bool = game.engine.phase in ["half_time", "et_break", "full_time"]
		if stopped or game.batch_abort:
			game.batch_abort = false
			break
		game.engine.tick()
		game.highlights.sample()
		if Time.get_ticks_usec() > budget and i > 2:
			break

func post_tick() -> void:
	game.replay_banner = maxf(0.0, game.replay_banner - game.get_process_delta_time())
	if game.replay == null:
		if game.in_highlight:
			if game.engine.clock > game.highlight_until:
				end_highlight()
		elif game.mode != "full":
			game.fast_mode = true
	if game.camera != null:
		game.camera.update_target()
	game._apply_camera(false)

func end_highlight() -> void:
	game.in_highlight = false
	game.highlight_until = -1.0
	if game.mode != "full":
		game.fast_mode = true


func skip() -> void:
	if game.replay != null:
		game.replay.finish(true)
		game.replay = null
		return
	if game.skip_armed:
		game.skip_armed = false
		return
	if game.engine == null or str(game.engine.phase) in BREAK_PHASES:
		return
	if game.in_highlight:
		end_highlight()
	game.paused = false
	game.skip_armed = true
	advance_skip()


func advance_skip() -> void:
	var engine = game.engine
	if engine == null:
		game.skip_armed = false
		return
	var budget := Time.get_ticks_usec() + SKIP_BUDGET_USEC
	for i in range(SKIP_TICK_CAP):
		if str(engine.phase) in BREAK_PHASES or game.batch_abort:
			game.batch_abort = false
			game.skip_armed = false
			return
		engine.tick()
		game.highlights.sample()
		if Time.get_ticks_usec() > budget:
			return


func on_engine_event(e: Dictionary) -> void:
	var kind: String = e.get("type", "")
	if kind == "goal":
		game.last_event_notice = 3.0
		game.audio.play("goal_roar", -4.0)
		game.audio.play("whistle", -12.0, 0.98)
	elif kind == "save":
		game.audio.play("ooh", -9.0)
	elif kind in ["foul", "offside", "half_time", "full_time", "kickoff", "extra_time",
			"extra_time_break", "shootout_start", "shootout_end"]:
		game.audio.play("whistle", -14.0, randf_range(0.97, 1.03))
	elif kind == "miss" or kind == "penalty_missed":
		game.audio.play("ooh", -12.0)
	if game.skip_armed:
		if kind == "goal":
			game.highlights.capture(e)
		return
	game.highlights.on_event(e)
