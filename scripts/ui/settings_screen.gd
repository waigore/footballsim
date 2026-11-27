class_name SettingsScreen
extends RefCounted


var mouse := Vector2(-1000, -1000)
var dragging := false
var _cache := {}


const HUD_ROW_HINT := "ON SHOWS THE BARS · SCORE AND MATCH CARDS STAY"


const CARD_H := 366.0


const CARD_H_MIN := 250.0

const ROW_STEP := 104.0


const ROW_STEP_MIN := 52.0


const SEG_W := 112.0
const SEG_GAP := 8.0
const SEG_H := 44.0


const MODE_WIDE := 540.0
const MODE_ROW_INLINE := 52.0
const MODE_ROW_STACKED := 68.0


static func card_rect(vp: Vector2) -> Rect2:
	var w: float = minf(560.0, vp.x - 48.0)
	var top_max: float = maxf(12.0, vp.y - 12.0 - CARD_H_MIN)
	var top: float = clampf(vp.y * (0.33 if vp.y < 620.0 else 0.30), 12.0, top_max)
	var room: float = vp.y - top - 12.0
	var h: float = clampf(room, minf(CARD_H_MIN, room), CARD_H)
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


static func row_step(vp: Vector2) -> float:
	var card := card_rect(vp)
	var room: float = card.end.y - 12.0 - row_y(vp) - mode_row_h(vp)
	return clampf(room * 0.5, ROW_STEP_MIN, ROW_STEP)


static func roomy(vp: Vector2) -> bool:
	return row_step(vp) >= ROW_STEP - 0.5


static func hud_row_y(vp: Vector2) -> float:
	return row_y(vp) + row_step(vp)


static func mode_row_y(vp: Vector2) -> float:
	return hud_row_y(vp) + row_step(vp)

static func mode_stacked(vp: Vector2) -> bool:
	return card_rect(vp).size.x < MODE_WIDE

static func mode_row_h(vp: Vector2) -> float:
	return MODE_ROW_STACKED if mode_stacked(vp) else MODE_ROW_INLINE


static func seg_rects(vp: Vector2) -> Array:
	var card := card_rect(vp)
	var top: float = mode_row_y(vp) + (18.0 if mode_stacked(vp) else 8.0)
	var width: float = card.size.x - 48.0
	var left: float = card.position.x + 24.0
	if not mode_stacked(vp):
		width = 3.0 * SEG_W + 2.0 * SEG_GAP
		left = card.end.x - 24.0 - width
	var each: float = (width - 2.0 * SEG_GAP) / 3.0
	var out: Array = []
	for i in range(Prefs.MODES.size()):
		out.append(Rect2(left + float(i) * (each + SEG_GAP), top, each, SEG_H))
	return out


static func hud_toggle_rect(vp: Vector2) -> Rect2:
	var card := card_rect(vp)
	return Rect2(card.end.x - 24.0 - 96.0, hud_row_y(vp) + 8.0, 96.0, 44.0)


static func back_rect(vp: Vector2) -> Rect2:
	return Rect2(24.0, 12.0, 116.0, 44.0)


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
	if hud_toggle_rect(vp).has_point(p):
		return "hud"
	var segs := seg_rects(vp)
	for i in range(segs.size()):
		if (segs[i] as Rect2).has_point(p):
			return "mode:%s" % Prefs.MODES[i]
	if back_rect(vp).has_point(p):
		return "back"
	return ""

func click(p: Vector2, vp: Vector2 = Vector2(1600, 900)) -> String:
	var id := button_at(p, vp)
	if id == "track":
		dragging = true
	return id


