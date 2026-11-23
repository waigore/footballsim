class_name UiChrome
extends RefCounted

## One modern sports-broadcast language for every screen: the main menu,
## settings, fixture picker and match HUD read these palette values, fonts and
## drawing helpers instead of each carrying a private copy.
##
## This module is presentational only: no input, no state, no platform calls.

const C_BG := Color(0.012, 0.020, 0.026)
const C_PANEL := Color(0.035, 0.055, 0.070, 0.96)
const C_PANEL_LIGHT := Color(0.075, 0.105, 0.125, 0.96)
const C_BORDER := Color(1, 1, 1, 0.085)
const C_TEXT := Color(0.92, 0.95, 0.96)
const C_DIM := Color(0.55, 0.64, 0.69)
## Secondary copy that must stay readable on a still or a dark card.
const C_SOFT := Color(0.66, 0.73, 0.77)
const C_GOLD := Color(0.96, 0.78, 0.30)
const C_LIVE := Color(0.62, 0.88, 0.66)
## Destructive confirm (quit): a broadcast red, never the gold primary.
const C_DANGER := Color(0.78, 0.26, 0.22)

## Wordmark drawn wherever player-facing chrome names the product.
const PRODUCT := "FOOTBALL"
const PRODUCT_TAIL := "SIM"
const PRODUCT_FULL := "Football Sim"

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
	if outline > 0:
		c.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_col)
	c.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

static func text_c(c: CanvasItem, center_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else fonts()["med"]
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(c, Vector2(center_x - w * 0.5, y), s, size, color, f)

static func text_r(c: CanvasItem, right_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else fonts()["med"]
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(c, Vector2(right_x - w, y), s, size, color, f)

## "FOOTBALL" in chalk white with "SIM" in broadcast gold; returns the width.
static func wordmark(c: CanvasItem, pos: Vector2, size: int, font: Font) -> float:
	var head: String = PRODUCT
	var tail: String = PRODUCT_TAIL
	var hw: float = font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var gap: float = size * 0.22
	text(c, pos, head, size, C_TEXT, font)
	text(c, Vector2(pos.x + hw + gap, pos.y), tail, size, C_GOLD, font)
	return hw + gap + font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Soft left-to-right scrim for a still backdrop: the wordmark and doors always
## sit on dark pixels without a hard-edged panel over the image.
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

## Thin broadcast rule that anchors a sheet's title.
static func rule(c: CanvasItem, center_x: float, y: float, w: float = 64.0, col: Color = C_GOLD) -> void:
	c.draw_rect(Rect2(center_x - w * 0.5, y, w, 3.0), col)

## Sheet header used by settings and the fixture picker: product bar top-left,
## a centred kicker + title, and an optional right-hand caption.
static func sheet_header(c: CanvasItem, vp: Vector2, fonts: Dictionary, kicker: String, title: String, caption: String = "") -> void:
	var bold: Font = fonts["bold"]
	wordmark(c, Vector2(24.0, 40.0), 20, bold)
	text(c, Vector2(24.0, 58.0), kicker, 10, C_DIM, fonts["med"])
	if caption != "":
		text_r(c, vp.x - 24.0, 40.0, caption, 11, C_DIM, bold)
	if vp.y < 620.0:
		rule(c, vp.x * 0.5, vp.y * 0.135, 48.0)
		text_c(c, vp.x * 0.5, vp.y * 0.195, title, 30, C_TEXT, bold)
	else:
		rule(c, vp.x * 0.5, vp.y * 0.185, 54.0)
		text_c(c, vp.x * 0.5, vp.y * 0.235, title, 38, C_TEXT, bold)
