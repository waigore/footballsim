class_name HudLayout
extends RefCounted


const PANEL_MARGIN := 24.0

const DESIGN_H := 900.0
const COMPACT_H := 620.0
const COMPACT_STATS_W := 240.0

const CONTROL_W := 108.0
const CONTROL_GAP := 6.0
const CONTROL_H := 46.0


const MOMENTUM_H := 22.0


const MOMENTUM_LABEL := 70.0
const MOMENTUM_INSET := 14.0
const MOMENTUM_TRACK_H := 4.0


const MOMENTUM_LABEL_Y := 10.0
const MOMENTUM_TRACK_Y := 12.0

const CONTROL_COUNT := 8


const CONTROL_COUNT_TOUCH := 9


const BREAK_W := 460.0

const BREAK_GAP := 10.0
const BREAK_BASE_H := 190.0
const BREAK_LINE_H := 15.0
const BREAK_ROWS_Y := 150.0
const BREAK_SUB_Y := 168.0

const BREAK_MAX_ROWS := 8


const BREAK_COMPACT_BASE_H := 132.0
const BREAK_COMPACT_LINE_H := 13.0
const BREAK_COMPACT_ROWS_Y := 88.0
const BREAK_COMPACT_SUB_Y := 116.0
const BREAK_COMPACT_PER_ROW := 2
const BREAK_COMPACT_MAX_ROWS := 4


const HUD_SLIDE_SECONDS := 0.22
const HUD_SLIDE_TOP := 168.0
const HUD_SLIDE_BOTTOM := 148.0
const HUD_TOGGLE_W := 132.0

const HUD_TOGGLE_H := 30.0

const HUD_TOGGLE_TAP := 44.0


static func is_compact(vp: Vector2) -> bool:
	return vp.y < COMPACT_H


static func scale_for(dp_height: float) -> float:
	return clampf(DESIGN_H / maxf(dp_height, 1.0), 1.0, 2.6)


static func overlay_scale() -> float:
	if not (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()):
		return 1.0
	var px := DisplayServer.screen_get_size()
	var density: float = maxf(DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi() / 160.0)
	if px.x <= 0 or px.y <= 0 or density <= 0.0:
		return 1.0
	return scale_for(float(mini(px.x, px.y)) / density)


static func control_count(vp: Vector2, touch := false) -> int:
	return CONTROL_COUNT_TOUCH if (touch or is_compact(vp)) else CONTROL_COUNT


static func controls_per_row(vp: Vector2, touch := false) -> int:
	var n := control_count(vp, touch)
	var k := n
	while k > 1:
		var avail: float = vp.x - 2.0 * PANEL_MARGIN - CONTROL_GAP * float(k - 1)
		if avail / float(k) >= 44.0:
			break
		k -= 1
	return k

static func control_rows(vp: Vector2, touch := false) -> int:
	var per := controls_per_row(vp, touch)
	return int(ceil(float(control_count(vp, touch)) / float(per)))

static func control_width(vp: Vector2, touch := false) -> float:
	var per := controls_per_row(vp, touch)
	var avail: float = vp.x - 2.0 * PANEL_MARGIN - CONTROL_GAP * float(per - 1)
	return minf(CONTROL_W, avail / float(per))

static func controls_rect(vp: Vector2, touch := false) -> Rect2:
	var per := controls_per_row(vp, touch)
	var w := control_width(vp, touch)
	var rows := control_rows(vp, touch)
	var total: float = w * float(mini(per, control_count(vp, touch))) + CONTROL_GAP * float(mini(per, control_count(vp, touch)) - 1)
	var h: float = CONTROL_H * float(rows) + CONTROL_GAP * float(rows - 1)
	return Rect2(vp.x * 0.5 - total * 0.5, vp.y - 20.0 - h, total, h)

static func commentary_rect(vp: Vector2) -> Rect2:
	return Rect2(PANEL_MARGIN, vp.y - 126.0, minf(620.0, vp.x - 2.0 * PANEL_MARGIN), 52.0)


static func hud_toggle_rect(vp: Vector2, touch := false) -> Rect2:
	var h: float = HUD_TOGGLE_TAP if (touch or is_compact(vp)) else HUD_TOGGLE_H
	var top: float = commentary_rect(vp).position.y - 8.0 - h
	return Rect2(PANEL_MARGIN, maxf(top, scoreboard_rect(vp).end.y + 4.0), HUD_TOGGLE_W, h)


static func break_band(vp: Vector2) -> Rect2:
	var top: float = scoreboard_rect(vp).end.y + BREAK_GAP
	var bottom: float = commentary_rect(vp).position.y - BREAK_GAP
	return Rect2(PANEL_MARGIN, top, vp.x - 2.0 * PANEL_MARGIN, maxf(bottom - top, 0.0))


