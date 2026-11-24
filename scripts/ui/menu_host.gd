class_name MenuHost
extends RefCounted

## Owns the menu shell layer and the scene-side glue: show/hide the match
## chrome, keep the match paused, forward input while a sheet is up, and hand
## Start/Resume back to the scene. Kept out of main.gd so that file stays inside
## its P3 size ratchet.

var game = null
var layer: CanvasLayer = null
var shell: AppShell = null
## The god-mode league surface: New/Setup, Load and the season hub.
var league: LeagueHost = null

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
	shell.new_league_requested.connect(_on_new_league)
	shell.load_league_requested.connect(_on_load_league)
	shell.visible = false
	league = LeagueHost.new()
	league.attach(main_node)
	league.build()

func active() -> bool:
	return (shell != null and shell.active()) or league_active()

func league_active() -> bool:
	return league != null and league.is_open()

func open_league_menu() -> void:
	if league != null:
		league.open_wizard()

func open_menu() -> void:
	# MENU while a season fixture is being watched hands the season back: the
	# rest of the match plays out at max speed and is saved (#100).
	if league != null and league.watch != null and league.watch.leave():
		return
	if game.wiki_host != null and game.wiki_host.is_open():
		game.wiki_host.close()
	if league != null and league.is_open():
		league.close()
	game.paused = true
	game.select_open = false
	_hide_chrome()
	if shell != null:
		shell.open_menu(bool(game.match_started))

func open_settings() -> void:
	if game.wiki_host != null and game.wiki_host.is_open():
		game.wiki_host.close()
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

## Pose the shell for a cold start (or a dev/evidence run). A normal launch
## opens the menu; `--home/--away` still goes straight to the match.
func pose(dev) -> void:
	if dev.open_settings:
		open_settings()
	elif dev.open_menu or not bool(game.fixture_arg_given):
		open_menu()
	else:
		game.match_started = true
	if dev.open_fixture:
		open_menu()
		game.open_select(true)
	if dev.open_confirm and shell != null:
		shell.open_quit_confirm()

func sync(frame: Transform2D, scale: float, touch: bool) -> void:
	if shell == null:
		return
	if league != null:
		league.sync(frame, scale, touch)
	layer.transform = frame
	shell.ui_scale = scale
	shell.touch = touch
	shell.queue_redraw()

## Swallow every event while a sheet is up: nothing may reach the paused match.
## The scene reports pointer positions in window space; the shell reads its own
## design space, so the host divides by the chrome scale it handed the layer.
func handle_input(event: InputEvent, screen_point: Vector2) -> bool:
	if not active():
		return false
	var design_point: Vector2 = screen_point / maxf(shell.ui_scale, 0.001)
	if league_active():
		return league.handle_input(event, design_point)
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
	if league != null:
		league.detach_season()
	game.open_select(true)

func _on_new_league() -> void:
	if league != null:
		league.open_wizard()

func _on_load_league() -> void:
	if league != null:
		league.open_load()

func _on_resume() -> void:
	if game.hud_layer != null:
		game.hud_layer.visible = true
	game.paused = false
