class_name WikiChrome
extends RefCounted


const PANEL := Color(0.035, 0.055, 0.070, 0.97)
const PANEL_LIGHT := Color(0.075, 0.105, 0.125, 0.97)
const BORDER := Color(1, 1, 1, 0.085)
const TEXT := Color(0.92, 0.95, 0.96)
const DIM := Color(0.62, 0.71, 0.76)
const GOLD := Color(0.96, 0.78, 0.30)

static var _styles := {}

static func box(c: CanvasItem, col: Color, r: Rect2, radius: int = 10, bc: Color = BORDER, bw: int = 1) -> void:
	var key := "%s|%d|%s|%d" % [col.to_html(), radius, bc.to_html(), bw]
	var sb: StyleBoxFlat = _styles.get(key, null)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(radius)
		sb.border_color = bc
		sb.set_border_width_all(bw)
		_styles[key] = sb
	c.draw_style_box(sb, r)


static func text_size(size_px: int) -> int:
	return ChromeDensity.read_size(size_px)

static func label(c: CanvasItem, font: Font, pos: Vector2, s: String, size_px: int, color: Color = TEXT) -> void:
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size(size_px), color)

static func label_c(c: CanvasItem, font: Font, center_x: float, y: float, s: String, size_px: int, color: Color = TEXT) -> void:
	var px := text_size(size_px)
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	c.draw_string(font, Vector2(center_x - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

static func label_r(c: CanvasItem, font: Font, right_x: float, y: float, s: String, size_px: int, color: Color = TEXT) -> void:
	var px := text_size(size_px)
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	c.draw_string(font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


static func button(c: CanvasItem, font: Font, r: Rect2, text: String, hovered: bool) -> void:
	box(c, PANEL_LIGHT if hovered else PANEL, r, 8, Color(1, 1, 1, 0.14 if hovered else 0.07))
	label_c(c, font, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.66, text, 13, TEXT if hovered else DIM)


static func footer_hint(touch: bool, can_open: bool, can_scroll: bool) -> String:
	var parts: Array = []
	if can_open:
		parts.append("TAP A ROW TO OPEN" if touch else "CLICK A ROW TO OPEN")
	if not touch:
		parts.append("ESC BACK")
	if can_scroll:
		parts.append("DRAG TO SCROLL" if touch else "WHEEL, DRAG OR KEYS SCROLL")
	return "  ·  ".join(PackedStringArray(parts))
