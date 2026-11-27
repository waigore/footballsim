class_name LeagueFieldFocus
extends RefCounted


const WIZARD := "wizard"
const SYSTEM := "system"
const INTEREST := "interest"


var kind := ""


static func kind_of(id: String) -> String:
	if id == "name":
		return WIZARD
	if id == "sys:name":
		return SYSTEM
	if id == "interest:search":
		return INTEREST
	return ""


static func press(screen, want: String) -> void:
	var rect: Rect2 = field_rect(screen, want)
	if rect.size.y <= 0.0:
		return
	screen.focus.take(want, rect, field_text(screen, want), float(screen.ui_scale))


static func field_text(screen, want: String) -> String:
	if want == WIZARD:
		return str(screen.wizard.get("name", ""))
	if want == SYSTEM:
		return str(screen.sys.get("name", ""))
	return str(screen.interest_query)


func take(want: String, rect: Rect2, text: String, scale: float = 1.0) -> void:
	if want == kind and SoftKeyboard.shown():
		return
	kind = want
	SoftKeyboard.show_field(text, SoftKeyboard.frame_of(rect, scale), LeagueTextField.MAX_CHARS)


func blur() -> void:
	if kind == "":
		return
	kind = ""
	SoftKeyboard.hide()


func owns(id: String) -> bool:
	return kind != "" and kind_of(id) == kind


func sync(screen) -> void:
	if kind == "":
		return
	if field_rect(screen, kind).size.y > 0.0:
		return
	blur()


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


static func caret(c: CanvasItem, rect: Rect2, value: String, font: Font, size: int, live: bool) -> void:
	if not live:
		return
	var x: float = rect.position.x + 12.0 + UiChrome.text_width(font, value, size)
	c.draw_rect(Rect2(minf(x, rect.end.x - 8.0), rect.position.y + 9.0, 2.0, rect.size.y - 18.0),
		UiChrome.C_GOLD)
