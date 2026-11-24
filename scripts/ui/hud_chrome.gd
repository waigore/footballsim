class_name HudChrome
extends RefCounted

## Drawing surface shared by every broadcast-overlay band: cached style boxes,
## the three text alignments, and the door list the overlay turns into taps.
## Split out of hud.gd so each band is its own module (RUB-P3-01).

const BORDER := Color(1, 1, 1, 0.085)

## Every door the overlay drew this frame, in draw order.
var buttons: Array = []
var _panel_cache := {}

func _style(fill: Color, radius: int, border: Color, width: int) -> StyleBoxFlat:
	var key := "%s|%d|%s|%d" % [fill.to_html(), radius, border.to_html(), width]
	if _panel_cache.has(key):
		return _panel_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(width)
	_panel_cache[key] = sb
	return sb

func panel(c: CanvasItem, fill: Color, r: Rect2, radius: int = 10, border: Color = BORDER) -> void:
	c.draw_style_box(_style(fill, radius, border, 1), r)

func text(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color, font: Font, outline: int = 0, outline_col: Color = Color(0, 0, 0, 0.5)) -> void:
	if outline > 0:
		c.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_col)
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func text_c(c: CanvasItem, center_x: float, y: float, s: String, size: int, color: Color, font: Font) -> void:
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(c, Vector2(center_x - w * 0.5, y), s, size, color, font)

func text_r(c: CanvasItem, right_x: float, y: float, s: String, size: int, color: Color, font: Font) -> void:
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(c, Vector2(right_x - w, y), s, size, color, font)

func add_button(id: String, r: Rect2, label: String, hint: String) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "hint": hint})

## First door under a design-space point, or "" when the pointer is on the pitch.
func button_at(p: Vector2) -> String:
	for b in buttons:
		if (b["rect"] as Rect2).has_point(p):
			return b["id"]
	return ""
