class_name LeagueScreenInput
extends RefCounted

## League sheet hit-testing, scroll, clicks and keys. The Control keeps the
## state; this module owns the branching so `LeagueScreen` stays inside its
## P3 size and method budget.

var screen = null

func _init(host: Control) -> void:
	screen = host

## True while the load list is waiting for a delete confirmation. Everything
## behind the dialog is frozen until it is answered.
func delete_confirm_open() -> bool:
	return screen.mode == LeagueScreen.MODE_LOAD and screen.delete.is_open()

## Hit test walks back to front so later items (e.g. a delete chip) win. The
## layer stack above the body answers first: the delete question is the only
## surface while it is up, and an open menu is in front of everything else
## (#107); the body it covers is frozen and answers nothing.
func button_at(p: Vector2) -> String:
	if delete_confirm_open():
		return screen.delete.hit(p, screen.design_vp())
	if screen.interest.is_open():
		return screen.interest.menu.hit(p, screen.design_vp())
	var over_panel: String = screen.panel.hit(p, screen.design_vp())
	if over_panel != "":
		return over_panel
	return screen.body.hit(p) if screen.body != null else ""

## Wheel, trackpad, drag and keys; wide tables also pan sideways. The sheet is
## frozen while the menu is up, so a press under it never scrolls the page.
func scroll_by(delta: float, dx: float = 0.0) -> void:
	if delete_confirm_open():
		return
	if screen.interest.is_open():
		return
	if screen.body != null:
		screen.body.pan_by(Vector2(dx, delta))

## True when the report on screen carries a stored clip for a goal ordinal.
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
	# The delete confirmation is modal: Enter answers it, Esc/Backspace put it
	# away, and every other key belongs to the dialog (nothing behind reacts).
	if delete_confirm_open():
		match code:
			KEY_ENTER, KEY_KP_ENTER:
				screen.delete.answer(screen)
			KEY_ESCAPE, KEY_BACKSPACE:
				screen.delete.cancel(screen)
		return true
	# ESC puts the menu away first: it is the top-most surface while it is up.
	if screen.interest.is_open() and (code == KEY_ESCAPE or code == KEY_BACKSPACE):
		screen.interest.close()
		screen.refresh()
		return true
	return LeagueDoors.key(screen, code)

## One character the platform typed, which is how a soft keyboard's own text
## arrives (#201). The sheet's text fields take it; everything else is ignored,
## so the shared pointer grammar can hand every key event here.
func text_key(code: int, unicode: int) -> bool:
	if delete_confirm_open() or screen.interest.is_open():
		return false
	return LeagueDoors.text_key(screen, code, unicode)
