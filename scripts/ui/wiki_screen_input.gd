class_name WikiScreenInput
extends RefCounted


var screen = null


func _init(host: Control) -> void:
	screen = host


func button_at(p: Vector2) -> String:
	for b in screen.buttons:
		if (b["rect"] as Rect2).has_point(p):
			return str(b["id"])
	return ""


func scroll_by(delta: float, _dx: float = 0.0) -> void:
	if screen.body != null:
		screen.body.scroll_by(delta)


func scroll_page(direction: float) -> void:
	if screen.body != null:
		screen.body.scroll_by(direction * screen.body.size.y * 0.9)


func scroll_to(at: float) -> void:
	if screen.body != null:
		screen.body.scroll_to(at)


func click(id: String) -> void:
	if screen.interest.click(id):
		return
	if id == "back":
		screen.back()
	elif id == "close":
		screen.close()
	elif id.begins_with("crumb:"):
		screen.nav.truncate_to(int(id.substr(6)))
		screen._refresh()
	elif id.begins_with("interest:"):
		screen.interest_toggled.emit(id.substr(9))
	elif id.begins_with("page:"):
		var rest := id.substr(5)
		var cut := rest.find(":")
		if cut < 0:
			return
		screen.push(rest.substr(0, cut), rest.substr(cut + 1))


func tap(p: Vector2) -> bool:
	if screen.body == null:
		return false
	var target: Dictionary = screen.body.hit(p)
	if target.is_empty():
		return false
	screen.push(str(target.get("page", "")), str(target.get("id", "")))
	return true


func key(code: int) -> bool:
	if screen.interest.is_open() and (code == KEY_ESCAPE or code == KEY_BACKSPACE):
		screen.interest.close()
		screen.queue_redraw()
		return true
	if code == KEY_ESCAPE or code == KEY_BACKSPACE or code == KEY_LEFT:
		screen.back()
	elif code == KEY_UP or code == KEY_W:
		scroll_by(-120.0)
	elif code == KEY_DOWN or code == KEY_S:
		scroll_by(120.0)
	elif code == KEY_PAGEUP:
		scroll_page(-1.0)
	elif code == KEY_PAGEDOWN:
		scroll_page(1.0)
	elif code == KEY_HOME:
		scroll_to(0.0)
	elif code == KEY_END:
		scroll_to(INF)
	else:
		return false
	return true
