class_name LeagueHost
extends RefCounted


const LAYER := 32

var game = null
var layer: CanvasLayer = null
var screen: LeagueScreen = null

var pointer: SheetPointer = null
var season: LeagueSeason = null

var watch: LeagueWatch = null


var result: LeagueResult = null

var briefing: Dictionary = {}
var was_paused := false

func attach(host) -> void:
	game = host
	watch = LeagueWatch.new(self)
	result = LeagueResult.new(self)

func build() -> void:
	if layer != null or game == null:
		return
	layer = CanvasLayer.new()
	layer.layer = LAYER
	game.add_child(layer)
	screen = LeagueScreen.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)


	if screen.body != null:
		screen.body.host = self
	screen.closed.connect(_on_closed)
	screen.match_requested.connect(_on_match_requested)
	screen.season_opened.connect(_on_season_opened)
	screen.club_requested.connect(_on_club_requested)
	screen.goal_highlight_requested.connect(_on_goal_highlight)
	screen.quit_requested.connect(_on_quit_requested)
	pointer = SheetPointer.new(screen)


	pointer.hold = screen.interest
	layer.visible = false


func is_open() -> bool:
	return layer != null and layer.visible and screen != null and screen.is_open()


func is_holding() -> bool:
	return result != null and result.holding

func sync(frame: Transform2D, scale: float, touch: bool) -> void:
	if layer == null:
		return
	layer.transform = frame
	screen.ui_scale = scale
	screen.touch = touch
	screen.queue_redraw()


func open_wizard() -> void:
	_activate()
	screen.open_wizard()

func open_load() -> void:
	_activate()
	screen.open_load()

func open_save(slug: String) -> void:
	_activate()
	screen.open_save(slug)


func show_season(season_in: LeagueSeason, podium: bool = false) -> void:
	_activate()
	screen.open_season(season_in, podium)

func close() -> void:
	if screen != null and screen.is_open():
		screen.close()

func _activate() -> void:
	if layer == null:
		build()
	if screen == null:
		return
	was_paused = bool(game.paused)
	game.paused = true
	game.select_open = false
	if game.menus != null:
		game.menus.close(true)
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if game.sel_layer != null:
		game.sel_layer.visible = false
	layer.visible = true
	screen.ui_scale = game.chrome_scale
	screen.touch = game.touch
	layer.transform = Transform2D.IDENTITY.scaled(Vector2(game.chrome_scale, game.chrome_scale))
	screen.visible = true
	screen.queue_redraw()


func _on_closed() -> void:
	if layer != null:
		layer.visible = false
	if screen != null and screen.season == null:
		season = null
	game.paused = true
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if game.menus != null:
		game.menus.open_menu()


func _on_club_requested(club_id: String) -> void:
	if game.wiki_host == null:
		return
	game.wiki_host.open_page_over_league(WikiModel.TEAM, club_id)


func cover_for_wiki(hidden: bool) -> void:
	if layer == null:
		return
	if hidden:


		if screen != null:
			screen.focus.blur()
		layer.visible = false
		return
	if screen == null:
		return
	game.paused = true
	layer.visible = true
	screen.queue_redraw()


func detach_season() -> void:
	if season != null and season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.disconnect(_on_recorded)
	if season != null:
		season.finishing = false
	if result != null:
		result.clear()
	if watch != null:
		watch.clear()
	if screen != null:
		screen.season = null
	season = null
	if LeagueSeason.active != null:
		LeagueSeason.active.close()

func _on_season_opened(opened: LeagueSeason) -> void:
	if season != null and season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.disconnect(_on_recorded)
	season = opened
	if season != null and not season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.connect(_on_recorded)


func _on_match_requested(home: String, away: String, fixture_id: String) -> void:
	briefing = {"home": home, "away": away, "fixture": fixture_id}
	var fx: Dictionary = season.record.fixtures.one(fixture_id) if season != null else {}

	MatchBilling.bind_scene(game, home, fx)
	if game.prematch != null:
		var req := PreMatchModel.build(home, away, fx, season)
		game.prematch.ask(req, Callable(self, "_kick_briefing"), Callable(self, "_back_from_briefing"))
		return
	_start_watch(home, away)


func _kick_briefing() -> void:
	_start_watch(str(briefing.get("home", "")), str(briefing.get("away", "")))


func _back_from_briefing() -> void:
	if season != null:
		season.cancel_watch()
	briefing = {}
	if layer != null:
		layer.visible = true
	if screen != null:
		screen.refresh()
	game.paused = true

func _start_watch(home: String, away: String) -> void:
	briefing = {}
	if layer != null:
		layer.visible = false

	if screen != null:
		screen.focus.blur()
	if result != null:
		result.clear()
	game.home_id = home
	game.away_id = away
	game.seeded += randi_range(1, 9999)
	game.match_started = true
	game.new_match(game.seeded)
	game.paused = false
	if game.hud_layer != null:
		game.hud_layer.visible = true


func _on_quit_requested() -> void:
	if game != null and game.menus != null:
		game.menus.ask_quit()


func _on_recorded(report: Dictionary) -> void:
	if screen == null:
		return
	if result.take(report):
		return
	result.reveal()


func handle_input(event: InputEvent, design_point: Vector2) -> bool:
	if is_holding():
		return result.input(event)
	if not is_open() or pointer == null:
		return false
	if pointer.handle(event, design_point):
		return true
	return event is InputEventMouse


func _on_goal_highlight(fixture_id: String, goal_index: int) -> void:
	if season == null or fixture_id == "":
		return
	var pack := season.goal_clip(fixture_id, goal_index)
	if pack.is_empty():
		return
	if layer != null:
		layer.visible = false
	if game.hud_layer != null:
		game.hud_layer.visible = true
	game.play_goal_clip(pack, _on_goal_clip_done)

func _on_goal_clip_done() -> void:
	if game == null or screen == null:
		return
	game.paused = true
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if layer != null:
		layer.visible = true
	screen.refresh()
