class_name AppShell
extends Control


signal start_requested
signal resume_requested
signal new_league_requested
signal load_league_requested


signal screen_changed


signal hud_visibility_changed(hud_on: bool)


signal match_mode_changed(mode: String)

const SCREEN_MENU := "menu"
const SCREEN_SETTINGS := "settings"
const SCREEN_CONFIRM := "confirm"
const SCREEN_NONE := ""

var screen := SCREEN_NONE
var prev_screen := SCREEN_NONE
var has_match := false
var volume: float = Prefs.DEFAULT_BGM


var hud_visible: bool = Prefs.DEFAULT_HUD


var match_mode: String = Prefs.DEFAULT_MODE
var prefs_path: String = Prefs.PATH
var ui_scale := 1.0
var touch := false

var fonts: Dictionary = {}
var menu: MenuScreen = null
var settings: SettingsScreen = null
var confirm: ConfirmPrompt = null
var music: MenuMusic = null
var stills: Array = []
var motion := 0.0


var scrim: GradientTexture2D = null
var input: AppShellInput = null
var paint: AppShellPaint = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	fonts = UiChrome.fonts()
	menu = MenuScreen.new()
	settings = SettingsScreen.new()
	confirm = ConfirmPrompt.new()
	music = MenuMusic.new()
	add_child(music)
	volume = Prefs.load_bgm(prefs_path)
	hud_visible = Prefs.load_hud(prefs_path)
	match_mode = Prefs.load_mode(prefs_path)
	music.set_volume(volume)
	for path in MenuScreen.STILL_PATHS:
		var tex = load(path)
		if tex != null:
			stills.append(tex)
	scrim = UiChrome.make_scrim()
	input = AppShellInput.new(self)
	paint = AppShellPaint.new(self)
	visible = false

func _process(delta: float) -> void:
	if not active():
		return
	motion += delta
	queue_redraw()

func active() -> bool:
	return screen != SCREEN_NONE

func design_vp() -> Vector2:
	var vp: Vector2 = size / maxf(ui_scale, 0.001)
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)
	return vp


func open_menu(has_match_now: bool) -> void:
	has_match = has_match_now
	screen = SCREEN_MENU
	prev_screen = SCREEN_NONE
	volume = Prefs.load_bgm(prefs_path)
	if menu != null:
		menu.has_match = has_match_now
	if music != null:
		music.set_volume(volume)
		music.play_menu()
	visible = true
	queue_redraw()
	screen_changed.emit()

func open_settings() -> void:
	screen = SCREEN_SETTINGS
	prev_screen = SCREEN_NONE


	volume = Prefs.load_bgm(prefs_path)
	hud_visible = Prefs.load_hud(prefs_path)
	match_mode = Prefs.load_mode(prefs_path)
	if music != null:
		music.play_menu()
	visible = true
	queue_redraw()
	screen_changed.emit()

func open_quit_confirm() -> void:
	if screen == SCREEN_CONFIRM:
		return
	prev_screen = screen
	screen = SCREEN_CONFIRM
	visible = true
	queue_redraw()
	screen_changed.emit()

func back_to_menu() -> void:
	open_menu(has_match)


func close(keep_music: bool = false) -> void:
	screen = SCREEN_NONE
	prev_screen = SCREEN_NONE
	visible = false
	if music != null and not keep_music:
		music.stop()
	screen_changed.emit()

func cancel_confirm() -> void:
	if screen != SCREEN_CONFIRM:
		return
	prev_screen = SCREEN_NONE if prev_screen == SCREEN_CONFIRM else prev_screen
	if prev_screen == SCREEN_SETTINGS:
		screen = SCREEN_SETTINGS
		prev_screen = SCREEN_NONE
		visible = true
	elif prev_screen == SCREEN_MENU:
		open_menu(has_match)
	else:
		screen = SCREEN_NONE
		prev_screen = SCREEN_NONE
		visible = false
	queue_redraw()
	screen_changed.emit()

func set_volume(v: float) -> void:
	volume = Prefs.clamp_volume(v)
	Prefs.save_bgm(volume, prefs_path)
	if music != null:
		music.set_volume(volume)
	queue_redraw()


func set_match_mode(mode: String) -> void:
	var next := Prefs.normalize_mode(mode)
	if next == match_mode:
		return
	match_mode = next
	Prefs.save_mode(match_mode, prefs_path)
	match_mode_changed.emit(match_mode)
	queue_redraw()


func button_at(p: Vector2) -> String:
	return input.button_at(p) if input != null else ""

func click(p: Vector2) -> bool:
	return input.click(p) if input != null else false

func key(code: int) -> bool:
	return input.key(code) if input != null else false


func handle_input(event: InputEvent, p: Vector2) -> bool:
	return input.handle(event, p) if input != null else false


func _draw() -> void:
	if not active() or paint == null:
		return
	paint.draw(design_vp())
