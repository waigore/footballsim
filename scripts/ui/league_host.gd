class_name LeagueHost
extends RefCounted

## Owns the league layer for the play scene: the modal screen, the pause and
## chrome dance underneath it, and the hand-off of a watched fixture to the
## match viewer. The season itself lives in LeagueSeason; this class only shows
## it and starts matches.

const LAYER := 32
## Pointer travel that separates a click from a scroll drag.
const DRAG_SLOP := 8.0
const PAN_STEP := 60.0

var game = null
var layer: CanvasLayer = null
var screen: LeagueScreen = null
var season: LeagueSeason = null
var was_paused := false
var pressing := false
var dragged := false
var press_at := Vector2.ZERO
var last_at := Vector2.ZERO

func attach(host) -> void:
	game = host

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
	screen.closed.connect(_on_closed)
	screen.match_requested.connect(_on_match_requested)
	screen.season_opened.connect(_on_season_opened)
	layer.visible = false

## Open means "the layer is on screen": the hand-off to the match viewer hides
## the layer but keeps the screen around, and the scene must play during it.
func is_open() -> bool:
	return layer != null and layer.visible and screen != null and screen.is_open()

func sync(frame: Transform2D, scale: float, touch: bool) -> void:
	if layer == null:
		return
	layer.transform = frame
	screen.ui_scale = scale
	screen.touch = touch
	screen.queue_redraw()

# ------------------------------------------------------------------ open ---

func open_wizard() -> void:
	_activate()
	screen.open_wizard()

func open_load() -> void:
	_activate()
	screen.open_load()

func open_save(slug: String) -> void:
	_activate()
	screen._open_save(slug)

## Show a season that already exists (a resumed save, a dev/evidence pose).
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
	screen.ui_scale = game.hud_scale
	screen.touch = game.touch
	layer.transform = Transform2D.IDENTITY.scaled(Vector2(game.hud_scale, game.hud_scale))
	screen.visible = true
	screen.queue_redraw()

## Leaving the league always lands on the main menu it was opened from — never
## on a finished match's HUD.
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

## Single-match mode owns the cached seed: a friendly started while a league
## save is loaded unbinds the season so its stats cannot land in the save.
func detach_season() -> void:
	if season != null and season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.disconnect(_on_recorded)
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

## Hand the fixture to the viewer: the season already remembers it is waiting,
## so the result finds its way back through PLSimStats.
func _on_match_requested(home: String, away: String, _fixture_id: String) -> void:
	if layer != null:
		layer.visible = false
	game.home_id = home
	game.away_id = away
	game.seeded += randi_range(1, 9999)
	game.match_started = true
	game.new_match(game.seeded)
	game.paused = false
	if game.hud_layer != null:
		game.hud_layer.visible = true

## A watched match reached full time and the season recorded it: pause again and
## show the hub with the new clock.
func _on_recorded(_report: Dictionary) -> void:
	if screen == null:
		return
	game.paused = true
	if game.hud_layer != null:
		game.hud_layer.visible = false
	layer.visible = true
	screen.open_season(season)
	screen.refresh()

# ----------------------------------------------------------------- input ---

## The sheet does its own hit testing; this converts pointers to design space
## and forwards. Wheel notches, trackpad pans, a held drag and the keys all move
## the season body; a press that never travels commits as a click on release.
func handle_input(event: InputEvent, design_point: Vector2) -> bool:
	if not is_open():
		return false
	if event is InputEventMouseMotion:
		_pointer_motion(design_point)
	elif event is InputEventPanGesture:
		# macOS reports a two-finger scroll as a pan, never as wheel buttons.
		screen.scroll_by(event.delta.y * PAN_STEP)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		screen.scroll_by(-110.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		screen.scroll_by(110.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer_down(design_point)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer_up()
	elif event is InputEventKey and event.pressed and not event.echo:
		screen.key(event.keycode)
	else:
		return event is InputEventMouse
	return true

func _pointer_down(p: Vector2) -> void:
	pressing = true
	dragged = false
	press_at = p
	last_at = p
	screen.mouse = p

## Hover is free; holding the button turns the pointer into a scroll drag, and
## the travel since the last frame is charged to the body in one step.
func _pointer_motion(p: Vector2) -> void:
	screen.mouse = p
	if not pressing:
		if not game.touch:
			Input.set_default_cursor_shape(
				Input.CURSOR_POINTING_HAND if screen.button_at(p) != "" else Input.CURSOR_ARROW)
		return
	if not dragged:
		if p.distance_to(press_at) < DRAG_SLOP:
			return
		dragged = true
	screen.scroll_by(last_at.y - p.y)
	last_at = p

func _pointer_up() -> void:
	if not pressing:
		return
	pressing = false
	if dragged:
		return
	var id := screen.button_at(press_at)
	if id != "":
		screen.click(id)