static func break_metrics(vp: Vector2, home_goals: int = 0, away_goals: int = 0) -> Dictionary:
	var compact := is_compact(vp)
	var base: float = BREAK_COMPACT_BASE_H if compact else BREAK_BASE_H
	var step: float = BREAK_COMPACT_LINE_H if compact else BREAK_LINE_H
	var per_row := BREAK_COMPACT_PER_ROW if compact else 1
	var cap := BREAK_COMPACT_MAX_ROWS if compact else BREAK_MAX_ROWS
	var band := break_band(vp)
	var room: bool = band.size.y >= base
	var capacity := 0
	if room:
		capacity = clampi(int(floor((band.size.y - base) / step)), 0, cap)
	var needed := 0
	if compact:
		needed = int(ceil(float(maxi(home_goals + away_goals, 0)) / float(per_row)))
	else:
		needed = maxi(home_goals, away_goals)


	var rows: int = mini(maxi(needed, 0), capacity) if room else 0


	var w: float = minf(BREAK_W, vp.x - 2.0 * PANEL_MARGIN)
	var x: float = vp.x * 0.5 - w * 0.5
	if compact:
		x = PANEL_MARGIN
		w = minf(scoreboard_rect(vp).size.x, vp.x - 2.0 * PANEL_MARGIN)
	var h: float = base + step * float(rows)


	var y: float = vp.y * 0.5 - h * 0.5
	var squeezed := false
	if band.size.y >= h:
		y = clampf(y, band.position.y, band.end.y - h)
	elif band.size.y > 0.0:
		h = band.size.y
		y = band.position.y
		squeezed = true
		rows = 0
	var title_y: float = 30.0 if compact else 48.0
	var title_size: int = 20 if compact else 30
	var score_y: float = 70.0 if compact else 104.0
	var score_size: int = 34 if compact else 48
	var sub_y: float = (BREAK_COMPACT_SUB_Y if compact else BREAK_SUB_Y) + step * float(rows)
	if squeezed:

		title_size = 14
		title_y = h * 0.34
		score_size = int(clampf(h * 0.46, 18.0, 34.0))
		score_y = h * 0.82
		sub_y = h + 12.0
	return {
		"rect": Rect2(x, y, w, h),
		"rows": rows,
		"capacity": capacity,
		"per_row": per_row,
		"compact": compact,
		"title_y": title_y,
		"title_size": title_size,
		"score_y": score_y,
		"score_size": score_size,
		"abbr_y": 132.0,
		"abbr_size": 11,
		"rows_y": BREAK_COMPACT_ROWS_Y if compact else BREAK_ROWS_Y,
		"step": step,
		"line_size": 10 if compact else 12,
		"sub_y": (BREAK_COMPACT_SUB_Y if compact else BREAK_SUB_Y) + step * float(rows),
		"sub_size": 9 if compact else 10,
	}

static func scoreboard_rect(vp: Vector2) -> Rect2:
	if is_compact(vp):
		var w: float = maxf(vp.x - (2.0 * PANEL_MARGIN + COMPACT_STATS_W + 10.0), 320.0)
		return Rect2(PANEL_MARGIN, 12.0, w, 86.0)
	return Rect2(vp.x * 0.5 - 320.0, 14.0, 640.0, 86.0)

static func stats_rect(vp: Vector2) -> Rect2:
	if is_compact(vp):


		return Rect2(vp.x - PANEL_MARGIN - COMPACT_STATS_W, 12.0, COMPACT_STATS_W, stats_row_limit(vp) * 16.0 + 45.0 + MOMENTUM_H)
	return Rect2(vp.x - PANEL_MARGIN - 300.0, PANEL_MARGIN, 300.0, 132.0 + MOMENTUM_H)


static func momentum_rect(vp: Vector2) -> Rect2:
	var box := stats_rect(vp)
	var left: float = box.position.x + MOMENTUM_INSET + MOMENTUM_LABEL
	var right: float = box.end.x - MOMENTUM_INSET
	var y: float = momentum_rule_y(vp) + MOMENTUM_TRACK_Y
	return Rect2(left, y, maxf(right - left, 24.0), MOMENTUM_TRACK_H)


static func momentum_rule_y(vp: Vector2) -> float:
	return stats_rect(vp).end.y - MOMENTUM_H

static func stats_row_limit(vp: Vector2) -> int:
	if is_compact(vp) and vp.y < 400.0:
		return 3
	return 5


static func pitch_band(vp: Vector2, touch := false) -> Rect2:
	var top: float = scoreboard_rect(vp).end.y + 27.0
	var bottom: float = controls_rect(vp, touch).position.y
	return Rect2(PANEL_MARGIN, top, vp.x - 2.0 * PANEL_MARGIN, maxf(bottom - top, 80.0))


static func pitch_fit(vp_logical: Vector2, scale: float, touch := false) -> Dictionary:
	var fit := minf(vp_logical.y / 102.0, (vp_logical.x - 40.0) / 135.0)
	var band := pitch_band(vp_logical / maxf(scale, 0.001), touch)
	var band_fit: float = band.size.y * scale / 76.0
	var offset := 0.0
	if band_fit < fit:
		fit = band_fit
		var band_mid: float = (band.position.y + band.size.y * 0.5) * scale
		offset = (band_mid - vp_logical.y * 0.5) / maxf(fit, 0.001)
	return {"zoom": maxf(fit, 3.0), "offset": offset}
