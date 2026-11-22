extends Node2D

## Playback controller + scene assembly.
## Owns the engine, the snapshot ring buffer that makes highlight replays possible,
## the camera and every input binding.

const W := 68.0
const L := 105.0

var engine = null
var arena: Node2D
var pitch
var actors
var cam: Camera2D
var hud
var hud_layer: CanvasLayer

var mode := "highlights"
var paused := false
var speed := 1.0
var fast_mode := true
var in_highlight := false
var highlight_until := -1.0
var replay_banner := 0.0
var seeded := 1000

var accumulator := 0.0
var history: Array = []
var hist_timer := 0.0
var shown_triggers := {}
var half_time_timer := -1.0
var focus_id := -1
var hover_id := -1
var names_visible := true
var camera_follow := false
var zoom_scale := 1.0
var base_zoom := 11.0
var mouse := Vector2.ZERO
var last_event_notice := 0.0

var shot_times: Array = []
var shot_index := 0
var goal_captured := false
var paused_start := false
var quit_after := -1.0
var elapsed_real := 0.0
var match_time := 0.0
var crowd: AudioStreamPlayer
var sfx_pool: Array = []
var sfx_next := 0
var sfx_streams := {}
var batch_abort := false
var hud_scale := 1.0
var token_scale := 1.0
var pitch_shift := 0.0
var touch := false
var dev: DevCapture = null

var home_id := "MUN"
var away_id := "MCI"
var select_open := false
var selector = null
var sel_layer: CanvasLayer
var fixture_arg_given := false

func _ready() -> void:
	build_scene()
	setup_audio()
	_parse_fixture_args()
	new_match(seeded)
	dev = DevCapture.new()
	dev.parse(self)
	_sync_overlay_scale()
	_build_selector()
	if not fixture_arg_given:
		open_select()

func setup_audio() -> void:
	crowd = AudioStreamPlayer.new()
	var cs = load("res://audio/crowd_loop.wav")
	if cs != null:
		cs.loop_mode = AudioStreamWAV.LOOP_FORWARD
		cs.loop_end = int(cs.get_length() * cs.mix_rate)
	crowd.stream = cs
	crowd.volume_db = -21.0
	add_child(crowd)
	crowd.play()
	for n in ["kick", "whistle", "goal_roar", "ooh"]:
		var st = load("res://audio/%s.wav" % n)
		sfx_streams[n] = st
	for i in range(6):
		var pl := AudioStreamPlayer.new()
		pl.volume_db = -8.0
		add_child(pl)
		sfx_pool.append(pl)

func play_sfx(name: String, vol_db: float = -8.0, pitch: float = 1.0) -> void:
	if not sfx_streams.has(name) or sfx_streams[name] == null:
		return
	var pl: AudioStreamPlayer = sfx_pool[sfx_next % sfx_pool.size()]
	sfx_next += 1
	pl.stream = sfx_streams[name]
	pl.volume_db = vol_db
	pl.pitch_scale = pitch
	pl.play()

func _on_ball_kicked(strength: float) -> void:
	play_sfx("kick", -10.0 + strength * 4.0, randf_range(0.9, 1.08))

func build_scene() -> void:
	arena = Node2D.new()
	arena.name = "Arena"
	add_child(arena)
	pitch = Node2D.new()
	pitch.set_script(load("res://scripts/view/pitch_view.gd"))
	arena.add_child(pitch)
	actors = Node2D.new()
	actors.set_script(load("res://scripts/view/actor_layer.gd"))
	arena.add_child(actors)
	cam = Camera2D.new()
	cam.position = Vector2(L * 0.5, W * 0.5)
	cam.enabled = true
	arena.add_child(cam)
	cam.make_current()
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = Control.new()
	hud.set_script(load("res://scripts/ui/hud.gd"))
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud)
	hud.game = self
	touch = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	_sync_overlay_scale()
	_recalc_zoom()
	actors.game = self

## Handhelds read the overlay at roughly one density point per design unit: the
## layer is scaled up by HudLayout.overlay_scale() and every rect is derived
## from the smaller design viewport, so type and tap targets grow with the
## screen instead of shrinking with it.
func _sync_overlay_scale() -> void:
	hud_scale = HudLayout.overlay_scale()
	if dev != null and dev.ui_scale > 0.0:
		hud_scale = dev.ui_scale
		touch = true
	token_scale = 1.5 if HudLayout.is_compact(get_viewport_rect().size / hud_scale) else 1.0
	actors.token_scale = token_scale
	hud.ui_scale = hud_scale
	hud.touch = touch
	var frame := Transform2D.IDENTITY.scaled(Vector2(hud_scale, hud_scale))
	hud_layer.transform = frame
	if sel_layer != null:
		sel_layer.transform = frame

