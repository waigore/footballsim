class_name SettingsLayout
extends RefCounted


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
