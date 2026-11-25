class_name LeagueDelete
extends RefCounted

## The load list's one confirmation: a named save leaves the disk only after
## DELETE (DR-20261125-06's dialog-over-the-sheet grammar). State and copy live
## here, so the season's press table stays a dispatcher and the overlay only
## paints what this object holds.

## Longest save name printed on the dialog's one body line before it is cut.
const NAME_MAX := 28

var slug := ""
var name := ""
var _painter := ConfirmPrompt.new()

func is_open() -> bool:
	return slug != ""

## The row that raised the question: its slug is the write key and its name is
## what the player reads back.
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

## DELETE: the one place the file goes. `LeagueDoors.delete_save` rebuilds the
## list and unloads the season when the file is the one open.
func answer(screen) -> void:
	var target := slug
	clear()
	if target != "":
		LeagueDoors.delete_save(screen, target)
	else:
		screen.refresh()

## CANCEL, Esc or BACK: the list is exactly as it was left.
func cancel(screen) -> void:
	clear()
	screen.refresh()

## A press inside the dialog: its two doors, or nothing. The sheet behind it
## never answers while the question is up.
func hit(p: Vector2, vp: Vector2) -> String:
	match _painter.button_at(p, vp):
		"confirm":
			return "delete_yes"
		"cancel":
			return "delete_no"
	return ""

## Paint the dialog over whatever sheet raised it. The body line never wraps,
## so a long name is shortened here rather than painted through the edge.
func paint(c: CanvasItem, vp: Vector2, fonts: Dictionary, mouse: Vector2, touch: bool) -> void:
	_painter.mouse = mouse
	var label := name
	if label.length() > NAME_MAX:
		label = label.substr(0, NAME_MAX - 3) + "..."
# gd-tools: no cover start
	_painter.draw(c, vp, fonts, "DELETE SAVE?", "%s is deleted for good." % label,
		"DELETE", "CANCEL", touch)
# gd-tools: no cover end
