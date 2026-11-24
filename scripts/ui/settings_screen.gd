class_name SettingsScreen
extends RefCounted

## Settings sheet: one control, menu music volume. Every rect is a function of
## the design viewport so the phone overlay (scaled by main.gd) gets the same
## layout at 44-unit tap targets, and a headless test can read the geometry.

var mouse := Vector2(-1000, -1000)
var dragging := false
var _cache := {}

static func card_rect(vp: Vector2) -> Rect2:
	var w: float = minf(560.0, vp.x - 48.0)
	var top: float = vp.y * (0.33 if vp.y < 620.0 else 0.30)
	var h: float = maxf(minf(210.0, vp.y - top - 30.0), 170.0)
	return Rect2(vp.x * 0.5 - w * 0.5, top, w, h)

static func row_y(vp: Vector2) -> float:
	return card_rect(vp).position.y + 86.0

static func minus_rect(vp: Vector2) -> Rect2:
	var card := card_rect(vp)
	return Rect2(card.position.x + 24.0, row_y(vp) + 8.0, 44.0, 44.0)

static func plus_rect(vp: Vector2) -> Rect2:
	var card := card_rect(vp)
	return Rect2(card.end.x - 24.0 - 44.0, row_y(vp) + 8.0, 44.0, 44.0)

static func track_rect(vp: Vector2) -> Rect2:
	var a := minus_rect(vp)
	var b := plus_rect(vp)
	var x: float = a.end.x + 18.0
	var w: float = maxf(b.position.x - 18.0 - x, 60.0)
	return Rect2(x, row_y(vp) + 25.0, w, 10.0)

## Same door the fixture sheet carries, so every sheet has one way out in the
## same corner.
static func back_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - 24.0 - 116.0, 18.0, 116.0, 44.0)

## Volume a pointer at `p` means, read on the track plus a finger-sized margin
## above and below it. `vp` is the design viewport the sheet was drawn in.
func value_at(p: Vector2, vp: Vector2 = Vector2(1600, 900)) -> float:
	var t := track_rect(vp)
	var grab := Rect2(t.position.x, t.position.y - 20.0, t.size.x, t.size.y + 40.0)
	if not grab.has_point(p):
		return -1.0
	return clampf((p.x - t.position.x) / maxf(t.size.x, 1.0), 0.0, 1.0)

func button_at(p: Vector2, vp: Vector2 = Vector2(1600, 900)) -> String:
	if track_rect(vp).grow_individual(0.0, 20.0, 0.0, 20.0).has_point(p):
		return "track"
	if minus_rect(vp).has_point(p):
		return "minus"
	if plus_rect(vp).has_point(p):
		return "plus"
	if back_rect(vp).has_point(p):
		return "back"
	return ""

func click(p: Vector2, vp: Vector2 = Vector2(1600, 900)) -> String:
	var id := button_at(p, vp)
	if id == "track":
		dragging = true
	return id

# ----------------------------------------------------------------- drawing --

func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary, volume: float, touch: bool = false) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	UiChrome.sheet_header(c, vp, fonts, "AUDIO · PREFS", "SETTINGS", "")
	var card := card_rect(vp)
	UiChrome.panel(c, _cache, card, UiChrome.C_PANEL, 12, Color(1, 1, 1, 0.10))
	c.draw_rect(Rect2(card.position.x + 1.0, card.position.y + 12.0, 3.0, 34.0), UiChrome.C_GOLD)
	UiChrome.text(c, Vector2(card.position.x + 24.0, card.position.y + 44.0), "MENU MUSIC", 18, UiChrome.C_TEXT, bold)
	UiChrome.text(c, Vector2(card.position.x + 24.0, card.position.y + 62.0), "PLAYS ON THE MENU AND SETTINGS ONLY", 10, UiChrome.C_SOFT, med)
	UiChrome.text_r(c, card.end.x - 24.0, card.position.y + 46.0, "%d%%" % int(round(volume * 100.0)), 26, UiChrome.C_GOLD, bold)
	_draw_step(c, minus_rect(vp), "-", fonts)
	_draw_step(c, plus_rect(vp), "+", fonts)
	_draw_track(c, vp, volume, fonts)
	var hint := "0% MUTES THE MENU MUSIC  ·  CROWD IS UNAFFECTED"
	if touch or vp.y < 620.0:
		hint = "DRAG THE BAR  ·  CROWD IS UNAFFECTED"
	UiChrome.text(c, Vector2(card.position.x + 24.0, card.end.y - 22.0), hint, 10, UiChrome.C_SOFT, med)
	_draw_back(c, vp, fonts, bold, touch)

func _draw_step(c: CanvasItem, r: Rect2, glyph: String, fonts: Dictionary) -> void:
	var hovered := r.has_point(mouse)
	UiChrome.panel(c, _cache, r, UiChrome.C_PANEL_LIGHT if hovered else Color(0.05, 0.075, 0.09, 0.96), 8, Color(1, 1, 1, 0.14 if hovered else 0.07))
	UiChrome.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 30.0, glyph, 24, UiChrome.C_TEXT if hovered else UiChrome.C_SOFT, fonts["bold"])

func _draw_track(c: CanvasItem, vp: Vector2, volume: float, fonts: Dictionary) -> void:
	var t := track_rect(vp)
	c.draw_rect(Rect2(t.position.x, t.position.y, t.size.x, t.size.y), Color(1, 1, 1, 0.18))
	var fill: float = t.size.x * clampf(volume, 0.0, 1.0)
	if fill > 0.0:
		c.draw_rect(Rect2(t.position, Vector2(fill, t.size.y)), UiChrome.C_GOLD)
	var knob := Vector2(t.position.x + fill, t.position.y + t.size.y * 0.5)
	c.draw_circle(knob, 9.0, UiChrome.C_TEXT)
	c.draw_circle(knob, 5.0, UiChrome.C_GOLD)
	UiChrome.text_c(c, t.position.x, t.end.y + 34.0, "0", 10, UiChrome.C_SOFT, fonts["med"])
	UiChrome.text_c(c, t.end.x, t.end.y + 34.0, "100", 10, UiChrome.C_SOFT, fonts["med"])

func _draw_back(c: CanvasItem, vp: Vector2, fonts: Dictionary, bold: Font, touch: bool) -> void:
	var r := back_rect(vp)
	var hovered := r.has_point(mouse)
	UiChrome.panel(c, _cache, r, UiChrome.C_PANEL_LIGHT if hovered else UiChrome.C_PANEL, 8, Color(1, 1, 1, 0.14 if hovered else 0.07))
	UiChrome.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 29.0, "‹  BACK", 13, UiChrome.C_TEXT if hovered else UiChrome.C_DIM, bold)
	if not touch:
		UiChrome.text_r(c, vp.x - 24.0, 76.0, "ESC", 10, UiChrome.C_SOFT, fonts["med"])
