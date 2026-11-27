class_name UiChrome
extends RefCounted


const C_BG := Color(0.012, 0.020, 0.026)
const C_PANEL := Color(0.035, 0.055, 0.070, 0.96)
const C_PANEL_LIGHT := Color(0.075, 0.105, 0.125, 0.96)
const C_BORDER := Color(1, 1, 1, 0.085)
const C_TEXT := Color(0.92, 0.95, 0.96)
const C_DIM := Color(0.55, 0.64, 0.69)

const C_SOFT := Color(0.66, 0.73, 0.77)
const C_GOLD := Color(0.96, 0.78, 0.30)
const C_LIVE := Color(0.62, 0.88, 0.66)

const C_DANGER := Color(0.78, 0.26, 0.22)


const PRODUCT := "FOOTBALL"
const PRODUCT_TAIL := "SIM"
const PRODUCT_FULL := "Football Sim"


const RISE := 5.0

const HINT_DROP := 14.0


static func button(c: CanvasItem, cache: Dictionary, r: Rect2, label: String, font: Font,
		primary: bool, size: int = -1, hint: String = "", enabled: bool = true) -> void:
	var px: int = size if size > 0 else (15 if primary else 12)
	var cx: float = r.get_center().x
	var middle: float = r.position.y + r.size.y * 0.5


	var mid: float = middle - RISE if hint != "" else middle + RISE
	var ink: Color = Color(0.06, 0.06, 0.05) if primary else C_TEXT
	if not enabled:
		panel(c, cache, r, C_PANEL, 7, C_BORDER, 1)
		text_c(c, cx, mid, label, px, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.55), font)
		return
	if primary:
		panel(c, cache, r, C_GOLD, 7, Color(0.96, 0.78, 0.30, 0.85), 1)
	else:
		panel(c, cache, r, C_PANEL_LIGHT, 7)
	text_c(c, cx, mid, label, px, ink, font)
	if hint != "":
		var hint_ink: Color = Color(0.06, 0.06, 0.05, 0.65) if primary else C_DIM
		text_c(c, cx, middle + HINT_DROP, hint, 10, hint_ink, font)


static func chip(c: CanvasItem, cache: Dictionary, r: Rect2, label: String, font: Font) -> void:
	panel(c, cache, r, C_PANEL_LIGHT, 5)
	text_c(c, r.get_center().x, r.position.y + r.size.y * 0.5 + RISE, label, 13, C_TEXT, font)

static func fonts() -> Dictionary:
	return {
		"bold": load("res://fonts/BarlowCondensed-SemiBold.ttf"),
		"med": load("res://fonts/BarlowCondensed-Medium.ttf"),
		"body": load("res://fonts/Inter-Regular.ttf"),
	}

static func style(cache: Dictionary, fill: Color, radius: int = 10, border: Color = C_BORDER, width: int = 1) -> StyleBoxFlat:
	var key := "%s|%d|%s|%d" % [fill.to_html(true), radius, border.to_html(true), width]
	if cache.has(key):
		return cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(width)
	cache[key] = sb
	return sb

static func panel(c: CanvasItem, cache: Dictionary, r: Rect2, fill: Color, radius: int = 10, border: Color = C_BORDER, width: int = 1) -> void:
	c.draw_style_box(style(cache, fill, radius, border, width), r)

static func text(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color = C_TEXT, font: Font = null, outline: int = 0, outline_col: Color = Color(0, 0, 0, 0.5)) -> void:
	var f: Font = font if font != null else fonts()["med"]
	var px := ChromeDensity.read_size(size)
	if outline > 0:
		c.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, outline, outline_col)
	c.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


static func text_width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, ChromeDensity.read_size(size)).x

static func text_c(c: CanvasItem, center_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else fonts()["med"]
	var w: float = text_width(f, s, size)
	text(c, Vector2(center_x - w * 0.5, y), s, size, color, f)

static func text_r(c: CanvasItem, right_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else fonts()["med"]
	var w: float = text_width(f, s, size)
	text(c, Vector2(right_x - w, y), s, size, color, f)


static func wordmark(c: CanvasItem, pos: Vector2, size: int, font: Font) -> float:
	var head: String = PRODUCT
	var tail: String = PRODUCT_TAIL
	var hw: float = font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var gap: float = size * 0.22
	text(c, pos, head, size, C_TEXT, font)
	text(c, Vector2(pos.x + hw + gap, pos.y), tail, size, C_GOLD, font)
	return hw + gap + font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func make_scrim() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.008, 0.014, 0.018, 0.94))
	grad.set_color(1, Color(0.008, 0.014, 0.018, 0.10))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 1
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex

static func wordmark_width(size: int, font: Font) -> float:
	var hw: float = font.get_string_size(PRODUCT, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var gap: float = size * 0.22
	return hw + gap + font.get_string_size(PRODUCT_TAIL, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

static func wordmark_c(c: CanvasItem, center_x: float, y: float, size: int, font: Font) -> void:
	wordmark(c, Vector2(center_x - wordmark_width(size, font) * 0.5, y), size, font)


static func rule(c: CanvasItem, center_x: float, y: float, w: float = 64.0, col: Color = C_GOLD) -> void:
	c.draw_rect(Rect2(center_x - w * 0.5, y, w, 3.0), col)


static func sheet_header(c: CanvasItem, vp: Vector2, fonts: Dictionary, title: String,
		caption: String = "") -> void:
	var bold: Font = fonts["bold"]


	if caption != "":
		text_r(c, vp.x - 24.0, 40.0, caption, 11, C_DIM, bold)
	if vp.y < 620.0:
		rule(c, vp.x * 0.5, vp.y * 0.135, 48.0)
		text_c(c, vp.x * 0.5, vp.y * 0.195, title, 30, C_TEXT, bold)
	else:
		rule(c, vp.x * 0.5, vp.y * 0.185, 54.0)
		text_c(c, vp.x * 0.5, vp.y * 0.235, title, 38, C_TEXT, bold)
