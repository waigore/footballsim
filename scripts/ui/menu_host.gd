class_name MenuHost
extends RefCounted


var game = null
var layer: CanvasLayer = null
var shell: AppShell = null

var league: LeagueHost = null


const SHEET_LAYER := 30
const CONFIRM_LAYER := 40

func attach(main_node) -> void:
	game = main_node
	layer = CanvasLayer.new()
	layer.layer = SHEET_LAYER
	main_node.add_child(layer)
	shell = AppShell.new()
	shell.name = "Shell"
	layer.add_child(shell)
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.start_requested.connect(_on_start)
	shell.resume_requested.connect(_on_resume)
	shell.new_league_requested.connect(_on_new_league)
	shell.load_league_requested.connect(_on_load_league)
	shell.screen_changed.connect(_restack)
	shell.hud_visibility_changed.connect(_on_hud_choice)
	shell.match_mode_changed.connect(_on_match_mode)
	shell.visible = false


	if game.hud != null:
		game.hud.on_hud_changed = _persist_hud
	restore_hud()
	restore_mode()
	league = LeagueHost.new()
	league.attach(main_node)
	league.build()


func restore_hud() -> void:
	if game != null and game.hud != null and shell != null:
		game.hud.set_hud_visible(Prefs.load_hud(shell.prefs_path), true)

func _on_hud_choice(on: bool) -> void:
	if game != null and game.hud != null:
		game.hud.set_hud_visible(on, true)


func restore_mode() -> void:
	if game != null and game.view != null and shell != null:
		game.view.set_mode(Prefs.load_mode(shell.prefs_path))


func _on_match_mode(mode: String) -> void:
	if game != null and game.view != null:
		game.view.set_mode(mode)


func save_mode(mode: String) -> void:
	if shell == null:
		return
	shell.match_mode = Prefs.normalize_mode(mode)
	Prefs.save_mode(shell.match_mode, shell.prefs_path)

func _persist_hud(on: bool) -> void:
	Prefs.save_hud(on, shell.prefs_path if shell != null else Prefs.PATH)


func _restack() -> void:
	if layer == null or shell == null:
		return
	layer.layer = CONFIRM_LAYER if shell.screen == AppShell.SCREEN_CONFIRM else SHEET_LAYER

func active() -> bool:
	return (shell != null and shell.active()) or league_active() or league_holding()

func league_active() -> bool:
	return league != null and league.is_open()


func league_holding() -> bool:
	return league != null and league.is_holding()

func open_league_menu() -> void:
	if league != null:
		league.open_wizard()

func open_menu() -> void:


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


func handle_input(event: InputEvent, screen_point: Vector2) -> bool:
	if not active():
		return false
	var design_point: Vector2 = screen_point / maxf(shell.ui_scale, 0.001)


	if shell != null and shell.screen == AppShell.SCREEN_CONFIRM:
		if event is InputEventMouse:
			shell.handle_input(event, design_point)
		elif event is InputEventKey:
			shell.handle_input(event, Vector2.ZERO)
		return true
	if league_active() or league_holding():
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
