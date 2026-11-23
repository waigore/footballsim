class_name ConfirmPrompt
extends RefCounted

## Small modal yes/no used before quitting. Drawn over whatever sheet was
## underneath; the game underneath stays paused, so no motion races input.

var mouse := Vector2(-1000, -1000)
var _cache := {}

static func dialog_rect(vp: Vector2) -> Rect2:
	var w: float = minf(480.0, vp.x - 48.0)
	var h: float = 188.0
	return Rect2(vp.x * 0.5 - w * 0.5, vp.y * 0.5 - h * 0.5, w, h)

static func confirm_rect(vp: Vector2) -> Rect2:
	var d := dialog_rect(vp)
	var w: float = (d.size.x - 60.0) * 0.5
	return Rect2(d.position.x + 24.0, d.end.y - 68.0, w, 44.0)

static func cancel_rect(vp: Vector2) -> Rect2:
	var d := dialog_rect(vp)
	var w: float = (d.size.x - 60.0) * 0.5
	return Rect2(d.end.x - 24.0 - w, d.end.y - 68.0, w, 44.0)

func button_at(p: Vector2, vp: Vector2 = Vector2(1600, 900)) -> String:
	if confirm_rect(vp).has_point(p):
		return "confirm"
	if cancel_rect(vp).has_point(p):
		return "cancel"
	return ""

func click(p: Vector2, vp: Vector2 = Vector2(1600, 900)) -> String:
	return button_at(p, vp)

func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary, title: String, body: String, ok_label: String, no_label: String, touch: bool = false) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
	var d := dialog_rect(vp)
	UiChrome.panel(c, _cache, d, Color(0.025, 0.038, 0.048, 0.985), 14, Color(1, 1, 1, 0.14))
	c.draw_rect(Rect2(d.position.x + 1.0, d.position.y + 1.0, d.size.x - 2.0, 3.0), UiChrome.C_GOLD)
	UiChrome.text_c(c, d.position.x + d.size.x * 0.5, d.position.y + 48.0, title, 26, UiChrome.C_TEXT, bold)
	UiChrome.text_c(c, d.position.x + d.size.x * 0.5, d.position.y + 78.0, body, 11, UiChrome.C_SOFT, med)
	var ok := confirm_rect(vp)
	var no := cancel_rect(vp)
	var ok_hover := ok.has_point(mouse)
	UiChrome.panel(c, _cache, ok, UiChrome.C_DANGER.darkened(0.08 if ok_hover else 0.0), 8, Color(0.95, 0.45, 0.40, 0.75))
	UiChrome.text_c(c, ok.position.x + ok.size.x * 0.5, ok.position.y + 29.0, ok_label, 15, Color(1, 1, 1), bold)
	UiChrome.panel(c, _cache, no, UiChrome.C_PANEL_LIGHT if no.has_point(mouse) else UiChrome.C_PANEL, 8, Color(1, 1, 1, 0.10))
	UiChrome.text_c(c, no.position.x + no.size.x * 0.5, no.position.y + 29.0, no_label, 15, UiChrome.C_TEXT, bold)
	if touch:
		UiChrome.text_c(c, vp.x * 0.5, d.end.y - 10.0, "TAP CANCEL TO STAY", 10, UiChrome.C_SOFT, med)
	else:
		UiChrome.text_c(c, no.position.x + no.size.x * 0.5, d.end.y - 10.0, "ESC", 10, UiChrome.C_SOFT, med)
