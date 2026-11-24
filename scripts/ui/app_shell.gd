class_name AppShell
extends Control

## The menu shell laid over the match scene: main menu, settings, quit confirm,
## menu music and the stills backdrop. The match underneath stays paused; the
## shell owns no sim state and talks to the scene through two signals.
##
## Screens are presentational RefCounted sheets (the same pattern as the HUD's
## ticker), so every rect and hit-test stays testable without a renderer.

signal start_requested
signal resume_requested
signal new_league_requested
signal load_league_requested
## The sheet on screen changed: the host re-stacks the shell so the quit
## confirmation draws over whatever raised it (#123).
signal screen_changed

const SCREEN_MENU := "menu"
const SCREEN_SETTINGS := "settings"
const SCREEN_CONFIRM := "confirm"
const SCREEN_NONE := ""

var screen := SCREEN_NONE
var prev_screen := SCREEN_NONE
var has_match := false
var volume: float = Prefs.DEFAULT_BGM
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
## Soft left-to-right scrim so the wordmark and doors always sit on dark pixels
## without a hard-edged panel over the still.
var scrim: GradientTexture2D = null

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
	music.set_volume(volume)
	for path in MenuScreen.STILL_PATHS:
		var tex = load(path)
		if tex != null:
			stills.append(tex)
	scrim = UiChrome.make_scrim()
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

# ------------------------------------------------------------------ state ---

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

## Leave the shell. `keep_music` covers the walk from the menu into fixture
## setup: the music belongs to the pre-match shell, not to the match.
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

func volume_percent() -> int:
	return int(round(volume * 100.0))

# ------------------------------------------------------------------ input ---

func button_at(p: Vector2) -> String:
	var vp := design_vp()
	if screen == SCREEN_MENU:
		return menu.button_at(p, vp)
	if screen == SCREEN_SETTINGS:
		return settings.button_at(p, vp)
	if screen == SCREEN_CONFIRM:
		return confirm.button_at(p, vp)
	return ""

func click(p: Vector2) -> bool:
	if screen == SCREEN_MENU:
		return _menu_click(p)
	if screen == SCREEN_SETTINGS:
		return _settings_click(p)
	if screen == SCREEN_CONFIRM:
		return _confirm_click(p)
	return false

func _menu_click(p: Vector2) -> bool:
	if menu != null:
		menu.has_match = has_match
	var id := menu.click(p, design_vp())
	if id == "start":
		close(true)
		start_requested.emit()
	elif id == "resume":
		close(false)
		resume_requested.emit()
	elif id == "new_league":
		close(true)
		new_league_requested.emit()
	elif id == "load_league":
		close(true)
		load_league_requested.emit()
	elif id == "settings":
		open_settings()
	elif id == "quit":
		open_quit_confirm()
	return true

func _settings_click(p: Vector2) -> bool:
	var id := settings.click(p, design_vp())
	if id == "back":
		back_to_menu()
	elif id == "minus":
		set_volume(volume - 0.1)
	elif id == "plus":
		set_volume(volume + 0.1)
	elif id == "track":
		var v := settings.value_at(p, design_vp())
		if v >= 0.0:
			set_volume(v)
	return true

func _confirm_click(p: Vector2) -> bool:
	var id := confirm.click(p, design_vp())
	if id == "confirm":
		get_tree().quit()
	elif id == "cancel":
		cancel_confirm()
	return true

func key(code: int) -> bool:
	if not active():
		return false
	if code == KEY_ESCAPE:
		if screen == SCREEN_SETTINGS:
			back_to_menu()
		elif screen == SCREEN_CONFIRM:
			cancel_confirm()
		else:
			open_quit_confirm()
		return true
	if screen == SCREEN_MENU:
		return _menu_key(code)
	if screen == SCREEN_SETTINGS:
		return _settings_key(code)
	return false

func _menu_key(code: int) -> bool:
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		close(true)
		start_requested.emit()
	elif code == KEY_N:
		close(true)
		new_league_requested.emit()
	elif code == KEY_L:
		close(true)
		load_league_requested.emit()
	elif code == KEY_S:
		open_settings()
	else:
		return false
	return true

func _settings_key(code: int) -> bool:
	if code == KEY_LEFT or code == KEY_A:
		set_volume(volume - 0.1)
	elif code == KEY_RIGHT or code == KEY_D:
		set_volume(volume + 0.1)
	else:
		return false
	return true

## Forward an input event in design space; returns true when the shell took it.
func handle_input(event: InputEvent, p: Vector2) -> bool:
	if not active():
		return false
	if event is InputEventMouseMotion:
		_paint_sheet_mouse(p)
		if screen == SCREEN_SETTINGS and settings.dragging:
			var v := settings.value_at(p, design_vp())
			if v >= 0.0:
				set_volume(v)
		if not touch:
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if button_at(p) != "" else Input.CURSOR_ARROW)
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if settings != null:
				settings.dragging = false
			return true
		_paint_sheet_mouse(p)
		return click(p)
	if event is InputEventKey and event.pressed and not event.echo:
		return key(event.keycode)
	return false

func _paint_sheet_mouse(p: Vector2) -> void:
	if menu != null:
		menu.mouse = p
	if settings != null:
		settings.mouse = p
	if confirm != null:
		confirm.mouse = p
	queue_redraw()

# ---------------------------------------------------------------- drawing ---

func _draw() -> void:
	if not active():
		return
	var vp := design_vp()
	var under := screen
	if screen == SCREEN_CONFIRM:
		under = prev_screen
	if under == SCREEN_MENU or under == SCREEN_SETTINGS:
		_draw_backdrop(vp)
		if under == SCREEN_MENU:
			menu.draw(self, vp, fonts, has_match, volume, touch)
		else:
			settings.draw(self, vp, fonts, volume, touch)
	elif screen == SCREEN_CONFIRM:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35))
	if screen == SCREEN_CONFIRM:
		confirm.draw(self, vp, fonts, "QUIT FOOTBALL SIM?", _confirm_body(), "QUIT", "CANCEL", touch)

## The prompt says what will actually be lost: a live match, or just the app.
func _confirm_body() -> String:
	if prev_screen == SCREEN_NONE:
		return "The match in progress will end and the game will close."
	return "The game will close."

func _draw_backdrop(vp: Vector2) -> void:
	if stills.is_empty():
		draw_rect(Rect2(Vector2.ZERO, vp), UiChrome.C_BG)
		return
	var cur := MenuScreen.current_still(motion)
	draw_texture_rect(stills[cur % stills.size()], MenuScreen.ken_rect(vp, cur, motion), false)
	var a := MenuScreen.fade_alpha(motion)
	if a > 0.001:
		var nxt := MenuScreen.next_still(motion)
		draw_texture_rect(stills[nxt % stills.size()], MenuScreen.ken_rect(vp, nxt, motion), false, Color(1, 1, 1, a))
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.008, 0.014, 0.018, 0.18))
	if scrim != null:
		draw_texture_rect(scrim, Rect2(Vector2.ZERO, vp), false)
