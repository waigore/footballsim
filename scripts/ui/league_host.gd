class_name LeagueHost
extends RefCounted


const LAYER := 32

var game = null
var layer: CanvasLayer = null
var screen: LeagueScreen = null

var pointer: SheetPointer = null
var season: LeagueSeason = null
var bus: UiBus = null

var watch: LeagueWatch = null


var result: LeagueResult = null

var was_paused := false

func attach(host) -> void:
	game = host
	bus = UiBus.make()
	bus.data_changed.connect(_on_data_changed)
	watch = LeagueWatch.new(self)
	result = LeagueResult.new(self)

func build() -> void:
	if layer != null or game == null:
		return
	layer = CanvasLayer.new()
	layer.layer = LAYER
	game.add_child(layer)
	screen = LeagueScreen.new()
	screen.bus = bus
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)


	if screen.body != null:
		screen.body.host = self
	screen.closed.connect(_on_closed)
	screen.match_requested.connect(watch.on_match_requested)
	screen.season_opened.connect(_on_season_opened)
	screen.club_requested.connect(_on_club_requested)
	screen.goal_highlight_requested.connect(watch.on_goal_highlight)
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
	if bus != null:
		bus.unbind_season()
	if LeagueSeason.active != null:
		LeagueSeason.active.close()

func _on_season_opened(opened: LeagueSeason) -> void:
	if season != null and season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.disconnect(_on_recorded)
	season = opened
	if season != null and not season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.connect(_on_recorded)
	bus.bind_season(season)


func _on_data_changed(scope: String) -> void:
	if scope != "season" and scope != "match":
		return
	if layer == null or not layer.visible or screen == null:
		return
	if result != null and result.holding:
		return
	screen.on_season_changed()


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
