class_name HudLayout
extends RefCounted

## Shared geometry for the broadcast overlay. Every panel rect is derived here
## so the drawing code and the layout tests read the same numbers.
##
## On handhelds the overlay is drawn in a smaller design space and the whole
## layer is scaled back up by `overlay_scale()`: one design unit then lands at
## roughly one density point, so 11-unit type is a readable 13 pt instead of a
## one-millimetre hairline. The pitch keeps its own metre scale — only chrome
## grows.

const PANEL_MARGIN := 24.0

const DESIGN_H := 900.0
const COMPACT_H := 620.0
const COMPACT_STATS_W := 240.0

const CONTROL_W := 108.0
const CONTROL_GAP := 6.0
const CONTROL_H := 46.0
const CONTROL_COUNT := 7
const CONTROL_COUNT_TOUCH := 8

## Touch builds get one extra door (teams) because the fixture panel that
## carries it on desktop is not drawn in compact. The league door rides the bar
## on every platform so the encyclopedia is always one tap away.
static func is_compact(vp: Vector2) -> bool:
	return vp.y < COMPACT_H

## One design unit per density point, measured against the short screen edge.
static func scale_for(dp_height: float) -> float:
	return clampf(DESIGN_H / maxf(dp_height, 1.0), 1.0, 2.6)

## Design-space multiplier for touch builds; 1.0 on desktop.
static func overlay_scale() -> float:
	if not (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()):
		return 1.0
	var px := DisplayServer.screen_get_size()
	var density: float = maxf(DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi() / 160.0)
	if px.x <= 0 or px.y <= 0 or density <= 0.0:
		return 1.0
	return scale_for(float(mini(px.x, px.y)) / density)

## Touch builds carry the teams door on the bar (the fixture panel that holds
## it on desktop is not drawn there), and phone metrics need it regardless
## because the panel does not fit either.
static func control_count(vp: Vector2, touch := false) -> int:
	return CONTROL_COUNT_TOUCH if (touch or is_compact(vp)) else CONTROL_COUNT

## Doors per row: a narrow design space (a square-ish handset) wraps the bar
## instead of shrinking every door below the 44-unit tap floor.
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

static func scoreboard_rect(vp: Vector2) -> Rect2:
	if is_compact(vp):
		var w: float = maxf(vp.x - (2.0 * PANEL_MARGIN + COMPACT_STATS_W + 10.0), 320.0)
		return Rect2(PANEL_MARGIN, 12.0, w, 86.0)
	return Rect2(vp.x * 0.5 - 320.0, 14.0, 640.0, 86.0)

static func stats_rect(vp: Vector2) -> Rect2:
	if is_compact(vp):
		# A 360-unit-tall design space (a 720p handset) has no room for five
		# rows beside the pitch, so the card drops to three.
		return Rect2(vp.x - PANEL_MARGIN - COMPACT_STATS_W, 12.0, COMPACT_STATS_W, stats_row_limit(vp) * 16.0 + 45.0)
	return Rect2(vp.x - PANEL_MARGIN - 300.0, PANEL_MARGIN, 300.0, 132.0)

static func stats_row_limit(vp: Vector2) -> int:
	if is_compact(vp) and vp.y < 400.0:
		return 3
	return 5

## Vertical strip the pitch must stay inside: the full-width bands (scoreboard
## and possession bar on top, control bar at the bottom). Narrow side panels may
## overlap the pitch corners, exactly as the desktop broadcast does.
static func pitch_band(vp: Vector2, touch := false) -> Rect2:
	var top: float = scoreboard_rect(vp).end.y + 27.0
	var bottom: float = controls_rect(vp, touch).position.y
	return Rect2(PANEL_MARGIN, top, vp.x - 2.0 * PANEL_MARGIN, maxf(bottom - top, 80.0))

## Camera fit for a logical (stretched) viewport, in pixels per metre, plus the
## metres the pitch centre must move so the pitch is centred inside the band.
## The band only ever shrinks the fit, so desktop framing is unchanged.
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
