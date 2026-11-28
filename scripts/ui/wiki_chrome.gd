class_name WikiChrome
extends RefCounted


static var PANEL: Color = UiTheme.color(&"panel")
static var PANEL_LIGHT: Color = UiTheme.color(&"panel_light")
static var BORDER: Color = UiTheme.color(&"border")
static var TEXT: Color = UiTheme.color(&"text")
static var DIM: Color = UiTheme.color(&"soft")
static var GOLD: Color = UiTheme.color(&"gold")

static var _styles := {}


static func text_color(col: Color) -> Color:
	return TEXT if col.a < 0.0 else col

static func box(c: CanvasItem, col: Color, r: Rect2, radius: int = 10, bc: Color = Color(-1, -1, -1, -1), bw: int = 1) -> void:
	var edge: Color = BORDER if bc.a < 0.0 else bc
	var key := "%s|%d|%s|%d" % [col.to_html(), radius, edge.to_html(), bw]
	var sb: StyleBoxFlat = _styles.get(key, null)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(radius)
		sb.border_color = edge
		sb.set_border_width_all(bw)
		_styles[key] = sb
	c.draw_style_box(sb, r)


static func text_size(size_px: int) -> int:
	return ChromeDensity.read_size(size_px)

static func label(c: CanvasItem, font: Font, pos: Vector2, s: String, size_px: int, color: Color = Color(-1, -1, -1, -1)) -> void:
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size(size_px), text_color(color))

static func label_c(c: CanvasItem, font: Font, center_x: float, y: float, s: String, size_px: int, color: Color = Color(-1, -1, -1, -1)) -> void:
	var px := text_size(size_px)
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	c.draw_string(font, Vector2(center_x - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, text_color(color))

static func label_r(c: CanvasItem, font: Font, right_x: float, y: float, s: String, size_px: int, color: Color = Color(-1, -1, -1, -1)) -> void:
	var px := text_size(size_px)
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	c.draw_string(font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, text_color(color))


static func chip(c: CanvasItem, font: Font, r: Rect2, text: String, accent: Color,
		gold: bool, hovered: bool) -> void:
	c.draw_rect(r, Color(0.075, 0.105, 0.125, 0.95 if not hovered else 1.0), true)
	c.draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), accent)
	label(c, font, Vector2(r.position.x + 14.0, r.position.y + r.size.y * 0.5 + 5.0),
		text, 13, GOLD if gold else TEXT)


static func fit(font: Font, s: String, size_px: int, width: float) -> String:
	var px := text_size(size_px)
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= width:
		return s
	var kept := s
	while kept.length() > 1 and font.get_string_size(kept + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		kept = kept.substr(0, kept.length() - 1)
	return kept + "…"


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


static func theme() -> Theme:
	return UiTheme.theme()