func new_match(seed: int) -> void:
	if engine != null and engine.event_fired.is_connected(_on_engine_event):
		engine.event_fired.disconnect(_on_engine_event)
	if engine != null and engine.ball_kicked.is_connected(_on_ball_kicked):
		engine.ball_kicked.disconnect(_on_ball_kicked)
	engine = MatchEngine.new(seed, home_id, away_id)
	engine.verbose = false
	engine.event_fired.connect(_on_engine_event)
	engine.ball_kicked.connect(_on_ball_kicked)
	actors.engine = engine
	actors.ball_trail.clear()
	hud.engine = engine
	history.clear()
	shown_triggers.clear()
	batch_abort = false
	focus_id = -1
	hover_id = -1
	in_highlight = false
	fast_mode = true
	highlight_until = -1.0
	paused = false
	speed = 1.0
	accumulator = 0.0
	hist_timer = 0.0
	half_time_timer = -1.0
	replay_banner = 0.0
	last_event_notice = 0.0
	match_time = 0.0
	cam.position = Vector2(L * 0.5, W * 0.5 + pitch_shift)
	cam.zoom = Vector2(base_zoom, base_zoom)
	_snapshot()

func _recalc_zoom() -> void:
	var geo := HudLayout.pitch_fit(get_viewport_rect().size, hud_scale, touch)
	base_zoom = clampf(float(geo["zoom"]), 3.0, 16.0)
	pitch_shift = float(geo["offset"])
	if cam != null:
		cam.zoom = Vector2(base_zoom * zoom_scale, base_zoom * zoom_scale)

# --------------------------------------------------------------- fixture ----

func _build_selector() -> void:
	if selector != null:
		return
	sel_layer = CanvasLayer.new()
	sel_layer.layer = 20
	add_child(sel_layer)
	selector = Control.new()
	selector.set_script(load("res://scripts/ui/team_select.gd"))
	selector.set_anchors_preset(Control.PRESET_FULL_RECT)
	selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_layer.add_child(selector)
	selector.confirmed.connect(_on_fixture_confirmed)
	selector.cancelled.connect(_close_select)
	sel_layer.transform = Transform2D.IDENTITY.scaled(Vector2(hud_scale, hud_scale))
	selector.ui_scale = hud_scale
	selector.touch = touch
	sel_layer.visible = false

func open_select() -> void:
	if selector == null:
		return
	select_open = true
	paused = true
	selector.setup(home_id, away_id)
	if hud_layer != null:
		hud_layer.visible = false
	sel_layer.visible = true
	selector.visible = true

func _close_select() -> void:
	select_open = false
	if sel_layer != null:
		sel_layer.visible = false
	if hud_layer != null:
		hud_layer.visible = true
	paused = false

func _on_fixture_confirmed(h: String, a: String) -> void:
	home_id = h
	away_id = a
	select_open = false
	if sel_layer != null:
		sel_layer.visible = false
	if hud_layer != null:
		hud_layer.visible = true
	seeded += randi_range(1, 9999)
	new_match(seeded)

func _parse_fixture_args() -> void:
	var known: Array = TeamData.team_ids()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seeded = int(a.substr(7))
		elif a.begins_with("--home="):
			var h := a.substr(7).to_upper()
			if known.has(h):
				home_id = h
				fixture_arg_given = true
		elif a.begins_with("--away="):
			var w := a.substr(7).to_upper()
			if known.has(w):
				away_id = w
				fixture_arg_given = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_sync_overlay_scale()
		_recalc_zoom()

# ------------------------------------------------------------------ input ----

