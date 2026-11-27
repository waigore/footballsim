class_name WikiHost
extends RefCounted


const LAYER := 30

var game = null
var screen = null
var layer: CanvasLayer = null

var pointer: SheetPointer = null
var from_select := false


var from_league := false
var was_paused := false

func _init(host) -> void:
	game = host

func build() -> void:
	if layer != null or game == null:
		return
	layer = CanvasLayer.new()
	layer.layer = LAYER
	game.add_child(layer)
	screen = Control.new()
	screen.set_script(load("res://scripts/ui/wiki_screen.gd"))
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	screen.closed.connect(_on_screen_closed)
	screen.interest_toggled.connect(_on_interest_toggled)
	pointer = SheetPointer.new(screen)

	pointer.hold = screen.interest
	layer.visible = false

func is_open() -> bool:
	return screen != null and screen.is_open()


func open_page(page: String, id: String) -> void:
	_open(page, id, bool(game.select_open), false)


func open_page_over_league(page: String, id: String) -> void:
	_open(page, id, false, true)

func _open(page: String, id: String, over_select: bool, over_league: bool) -> void:
	if layer == null:
		build()
	reset_pointer()
	from_select = over_select
	from_league = over_league
	was_paused = bool(game.paused)
	game.paused = true
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if from_select and game.sel_layer != null:
		game.sel_layer.visible = false
	if from_league and game.menus != null and game.menus.league != null:
		game.menus.league.cover_for_wiki(true)
	layer.visible = true
	screen.mouse = Vector2(-1000, -1000)
	screen.touch = game.touch
	screen.ui_scale = game.chrome_scale
	layer.transform = Transform2D.IDENTITY.scaled(Vector2(game.chrome_scale, game.chrome_scale))
	screen.visible = true
	screen.open(page, id)


func _on_interest_toggled(club_id: String) -> void:
	var season = LeagueSeason.active
	if season == null or club_id == "":
		return
	season.set_interest(club_id, not season.record.interest.is_interested(club_id))
	if screen != null:
		screen.queue_redraw()


func close() -> void:
	if screen != null:
		screen.close()

func _on_screen_closed() -> void:
	if layer != null:
		layer.visible = false
	if from_league:

		from_league = false
		from_select = false
		if game.menus != null and game.menus.league != null:
			game.menus.league.cover_for_wiki(false)
		return
	if from_select:
		if game.sel_layer != null:
			game.sel_layer.visible = true
			if game.selector != null:
				game.selector.visible = true
		game.paused = true
	else:
		if game.hud_layer != null:
			game.hud_layer.visible = true
		game.paused = was_paused
	from_select = false

func sync_scale() -> void:
	if layer == null:
		return
	layer.transform = Transform2D.IDENTITY.scaled(Vector2(game.chrome_scale, game.chrome_scale))
	screen.ui_scale = game.chrome_scale
	screen.touch = game.touch


func handle_input(event: InputEvent) -> void:
	if screen == null or pointer == null:
		return


	var point: Vector2 = _point(event) if event is InputEventMouse else Vector2.ZERO
	pointer.handle(event, point)


func reset_pointer() -> void:
	if pointer != null:
		pointer.reset()

func _point(event: InputEvent) -> Vector2:
	return event.position / maxf(game.chrome_scale, 0.001)
