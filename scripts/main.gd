extends Node2D

## Playback controller + scene assembly: the engine, the snapshot ring, the
## camera and the input bindings. Design-space arithmetic and the sheet routing
## live in MatchView / MatchInput so the scene stays inside its P3 size budget.

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
## The broadcast ring and the goal captures it makes (see HighlightDirector).
var highlights: HighlightDirector = null
## A stored goal clip being played over the pitch, or null.
var replay: GoalReplay = null
var half_time_timer := -1.0
var focus_id := -1
var hover_id := -1
var names_visible := true
var camera_follow: bool = MatchView.default_follow()  # follow on phones (#158)
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
var audio: MatchAudio = null
var camera: MatchCamera = null
var view: MatchView = null
var input: MatchInput = null
var fixture: FixtureSheet = null
var batch_abort := false
var hud_scale := 1.0
## Reading scale for the non-match layers; the match HUD keeps HudLayout's.
var chrome_scale := 1.0
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
## Menu shell: main menu, settings, quit confirm and the menu music.
var menus: MenuHost = null
var select_from_menu := false
var match_started := false
## Encyclopedia sheet: league / club / player pages over the paused broadcast.
var wiki_host: WikiHost = null
## The pre-match briefing (#157): the last screen before a watched or single
## match starts. League watches and the fixture picker both ask it first.
var prematch: PreMatchHost = null
## A finished match is written to the cached seed exactly once.
var result_recorded := false
## A league watch keeps its FULL TIME card until the player taps it away (#124);
## LeagueHost owns the flag, the broadcast only reads it.
var result_hold := false

func _ready() -> void:
	build_scene()
	setup_audio()
	highlights = HighlightDirector.new(self)
	fixture_arg_given = fixture.parse_args()
	new_match(seeded)
	dev = DevCapture.new()
	dev.parse(self)
	wiki_host = WikiHost.new(self)
	wiki_host.build()
	fixture.build()
	prematch = PreMatchHost.mount(self)
	menus = MenuHost.new()
	menus.attach(self)
	_sync_overlay_scale()
	menus.pose(dev)

func setup_audio() -> void:
	audio = MatchAudio.new(self)
	audio.setup()

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
	camera = MatchCamera.new(self)
	view = MatchView.new(self)
	input = MatchInput.new(self)
	fixture = FixtureSheet.new(self)
	_sync_overlay_scale()
	camera.fit()
	actors.game = self

## Handhelds read the match overlay at one density point per design unit; the
## non-match chrome (menus, settings, league and encyclopedia sheets) has its
## own scale. Each layer keeps its own transform; MatchView owns the numbers and
## the scene hands back the overlay layer it created.
func _sync_overlay_scale() -> void:
	var scales: Dictionary = view.overlay_scale(hud_layer, dev)
	hud_scale = float(scales["hud"])
	touch = bool(scales["touch"])
	chrome_scale = float(scales["chrome"])
	token_scale = float(scales["token"])
	actors.token_scale = token_scale
	hud.ui_scale = hud_scale
	hud.touch = touch
	hud_layer.transform = Transform2D.IDENTITY.scaled(Vector2(hud_scale, hud_scale))
	var frame := Transform2D.IDENTITY.scaled(Vector2(chrome_scale, chrome_scale))
	if sel_layer != null:
		sel_layer.transform = frame
		selector.ui_scale = chrome_scale
	if wiki_host != null:
		wiki_host.sync_scale()
	if prematch != null:
		prematch.sync(frame, chrome_scale, touch)
	if menus != null:
		menus.sync(frame, chrome_scale, touch)
	if camera != null:
		camera.fit()

func new_match(seed: int) -> void:
	if replay != null:
		replay.finish(false)
		replay = null
	if engine != null and engine.event_fired.is_connected(_on_engine_event):
		engine.event_fired.disconnect(_on_engine_event)
	engine = MatchEngine.new(seed, home_id, away_id)
	engine.verbose = false
	engine.event_fired.connect(_on_engine_event)
	engine.ball_kicked.connect(audio.ball_kicked)
	actors.engine = engine
	actors.ball_trail.clear()
	hud.engine = engine
	batch_abort = false
	focus_id = -1
	hover_id = -1
	in_highlight = false
	fast_mode = true
	highlight_until = -1.0
	paused = false
	speed = 1.0
	accumulator = 0.0
	half_time_timer = -1.0
	replay_banner = 0.0
	last_event_notice = 0.0
	match_time = 0.0
	cam.position = Vector2(L * 0.5, W * 0.5 + pitch_shift)
	cam.zoom = Vector2(base_zoom, base_zoom)
	result_recorded = false
	highlights.restart()

# --------------------------------------------------------------- fixture ----

func open_select(from_menu: bool = false) -> void:
	fixture.open(from_menu)

func _close_select() -> void:
	fixture.close()

func _on_fixture_confirmed(h: String, a: String) -> void:
	fixture.confirm(h, a)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_sync_overlay_scale()

# ------------------------------------------------------------------ input ----

## Sheets, the wheel, the overlay bar and the one-key controls all route
## through MatchInput; the scene only exposes its state.
func _input(event: InputEvent) -> void:
	input.handle(event)

