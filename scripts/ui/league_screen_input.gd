class_name LeagueScreenInput
extends RefCounted


var screen = null

func _init(host: Control) -> void:
	screen = host


func delete_confirm_open() -> bool:
	return screen.mode == LeagueScreen.MODE_LOAD and screen.delete.is_open()


func button_at(p: Vector2) -> String:
	if delete_confirm_open():
		return screen.delete.hit(p, screen.design_vp())
	if screen.interest.is_open():
		return screen.interest.menu.hit(p, screen.design_vp())
	var over_panel: String = screen.panel.hit(p, screen.design_vp())
	if over_panel != "":
		return over_panel
	return screen.body.hit(p) if screen.body != null else ""


func scroll_by(delta: float, dx: float = 0.0) -> void:
	if delete_confirm_open():
		return
	if screen.interest.is_open():
		return
	if screen.body != null:
		screen.body.pan_by(Vector2(dx, delta))


func has_clip(index: int) -> bool:
	return LeagueGoalDoors.has_clip(screen, index)

func click(id: String) -> void:
	if delete_confirm_open():
		LeagueDoors.press(screen, id)
		return
	if screen.interest.click(id):
		return
	LeagueDoors.press(screen, id)

func key(code: int) -> bool:


	if delete_confirm_open():
		match code:
			KEY_ENTER, KEY_KP_ENTER:
				screen.delete.answer(screen)
			KEY_ESCAPE, KEY_BACKSPACE:
				screen.delete.cancel(screen)
		return true

	if screen.interest.is_open() and (code == KEY_ESCAPE or code == KEY_BACKSPACE):
		screen.interest.close()
		screen.refresh()
		return true
	return LeagueDoors.key(screen, code)


func text_key(code: int, unicode: int) -> bool:
	if delete_confirm_open() or screen.interest.is_open():
		return false
	return LeagueDoors.text_key(screen, code, unicode)
