class_name AppShellInput
extends RefCounted


var shell = null

func _init(host: Control) -> void:
	shell = host


func button_at(p: Vector2) -> String:
	var vp: Vector2 = shell.design_vp()
	if shell.screen == AppShell.SCREEN_MENU:
		return shell.menu.button_at(p, vp)
	if shell.screen == AppShell.SCREEN_SETTINGS:
		return shell.settings.button_at(p, vp)
	if shell.screen == AppShell.SCREEN_CONFIRM:
		return shell.confirm.button_at(p, vp)
	return ""


func click(p: Vector2) -> bool:
	if shell.screen == AppShell.SCREEN_MENU:
		return menu_click(p)
	if shell.screen == AppShell.SCREEN_SETTINGS:
		return settings_click(p)
	if shell.screen == AppShell.SCREEN_CONFIRM:
		return confirm_click(p)
	return false

func menu_click(p: Vector2) -> bool:
	if shell.menu != null:
		shell.menu.has_match = shell.has_match
	var id: String = shell.menu.click(p, shell.design_vp())
	if id == "start":
		shell.close(true)
		shell.start_requested.emit()
	elif id == "resume":
		shell.close(false)
		shell.resume_requested.emit()
	elif id == "new_league":
		shell.close(true)
		shell.new_league_requested.emit()
	elif id == "load_league":
		shell.close(true)
		shell.load_league_requested.emit()
	elif id == "settings":
		shell.open_settings()
	elif id == "quit":
		shell.open_quit_confirm()
	return true

func settings_click(p: Vector2) -> bool:
	var id: String = shell.settings.click(p, shell.design_vp())
	if id == "back":
		shell.back_to_menu()
	elif id == "minus":
		shell.set_volume(shell.volume - 0.1)
	elif id == "plus":
		shell.set_volume(shell.volume + 0.1)
	elif id == "track":
		var v: float = shell.settings.value_at(p, shell.design_vp())
		if v >= 0.0:
			shell.set_volume(v)
	elif id == "hud":

		shell.hud_visible = not shell.hud_visible
		Prefs.save_hud(shell.hud_visible, shell.prefs_path)
		shell.hud_visibility_changed.emit(shell.hud_visible)
		shell.queue_redraw()
	elif id.begins_with("mode:"):
		shell.set_match_mode(id.substr(5))
	return true

func confirm_click(p: Vector2) -> bool:
	var id: String = shell.confirm.click(p, shell.design_vp())
	if id == "confirm":
		shell.get_tree().quit()
	elif id == "cancel":
		shell.cancel_confirm()
	return true


func key(code: int) -> bool:
	if not shell.active():
		return false
	if code == KEY_ESCAPE:
		if shell.screen == AppShell.SCREEN_SETTINGS:
			shell.back_to_menu()
		elif shell.screen == AppShell.SCREEN_CONFIRM:
			shell.cancel_confirm()
		else:
			shell.open_quit_confirm()
		return true
	if shell.screen == AppShell.SCREEN_MENU:
		return menu_key(code)
	if shell.screen == AppShell.SCREEN_SETTINGS:
		return settings_key(code)
	return false


func menu_key(code: int) -> bool:
	var want := ""
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		want = MenuScreen.primary_id(shell.has_match)
	elif code == KEY_T:
		want = "start"
	if want != "":
		for b in MenuScreen.door_rects(shell.design_vp(), shell.has_match):
			if str(b["id"]) == want:
				return menu_click((b["rect"] as Rect2).get_center())
		return false
	if code == KEY_N:
		shell.close(true)
		shell.new_league_requested.emit()
	elif code == KEY_L:
		shell.close(true)
		shell.load_league_requested.emit()
	elif code == KEY_S:
		shell.open_settings()
	else:
		return false
	return true

func settings_key(code: int) -> bool:
	if code == KEY_LEFT or code == KEY_A:
		shell.set_volume(shell.volume - 0.1)
	elif code == KEY_RIGHT or code == KEY_D:
		shell.set_volume(shell.volume + 0.1)
	elif code >= KEY_1 and code <= KEY_3:

		shell.set_match_mode(str(Prefs.MODES[code - KEY_1]))
	else:
		return false
	return true


func handle(event: InputEvent, p: Vector2) -> bool:
	if not shell.active():
		return false
	if event is InputEventMouseMotion:
		paint_sheet_mouse(p)
		if shell.screen == AppShell.SCREEN_SETTINGS and shell.settings.dragging:
			var v: float = shell.settings.value_at(p, shell.design_vp())
			if v >= 0.0:
				shell.set_volume(v)
		if not shell.touch:
			Input.set_default_cursor_shape(
				Input.CURSOR_POINTING_HAND if button_at(p) != "" else Input.CURSOR_ARROW)
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if shell.settings != null:
				shell.settings.dragging = false
			return true
		paint_sheet_mouse(p)
		return click(p)
	if event is InputEventKey and event.pressed and not event.echo:
		return key(event.keycode)
	return false

func paint_sheet_mouse(p: Vector2) -> void:
	if shell.menu != null:
		shell.menu.mouse = p
	if shell.settings != null:
		shell.settings.mouse = p
	if shell.confirm != null:
		shell.confirm.mouse = p
	shell.queue_redraw()
