class_name LeagueDelete
extends RefCounted


const NAME_MAX := 28

var slug := ""
var name := ""
var _painter := ConfirmPrompt.new()

func is_open() -> bool:
	return slug != ""


func ask_from(saves: Array, target: String) -> void:
	var label := target
	for row in saves:
		if str(row.get("slug", "")) == target:
			label = str(row.get("name", target))
			break
	slug = target
	name = label

func clear() -> void:
	slug = ""
	name = ""


func answer(screen) -> void:
	var target := slug
	clear()
	if target != "":
		LeagueDoors.delete_save(screen, target)
	else:
		screen.refresh()


func cancel(screen) -> void:
	clear()
	screen.refresh()


func hit(p: Vector2, vp: Vector2) -> String:
	match _painter.button_at(p, vp):
		"confirm":
			return "delete_yes"
		"cancel":
			return "delete_no"
	return ""


func paint(c: CanvasItem, vp: Vector2, fonts: Dictionary, mouse: Vector2, touch: bool) -> void:
	_painter.mouse = mouse
	var label := name
	if label.length() > NAME_MAX:
		label = label.substr(0, NAME_MAX - 3) + "..."
# gd-tools: no cover start
	_painter.draw(c, vp, fonts, "DELETE SAVE?", "%s is deleted for good." % label,
		"DELETE", "CANCEL", touch)
# gd-tools: no cover end