func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary, volume: float, touch: bool = false,
		hud_on: bool = true, match_mode: String = Prefs.DEFAULT_MODE) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	UiChrome.sheet_header(c, vp, fonts, "SETTINGS")
	var card := card_rect(vp)
	var roomy_rows := roomy(vp)
	UiChrome.panel(c, _cache, card, UiChrome.C_PANEL, 12, Color(1, 1, 1, 0.10))
	c.draw_rect(Rect2(card.position.x + 1.0, card.position.y + 12.0, 3.0, 34.0), UiChrome.C_GOLD)
	UiChrome.text(c, Vector2(card.position.x + 24.0, card.position.y + 44.0), "MENU MUSIC", 18, UiChrome.C_TEXT, bold)
	UiChrome.text(c, Vector2(card.position.x + 24.0, card.position.y + 62.0), "PLAYS ON THE MENU AND SETTINGS ONLY", 10, UiChrome.C_SOFT, med)
	UiChrome.text_r(c, card.end.x - 24.0, card.position.y + 46.0, "%d%%" % int(round(volume * 100.0)), 26, UiChrome.C_GOLD, bold)
	_draw_step(c, minus_rect(vp), "-", fonts)
	_draw_step(c, plus_rect(vp), "+", fonts)
	_draw_track(c, vp, volume, fonts)
	if roomy_rows:
		var hint := "0% MUTES THE MENU MUSIC  ·  CROWD IS UNAFFECTED"
		if touch or vp.y < 620.0:
			hint = "DRAG THE BAR  ·  CROWD IS UNAFFECTED"
		UiChrome.text(c, Vector2(card.position.x + 24.0, row_y(vp) + 88.0), hint, 10, UiChrome.C_SOFT, med)
		var hy := hud_row_y(vp)
		c.draw_line(Vector2(card.position.x + 14.0, hy - 12.0), Vector2(card.end.x - 14.0, hy - 12.0), Color(1, 1, 1, 0.07), 1)
		UiChrome.text(c, Vector2(card.position.x + 24.0, hy + 26.0), "MATCH HUD", 18, UiChrome.C_TEXT, bold)
		UiChrome.text(c, Vector2(card.position.x + 24.0, hy + 44.0), HUD_ROW_HINT, 10, UiChrome.C_SOFT, med)
	else:
		UiChrome.text(c, Vector2(card.position.x + 24.0, hud_row_y(vp) + 26.0), "MATCH HUD", 13, UiChrome.C_TEXT, bold)
	_draw_switch(c, hud_toggle_rect(vp), hud_on, fonts)
	_draw_mode_row(c, vp, fonts, match_mode, touch, roomy_rows)
	_draw_back(c, vp, fonts, bold, touch)

func _draw_step(c: CanvasItem, r: Rect2, glyph: String, fonts: Dictionary) -> void:
	var hovered := r.has_point(mouse)
	UiChrome.panel(c, _cache, r, UiChrome.C_PANEL_LIGHT if hovered else Color(0.05, 0.075, 0.09, 0.96), 8, Color(1, 1, 1, 0.14 if hovered else 0.07))
	UiChrome.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 30.0, glyph, 24, UiChrome.C_TEXT if hovered else UiChrome.C_SOFT, fonts["bold"])


func _draw_switch(c: CanvasItem, r: Rect2, on: bool, fonts: Dictionary) -> void:
	var hovered := r.has_point(mouse)
	var border: Color = Color(0.96, 0.78, 0.30, 0.45 if on else 0.16) if on or hovered else Color(1, 1, 1, 0.07)
	var fill: Color = Color(0.16, 0.13, 0.05, 0.96) if on else Color(0.05, 0.075, 0.09, 0.96)
	UiChrome.panel(c, _cache, r, fill, 8, border)
	var label := "ON" if on else "OFF"
	var size := 13
	var w: float = fonts["bold"].get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	UiChrome.text(c, Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + r.size.y * 0.5 + 5.0), label, size, UiChrome.C_GOLD if on else UiChrome.C_DIM, fonts["bold"])
	if on:
		c.draw_rect(Rect2(r.position.x + 2.0, r.position.y + r.size.y - 4.0, r.size.x - 4.0, 2.0), UiChrome.C_GOLD)


