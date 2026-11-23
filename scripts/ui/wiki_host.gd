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
var from_select := false
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
	layer.visible = false

func is_open() -> bool:
	return screen != null and screen.is_open()

## Open a page over the broadcast, or over the fixture picker when that is what
## the player is looking at. Either way the surface underneath comes back.
func open_page(page: String, id: String) -> void:
	if layer == null:
		build()
	from_select = bool(game.select_open)
	was_paused = bool(game.paused)
	game.paused = true
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if from_select and game.sel_layer != null:
		game.sel_layer.visible = false
	layer.visible = true
	screen.mouse = Vector2(-1000, -1000)
	screen.touch = game.touch
	screen.ui_scale = game.hud_scale
	layer.transform = Transform2D.IDENTITY.scaled(Vector2(game.hud_scale, game.hud_scale))
	screen.visible = true
	screen.open(page, id)

## Ask the sheet to close; it emits `closed` and the surface comes back.
func close() -> void:
	if screen != null:
		screen.close()

func _on_screen_closed() -> void:
	if layer != null:
		layer.visible = false
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
	layer.transform = Transform2D.IDENTITY.scaled(Vector2(game.hud_scale, game.hud_scale))
	screen.ui_scale = game.hud_scale
	screen.touch = game.touch

## The sheet does its own hit testing; this only converts pointers to design
## space and forwards. Touch drags scroll, the wheel scrolls, keys walk back.
func handle_input(event: InputEvent) -> void:
	if screen == null:
		return
	if event is InputEventMouseMotion:
		screen.mouse = event.position / maxf(game.hud_scale, 0.001)
		if game.touch and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			screen.wheel(-event.relative.y / maxf(game.hud_scale, 0.001))
		elif not game.touch:
			var over: bool = screen.button_at(screen.mouse) != ""
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)
	elif event is InputEventMouseButton and event.pressed:
		var p: Vector2 = event.position / maxf(game.hud_scale, 0.001)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			screen.wheel(-110.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			screen.wheel(110.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var id: String = screen.button_at(p)
			if id != "":
				screen.click(id)
			else:
				screen.tap(p)
	elif event is InputEventKey and event.pressed and not event.echo:
		screen.key(event.keycode)
