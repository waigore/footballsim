class_name MenuHost
extends RefCounted

## Owns the menu shell layer and the scene-side glue: show/hide the match
## chrome, keep the match paused, forward input while a sheet is up, and hand
## Start/Resume back to the scene. Kept out of main.gd so that file stays inside
## its P3 size ratchet.

var game = null
var layer: CanvasLayer = null
var shell: AppShell = null

func attach(main_node) -> void:
	game = main_node
	layer = CanvasLayer.new()
	layer.layer = 30
	main_node.add_child(layer)
	shell = AppShell.new()
	shell.name = "Shell"
	layer.add_child(shell)
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.start_requested.connect(_on_start)
	shell.resume_requested.connect(_on_resume)
	shell.visible = false

func active() -> bool:
	return shell != null and shell.active()

func open_menu() -> void:
	game.paused = true
	game.select_open = false
	_hide_chrome()
	if shell != null:
		shell.open_menu(bool(game.match_started))

func open_settings() -> void:
	game.paused = true
	_hide_chrome()
	if shell != null:
		shell.open_settings()

func ask_quit() -> void:
	if shell != null:
		shell.open_quit_confirm()

func close(keep_music: bool = false) -> void:
	if shell != null:
		shell.close(keep_music)

func sync(frame: Transform2D, scale: float, touch: bool) -> void:
	if shell == null:
		return
	layer.transform = frame
	shell.ui_scale = scale
	shell.touch = touch
	shell.queue_redraw()

## Swallow every event while a sheet is up: nothing may reach the paused match.
func handle_input(event: InputEvent, design_point: Vector2) -> bool:
	if not active():
		return false
	if event is InputEventMouse:
		shell.handle_input(event, design_point)
	elif event is InputEventKey:
		shell.handle_input(event, Vector2.ZERO)
	return true

func _hide_chrome() -> void:
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if game.sel_layer != null:
		game.sel_layer.visible = false

func _on_start() -> void:
	game.open_select(true)

func _on_resume() -> void:
	if game.hud_layer != null:
		game.hud_layer.visible = true
	game.paused = false