func _draw_mode_row(c: CanvasItem, vp: Vector2, fonts: Dictionary, mode: String, touch: bool, roomy_rows: bool) -> void:
	var card := card_rect(vp)
	var my := mode_row_y(vp)
	if roomy_rows:
		c.draw_line(Vector2(card.position.x + 14.0, my - 12.0), Vector2(card.end.x - 14.0, my - 12.0), Color(1, 1, 1, 0.07), 1)
	if mode_stacked(vp):
		UiChrome.text(c, Vector2(card.position.x + 24.0, my + 12.0), "MATCH VIEW", 10, UiChrome.C_SOFT, fonts["bold"])
	else:
		UiChrome.text(c, Vector2(card.position.x + 24.0, my + 30.0), "MATCH VIEW", 18, UiChrome.C_TEXT, fonts["bold"])
	var segs := seg_rects(vp)
	var chosen := Prefs.normalize_mode(mode)
	for i in range(segs.size()):
		var id: String = Prefs.MODES[i]
		_draw_segment(c, segs[i], Prefs.mode_label(id), id == chosen, str(i + 1), touch, fonts)

func _draw_segment(c: CanvasItem, r: Rect2, label: String, on: bool, key_hint: String, touch: bool, fonts: Dictionary) -> void:
	var hovered := r.has_point(mouse)
	var border: Color = Color(0.96, 0.78, 0.30, 0.45 if on else 0.16) if on or hovered else Color(1, 1, 1, 0.07)
	var fill: Color = Color(0.16, 0.13, 0.05, 0.96) if on else Color(0.05, 0.075, 0.09, 0.96)
	UiChrome.panel(c, _cache, r, fill, 8, border)
	var ink: Color = UiChrome.C_GOLD if on else (UiChrome.C_TEXT if hovered else UiChrome.C_SOFT)


	if touch:
		UiChrome.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + 5.0, label, 12, ink, fonts["bold"])
	else:
		UiChrome.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 24.0, label, 12, ink, fonts["bold"])
		UiChrome.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 38.0, key_hint, 9, UiChrome.C_DIM, fonts["med"])
	if on:
		c.draw_rect(Rect2(r.position.x + 2.0, r.position.y + r.size.y - 4.0, r.size.x - 4.0, 2.0), UiChrome.C_GOLD)

func _draw_track(c: CanvasItem, vp: Vector2, volume: float, fonts: Dictionary) -> void:
	var t := track_rect(vp)
	c.draw_rect(Rect2(t.position.x, t.position.y, t.size.x, t.size.y), Color(1, 1, 1, 0.18))
	var fill: float = t.size.x * clampf(volume, 0.0, 1.0)
	if fill > 0.0:
		c.draw_rect(Rect2(t.position, Vector2(fill, t.size.y)), UiChrome.C_GOLD)
	var knob := Vector2(t.position.x + fill, t.position.y + t.size.y * 0.5)
	c.draw_circle(knob, 9.0, UiChrome.C_TEXT)
	c.draw_circle(knob, 5.0, UiChrome.C_GOLD)
	if not roomy(vp):
		return
	UiChrome.text_c(c, t.position.x, t.end.y + 34.0, "0", 10, UiChrome.C_SOFT, fonts["med"])
	UiChrome.text_c(c, t.end.x, t.end.y + 34.0, "100", 10, UiChrome.C_SOFT, fonts["med"])

func _draw_back(c: CanvasItem, vp: Vector2, fonts: Dictionary, bold: Font, touch: bool) -> void:
	var r := back_rect(vp)
	var hovered := r.has_point(mouse)
	UiChrome.panel(c, _cache, r, UiChrome.C_PANEL_LIGHT if hovered else UiChrome.C_PANEL, 8, Color(1, 1, 1, 0.14 if hovered else 0.07))
	UiChrome.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 29.0, "‹  BACK", 13, UiChrome.C_TEXT if hovered else UiChrome.C_DIM, bold)
	if not touch:
		UiChrome.text_r(c, vp.x - 24.0, 76.0, "ESC", 10, UiChrome.C_SOFT, fonts["med"])
