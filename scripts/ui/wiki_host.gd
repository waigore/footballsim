class_name WikiHost
extends RefCounted

## Owns the encyclopedia layer for the play scene: building the sheet, pausing
## the broadcast (or the fixture picker) underneath it, restoring whichever was
## showing on the way out, and forwarding pointer/key input in design space.
## main.gd only has to say "open this page".

const LAYER := 30

var game = null
var screen = null
var layer: CanvasLayer = null
## The drag/wheel/click grammar the sheet shares with the league surface.
var pointer: SheetPointer = null
var from_select := false
## The encyclopedia was opened from inside a league season: closing it puts the
## season sheet back exactly where it was, not the match chrome.
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
	pointer = SheetPointer.new(screen)
	layer.visible = false

func is_open() -> bool:
	return screen != null and screen.is_open()

## Open a page over the broadcast, or over the fixture picker when that is what
## the player is looking at. Either way the surface underneath comes back.
func open_page(page: String, id: String) -> void:
	_open(page, id, bool(game.select_open), false)

## A league season opened the page: closing it hands the season sheet back
## instead of the match chrome, so a club row is a look-up, not an exit.
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

## Ask the sheet to close; it emits `closed` and the surface comes back.
func close() -> void:
	if screen != null:
		screen.close()

func _on_screen_closed() -> void:
	if layer != null:
		layer.visible = false
	if from_league:
		# The season never left: paint it again under the pointer, paused.
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

## The sheet does its own hit testing; this only converts pointers to design
## space and hands them to the shared grammar. Wheel notches, macOS trackpad pan
## gestures, drags and keys all move the body; a press that never travels commits
## as a click or a tap on release.
func handle_input(event: InputEvent) -> void:
	if screen == null or pointer == null:
		return
	# Only a pointer event carries a window position; keys and pan gestures do
	# not need one, and reading `position` off a key would be a runtime error.
	var point: Vector2 = _point(event) if event is InputEventMouse else Vector2.ZERO
	pointer.handle(event, point)

## A fresh page starts with no pointer history: a press belongs to the sheet that
## was on screen when it happened.
func reset_pointer() -> void:
	if pointer != null:
		pointer.reset()

func _point(event: InputEvent) -> Vector2:
	return event.position / maxf(game.chrome_scale, 0.001)