func _click(p: Vector2) -> void:
	var b: String = view.button_at(p)
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
	elif b == "menu":
		menus.open_menu()
	elif b == "league":
		wiki_host.open_page(WikiModel.LEAGUE, "")
	elif b == "team_0":
		wiki_host.open_page(WikiModel.TEAM, str(engine.teams[0]["id"]))
	elif b == "team_1":
		wiki_host.open_page(WikiModel.TEAM, str(engine.teams[1]["id"]))
	elif b == "profile":
		var tracked = engine.by_id.get(focus_id, null)
		if tracked != null and str(tracked.key) != "":
			wiki_host.open_page(WikiModel.PLAYER, str(tracked.key))
	elif b == "manager_card":
		hud.manager_card.dismiss()
	elif b == "restart":
		new_match(seeded + randi_range(0, 9999))
	if b != "":
		return

	hover_id = view.pick(p)
	focus_id = -1 if hover_id < 0 or focus_id == hover_id else hover_id
	actors.focus_id = focus_id

func _cycle_speed() -> void:
	var opts := [1.0, 2.0, 4.0, 8.0]
	var idx := opts.find(speed)
	speed = opts[(idx + 1) % opts.size()]

func _toggle_mode() -> void:
	set_mode(Prefs.next_mode(mode))

## Every door into the match view — `H`, the bar's mode door, the Settings sheet
## — lands here, and the prefs file remembers the choice (#164).
func set_mode(next: String) -> void:
	view.set_mode(next)
	if menus != null:
		menus.save_mode(mode)

func _skip() -> void:
	if replay != null:
		# Skip inside a stored clip ends it and hands the report back.
		replay.finish(true)
		replay = null
		return
	if mode != "full":
		if in_highlight:
			_end_highlight()
		elif fast_mode:
			_advance_ticks(60 * 10)
	else:
		_advance_ticks(60 * 10)

# ------------------------------------------------------------------ loop ----

func _process(delta: float) -> void:
	elapsed_real += delta
	match_time += delta
	dev.tick(self, delta)
	if prematch != null and prematch.is_open():
		return
	if wiki_host != null and wiki_host.is_open():
		return
	if menus != null and menus.active():
		return
	if select_open:
		return
	var zm: float = zoom_scale * (2.6 if camera_follow else (1.10 if in_highlight else 1.0))
	cam.zoom = cam.zoom.lerp(Vector2(base_zoom * zm, base_zoom * zm), clampf(delta * 3.0, 0.0, 1.0))
	if camera != null:
		camera.update(delta)
	_apply_camera(false)
	if not dev.apply_hover(self):
		view.hover(mouse)

	if replay != null:
		# A stored clip owns the broadcast until it ends: the pack drives the
		# bodies, so nothing here may tick the engine.
		if replay.step(delta):
			replay = null
		return
	if engine.phase == "full_time":
		if not result_recorded:
			result_recorded = PLSimStats.record_match(engine)
		return
	if engine.phase == "half_time":
		if half_time_timer < 0.0:
			half_time_timer = 4.0
		half_time_timer -= delta
		if half_time_timer <= 0.0 and not paused:
			engine.begin_second_half()
			half_time_timer = -1.0
			highlights.restart()
		return
	if paused:
		return

	_advance_ticks(view.ticks_this_frame(delta))
	_post_tick()

func _advance_ticks(n: int) -> void:
	var budget := Time.get_ticks_usec() + 9000
	for i in range(n):
		if engine.phase == "half_time" or engine.phase == "full_time" or batch_abort:
			batch_abort = false
			break
		engine.tick()
		highlights.sample()
		if Time.get_ticks_usec() > budget and i > 2:
			break

func _post_tick() -> void:
	replay_banner = maxf(0.0, replay_banner - get_process_delta_time())
	if in_highlight:
		if engine.clock > highlight_until:
			_end_highlight()
	elif mode != "full":
		fast_mode = true
	if camera != null:
		camera.update_target()
	_apply_camera(false)

func _end_highlight() -> void:
	in_highlight = false
	highlight_until = -1.0
	if mode != "full":
		fast_mode = true

func _snapshot() -> void:
	highlights.snapshot()

## Play one stored goal clip on the broadcast. The league hands the pack back
## with `on_done`, which puts its report sheet back on screen when the clip ends.
func play_goal_clip(pack: Dictionary, on_done := Callable()) -> void:
	if replay != null:
		replay.finish(false)
		replay = null
	replay = GoalReplay.open(self, pack, on_done)
	if replay == null and on_done.is_valid():
		on_done.call()

func _on_engine_event(e: Dictionary) -> void:
	var kind: String = e.get("type", "")
	if kind == "goal":
		last_event_notice = 3.0
		audio.play("goal_roar", -4.0)
		audio.play("whistle", -12.0, 0.98)
	elif kind == "save":
		audio.play("ooh", -9.0)
	elif kind in ["foul", "offside", "half_time", "full_time", "kickoff"]:
		audio.play("whistle", -14.0, randf_range(0.97, 1.03))
	elif kind == "miss":
		audio.play("ooh", -12.0)
	highlights.on_event(e)

# ---------------------------------------------------------------- camera ----

func _apply_camera(snap_zoom: bool) -> void:
	if camera != null:
		camera.apply(snap_zoom)