func _input(event: InputEvent) -> void:
	if select_open:
		if event is InputEventMouseMotion:
			mouse = event.position
			selector.mouse = _design(event.position)
			if not touch:
				Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if selector.button_at(selector.mouse) != "" else Input.CURSOR_ARROW)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			mouse = event.position
			selector.mouse = _design(event.position)
			var sid: String = selector.button_at(selector.mouse)
			if sid != "":
				selector.click(sid)
		elif event is InputEventKey and event.pressed and not event.echo:
			selector.key(event.keycode)
		return
	if event is InputEventMouseMotion:
		mouse = event.position
		_update_hover()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_scale = clampf(zoom_scale * 1.08, 0.65, 2.4)
			_apply_camera(true)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_scale = clampf(zoom_scale / 1.08, 0.65, 2.4)
			_apply_camera(true)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			mouse = event.position
			_click(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		# if/elif rather than match: the coverage injector cannot instrument a
		# match statement, and an uninstrumentable main.gd fails the patch gate.
		var k: int = event.keycode
		if k == KEY_SPACE:
			paused = not paused
		elif k == KEY_1:
			speed = 1.0
		elif k == KEY_2:
			speed = 2.0
		elif k == KEY_3:
			speed = 4.0
		elif k == KEY_4:
			speed = 8.0
		elif k == KEY_H:
			_toggle_mode()
		elif k == KEY_S:
			_skip()
		elif k == KEY_R:
			new_match(seeded + randi_range(0, 9999))
		elif k == KEY_N:
			names_visible = not names_visible
			actors.names_visible = names_visible
		elif k == KEY_C:
			camera_follow = not camera_follow
		elif k == KEY_T:
			open_select()
		elif k == KEY_ESCAPE:
			if focus_id >= 0:
				focus_id = -1
			else:
				get_tree().quit()

## Overlay widgets live in design space; pointer events arrive in logical
## viewport units.
func _design(p: Vector2) -> Vector2:
	return p / maxf(hud_scale, 0.001)

func _click(p: Vector2) -> void:
	var b: String = hud.button_at(_design(p))
	if b == "pause":
		paused = not paused
	elif b == "speed":
		_cycle_speed()
	elif b == "mode":
		_toggle_mode()
	elif b == "skip":
		_skip()
	elif b == "camera":
		camera_follow = not camera_follow
	elif b == "teams":
		open_select()
	elif b == "manager_card":
		hud.manager_card.dismiss()
	elif b == "restart":
		new_match(seeded + randi_range(0, 9999))
	if b != "":
		return
	hover_id = _pick(p)
	if hover_id >= 0:
		focus_id = -1 if focus_id == hover_id else hover_id
		actors.focus_id = focus_id
	else:
		focus_id = -1
		actors.focus_id = -1

func _cycle_speed() -> void:
	var opts := [1.0, 2.0, 4.0, 8.0]
	var idx := opts.find(speed)
	speed = opts[(idx + 1) % opts.size()]

func _toggle_mode() -> void:
	mode = "full" if mode == "highlights" else "highlights"
	if mode == "full":
		fast_mode = false
		in_highlight = false
		highlight_until = -1.0
		paused = false
		speed = 1.0
	else:
		fast_mode = not in_highlight
		if not in_highlight:
			in_highlight = false
			highlight_until = -1.0

func _skip() -> void:
	if mode == "highlights":
		if in_highlight:
			_end_highlight()
		elif fast_mode:
			_advance_ticks(60 * 10)
	else:
		_advance_ticks(60 * 10)

## Nearest player to a logical-space point, within a radius a finger can hit.
func _pick(p: Vector2) -> int:
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * p
	var best = null
	var reach: float = 2.8 if touch else 1.7
	var bd := reach * reach
	for q in engine.players:
		if q.sent_off:
			continue
		var d: float = q.pos.distance_squared_to(world)
		if d < bd:
			bd = d
			best = q
	return -1 if best == null else best.id

func _update_hover() -> void:
	hover_id = _pick(mouse)
	actors.hover_id = hover_id
	hud.mouse = _design(mouse)
	if not touch:
		var over_button: bool = hud.button_at(hud.mouse) != ""
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if (hover_id >= 0 or over_button) else Input.CURSOR_ARROW)

# ------------------------------------------------------------------ loop ----

func _process(delta: float) -> void:
	elapsed_real += delta
	match_time += delta
	dev.tick(self, delta)
	if select_open:
		return
	var zm: float = zoom_scale * (2.6 if camera_follow else (1.10 if in_highlight else 1.0))
	cam.zoom = cam.zoom.lerp(Vector2(base_zoom * zm, base_zoom * zm), clampf(delta * 3.0, 0.0, 1.0))
	_update_camera(delta)
	_apply_camera(false)
	if not dev.apply_hover(self):
		_update_hover()

	if engine.phase == "full_time":
		return
	if engine.phase == "half_time":
		if half_time_timer < 0.0:
			half_time_timer = 4.0
		half_time_timer -= delta
		if half_time_timer <= 0.0 and not paused:
			engine.begin_second_half()
			half_time_timer = -1.0
			history.clear()
			_snapshot()
		return
	if paused:
		return

	var ticks := 0
	if mode == "highlights" and fast_mode:
		accumulator += delta * 60.0 * 24.0
		ticks = int(accumulator)
		accumulator -= ticks
		ticks = mini(ticks, 60)
	else:
		accumulator += delta * 60.0 * speed
		ticks = int(accumulator)
		accumulator -= ticks
		ticks = mini(ticks, 120)
	_advance_ticks(ticks)
	_post_tick()

