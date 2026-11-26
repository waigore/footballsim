class_name LeagueFieldFocus
extends RefCounted

## Which of the season's painted text fields owns the on-screen keyboard (#201).
##
## The wizard's name, the System dialog's Save As name and the shortlist's search
## are painted strings on a sheet, not `LineEdit` nodes, so tapping one only moved
## focus inside the game — the platform never learned a field had focus and no
## keyboard appeared. A touch-only player could not rename a save at all, and the
## Save As field painted `Unknown action.` when it was pressed.
##
## This module owns the three moments a field needs: the tap that puts a field in
## front of the keyboard, the repaint that must not fight the IME, and the press,
## pose change or BACK that puts it away. The keyboard itself is asked for through
## `SoftKeyboard`, so no sheet branches on the platform (RUB-P3-05).
##
## Desktop typing is untouched: with no on-screen keyboard every call is a no-op
## and the sheet's own key grammar remains the only way text arrives.

const WIZARD := "wizard"
const SYSTEM := "system"
const INTEREST := "interest"

## The field the keyboard is open for, or "" when none is.
var kind := ""

## The field a door id belongs to, or "" when that id is not a text field.
static func kind_of(id: String) -> String:
	if id == "name":
		return WIZARD
	if id == "sys:name":
		return SYSTEM
	if id == "interest:search":
		return INTEREST
	return ""

## Put `want` in front of the keyboard and open it on the text the field already
## holds, so the player edits their own name rather than starting from an empty
## line. The box the keyboard points at is read from the pose's own layout, so it
## is the box the player pressed.
static func press(screen, want: String) -> void:
	var rect: Rect2 = field_rect(screen, want)
	if rect.size.y <= 0.0:
		return
	screen.focus.take(want, rect, field_text(screen, want), float(screen.ui_scale))

## What the field holds now, so the keyboard opens on it.
static func field_text(screen, want: String) -> String:
	if want == WIZARD:
		return str(screen.wizard.get("name", ""))
	if want == SYSTEM:
		return str(screen.sys.get("name", ""))
	return str(screen.interest_query)

## Put `want` in front of the keyboard and open it on the text the field holds.
## A repaint the field survives leaves the IME alone; a field pressed again after
## the player put the keyboard away themselves — Android's back key does that
## without telling the game — raises it again, because the platform is asked
## whether the keyboard is really up rather than trusting the last call.
func take(want: String, rect: Rect2, text: String, scale: float = 1.0) -> void:
	if want == kind and SoftKeyboard.shown():
		return
	kind = want
	SoftKeyboard.show_field(text, SoftKeyboard.frame_of(rect, scale), LeagueTextField.MAX_CHARS)

## Put the keyboard away. Called by BACK, by a press that is not the field, and
## by the pose leaving the field behind.
func blur() -> void:
	if kind == "":
		return
	kind = ""
	SoftKeyboard.hide()

## True when `id` is the door of the field that owns the keyboard.
func owns(id: String) -> bool:
	return kind != "" and kind_of(id) == kind

## Keep the keyboard in step with what is on screen. A repaint the field survives
## leaves the IME alone; a pose that no longer paints the field (the wizard left,
## Save As was committed, the shortlist closed) puts it away, so no keyboard is
## left standing over a sheet with no field on it.
func sync(screen) -> void:
	if kind == "":
		return
	if field_rect(screen, kind).size.y > 0.0:
		return
	blur()

## The rect the field paints at in the pose on screen, or an empty rect when this
## pose does not paint it.
static func field_rect(screen, want: String) -> Rect2:
	var vp: Vector2 = screen.design_vp()
	if want == WIZARD and str(screen.mode) == LeagueScreen.MODE_WIZARD:
		return _find(screen.start.wizard_layout(vp, screen.current_view()), "name")
	if want == SYSTEM and str(screen.mode) == LeagueScreen.MODE_SYSTEM:
		return _find(screen.system.layout(vp, screen.current_view()), "sys:name")
	if want == INTEREST and str(screen.mode) == LeagueScreen.MODE_INTEREST:
		return _find(screen.sheet_extra.interest_layout(vp, screen.current_view()), "interest:search")
	return Rect2()

static func _find(items: Array, id: String) -> Rect2:
	for item in items:
		if str(item.get("id", "")) == id:
			return item["rect"]
	return Rect2()

## The caret a field paints while it owns the keyboard: a gold hairline just
## past the last glyph. A field that is not being typed into keeps its plain
## reading, so a touch sheet says plainly which box the keyboard belongs to.
static func caret(c: CanvasItem, rect: Rect2, value: String, font: Font, size: int, live: bool) -> void:
	if not live:
		return
	var x: float = rect.position.x + 12.0 + UiChrome.text_width(font, value, size)
	c.draw_rect(Rect2(minf(x, rect.end.x - 8.0), rect.position.y + 9.0, 2.0, rect.size.y - 18.0),
		UiChrome.C_GOLD)
