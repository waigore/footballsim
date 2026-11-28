extends Node2D


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

var highlights: HighlightDirector = null

var replay: GoalReplay = null
var half_time_timer := -1.0
var focus_id := -1
var hover_id := -1
var names_visible := true
var camera_follow: bool = MatchView.default_follow()
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

var playback: MatchPlayback = null
var fixture: FixtureSheet = null
var batch_abort := false
var hud_scale := 1.0

var chrome_scale := 1.0
var token_scale := 1.0
var pitch_shift := 0.0
var touch := false
var dev: DevCapture = null

var home_id := "ENG-MUN1"
var away_id := "ENG-MCI1"
var select_open := false
var selector = null
var sel_layer: CanvasLayer
var fixture_arg_given := false

var menus: MenuHost = null
var select_from_menu := false
var match_started := false

var wiki_host: WikiHost = null


var prematch: PreMatchHost = null

var result_recorded := false


var billing: MatchBilling = MatchBilling.new()


var result_hold := false

var skip_armed := false

var back_stamp := -100000

func _ready() -> void:
	MatchScene.build(self)
	audio = MatchAudio.new(self)
	audio.setup()
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

func _sync_overlay_scale() -> void:
	view.sync_overlays(hud_layer, dev)

func new_match(seed: int) -> void:
	if replay != null:
		replay.finish(false)
		replay = null
	if engine != null and engine.event_fired.is_connected(_on_engine_event):
		engine.event_fired.disconnect(_on_engine_event)
	engine = MatchEngine.new(seed, home_id, away_id, CommentaryRender.render)
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
	skip_armed = false
	match_time = 0.0
	cam.position = Vector2(L * 0.5, W * 0.5 + pitch_shift)
	cam.zoom = Vector2(base_zoom, base_zoom)
	result_recorded = false
	highlights.restart()


func open_select(from_menu: bool = false) -> void:
	fixture.open(from_menu)

func _close_select() -> void:
	fixture.close()

func _on_fixture_confirmed(h: String, a: String) -> void:
	fixture.confirm(h, a)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_sync_overlay_scale()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_press()


func back_press() -> void:
	var now := Time.get_ticks_msec()
	if not BackPress.allowed(back_stamp, now):
		return
	back_stamp = now
	BackPress.press(self)


func _input(event: InputEvent) -> void:
	input.handle(event)

func _click(p: Vector2) -> void:
	input.click(p)

func _toggle_mode() -> void:
	set_mode(Prefs.next_mode(mode))


func set_mode(next: String) -> void:
	view.set_mode(next)
	if menus != null:
		menus.save_mode(mode)

func _skip() -> void:
	playback.skip()


func _process(delta: float) -> void:
	view.sync_type_density()
	playback.tick(delta)

func _advance_ticks(n: int) -> void:
	playback.advance_ticks(n)

func _post_tick() -> void:
	playback.post_tick()


func play_goal_clip(pack: Dictionary, on_done := Callable()) -> void:
	if replay != null:
		replay.finish(false)
		replay = null
	replay = GoalReplay.open(self, pack, on_done)
	if replay == null and on_done.is_valid():
		on_done.call()


func open_live_replay(pack: Dictionary) -> bool:
	if pack.is_empty() or replay != null:
		return false
	replay = GoalReplay.open_live(self, pack)
	if replay == null:
		return false
	in_highlight = true
	fast_mode = false
	highlight_until = -1.0
	accumulator = 0.0
	return true

func _on_engine_event(e: Dictionary) -> void:
	playback.on_engine_event(e)


func _apply_camera(snap_zoom: bool) -> void:
	if camera != null:
		camera.apply(snap_zoom)