func _advance_ticks(n: int) -> void:
	var budget := Time.get_ticks_usec() + 9000
	for i in range(n):
		if engine.phase == "half_time" or engine.phase == "full_time" or batch_abort:
			batch_abort = false
			break
		engine.tick()
		hist_timer += 1.0 / 60.0
		if hist_timer >= 0.45:
			hist_timer = 0.0
			_snapshot()
		if Time.get_ticks_usec() > budget and i > 2:
			break

func _post_tick() -> void:
	replay_banner = maxf(0.0, replay_banner - get_process_delta_time())
	if in_highlight:
		if engine.clock > highlight_until:
			_end_highlight()
	elif mode == "highlights":
		fast_mode = true
	_update_camera_target()
	_apply_camera(false)

func _end_highlight() -> void:
	in_highlight = false
	highlight_until = -1.0
	if mode == "highlights":
		fast_mode = true

func _snapshot() -> void:
	history.append(engine.to_dict())
	if history.size() > 40:
		history.pop_front()

func _rewind_for(trigger_clock: float) -> bool:
	if history.is_empty():
		return false
	var target := trigger_clock - 7.0
	var best: Dictionary = history[0]
	for s in history:
		if float(s["clock"]) <= target:
			best = s
		else:
			break
	if float(best["clock"]) > trigger_clock - 1.0:
		best = history[0]
	var trimmed := []
	for s2 in history:
		if float(s2["clock"]) <= float(best["clock"]) + 0.01:
			trimmed.append(s2)
	history = trimmed
	engine.from_dict(best)
	actors.ball_trail.clear()
	batch_abort = true
	return true

func _on_engine_event(e: Dictionary) -> void:
	var kind: String = e.get("type", "")
	var key := "%d|%s|%d" % [int(float(e.get("clock", 0.0)) * 60.0), kind, int(e.get("player_id", -1))]
	if kind == "goal":
		last_event_notice = 3.0
		play_sfx("goal_roar", -4.0)
		play_sfx("whistle", -12.0, 0.98)
	elif kind == "save":
		play_sfx("ooh", -9.0)
	elif kind in ["foul", "offside", "half_time", "full_time", "kickoff"]:
		play_sfx("whistle", -14.0, randf_range(0.97, 1.03))
	elif kind == "miss":
		play_sfx("ooh", -12.0)
	if mode != "highlights":
		return
	if shown_triggers.has(key):
		return
	var important: bool = kind in ["shot", "goal", "penalty", "penalty_taken", "card", "corner"]
	if not important:
		return
	if in_highlight:
		# extend the live window around goals and late chances
		highlight_until = maxf(highlight_until, engine.clock + (5.0 if kind == "goal" else 3.0))
		return
	if kind in ["shot", "penalty", "corner"]:
		shown_triggers[key] = true
		if _rewind_for(engine.clock):
			in_highlight = true
			fast_mode = false
			highlight_until = engine.clock + 12.0
			replay_banner = 2.2
			accumulator = 0.0
	elif kind == "goal" or kind == "card":
		shown_triggers[key] = true
		if _rewind_for(engine.clock):
			in_highlight = true
			fast_mode = false
			highlight_until = engine.clock + 12.0
			replay_banner = 2.2

# ---------------------------------------------------------------- camera ----

var cam_target := Vector2(L * 0.5, W * 0.5)

func _update_camera_target() -> void:
	if camera_follow:
		var b: Vector2 = engine.ball.pos
		var half_w := (get_viewport_rect().size.x / (base_zoom * zoom_scale)) * 0.5
		var half_h := (get_viewport_rect().size.y / (base_zoom * zoom_scale)) * 0.5
		cam_target = Vector2(
			clampf(b.x, half_w - 8.0, L - half_w + 8.0),
			clampf(b.y, half_h - 6.0, W - half_h + 6.0)
		)
		if half_w * 2.0 > L + 20.0:
			cam_target.x = L * 0.5
		if half_h * 2.0 > W + 18.0:
			cam_target.y = W * 0.5
	else:
		cam_target = Vector2(L * 0.5, W * 0.5 + pitch_shift)

func _update_camera(delta: float) -> void:
	_update_camera_target()
	cam.position = cam.position.lerp(cam_target, clampf(delta * 4.0, 0.0, 1.0))

func _apply_camera(snap_zoom: bool) -> void:
	if snap_zoom:
		cam.zoom = Vector2(base_zoom * zoom_scale, base_zoom * zoom_scale)

