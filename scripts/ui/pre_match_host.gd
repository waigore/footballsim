class_name PreMatchHost
extends RefCounted

## Owns the pre-match briefing layer and the hand-off either side of it (#157).
##
## Both ways into a watched match — a league Continue that reaches a Watch, and
## the fixture picker's KICK OFF — ask this host to show the briefing first. The
## host answers every press itself, and only a kick starts the sim; BACK hands
## control to the caller's own way out (the hub, or the picker) without starting.

const LAYER := 40

var game = null
var layer: CanvasLayer = null
var screen: PreMatchScreen = null
## What is on the briefing, kept for the caller's back door.
var request: Dictionary = {}
var on_kick := Callable()
var on_back := Callable()

## Create, attach and build the layer in one step: the scene keeps one field
## instead of three lines of wiring.
static func mount(host) -> PreMatchHost:
	var out := PreMatchHost.new()
	out.attach(host)
	out.build()
	return out

func attach(host) -> void:
	game = host

func build() -> void:
	if layer != null or game == null:
		return
	layer = CanvasLayer.new()
	layer.layer = LAYER
	game.add_child(layer)
	screen = PreMatchScreen.new()
	screen.name = "PreMatch"
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	screen.kick_off.connect(_on_kick)
	screen.cancelled.connect(_on_back)
	layer.visible = false

func is_open() -> bool:
	return layer != null and layer.visible and screen != null and screen.is_open()

## Show the briefing for `req` (a `PreMatchModel.build` dictionary). `kick` runs
## when the player starts the match; `back` when they leave without starting.
func ask(req: Dictionary, kick: Callable, back: Callable) -> void:
	if req.is_empty():
		if kick.is_valid():
			kick.call()
		return
	if layer == null:
		build()
	request = req
	on_kick = kick
	on_back = back
	if game != null:
		game.paused = true
	layer.visible = true
	screen.setup(req)
	screen.ui_scale = game.chrome_scale if game != null else 1.0
	screen.touch = bool(game.touch) if game != null else false
	screen.visible = true
	screen.queue_redraw()

func close() -> void:
	if layer != null:
		layer.visible = false
	if screen != null:
		screen.visible = false
		screen.view = {}
		screen.buttons = []
	on_kick = Callable()
	on_back = Callable()
	request = {}

func _on_kick() -> void:
	var go := on_kick
	close()
	if go.is_valid():
		go.call()

func _on_back() -> void:
	var back := on_back
	close()
	if back.is_valid():
		back.call()

func sync(frame: Transform2D, scale: float, touch: bool) -> void:
	if layer == null or screen == null:
		return
	layer.transform = frame
	screen.ui_scale = scale
	screen.touch = touch
	screen.queue_redraw()

## Hover, taps and keys, all in design space. The briefing is modal: it answers
## every event while it is up.
func handle_input(event: InputEvent, design_point: Vector2) -> bool:
	if not is_open():
		return false
	if event is InputEventMouseMotion:
		screen.mouse = design_point
		if not screen.touch:
			Input.set_default_cursor_shape(
				Input.CURSOR_POINTING_HAND if screen.button_at(design_point) != "" else Input.CURSOR_ARROW)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var id: String = screen.button_at(design_point)
			if id != "":
				screen.click(id)
	elif event is InputEventKey and event.pressed and not event.echo:
		screen.key(event.keycode)
	return true
