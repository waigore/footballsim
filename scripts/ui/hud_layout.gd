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
## Desktop bar: pause, speed, mode, skip, camera, restart, menu.
const CONTROL_COUNT := 7
## Touch/compact adds the teams door, because the fixture panel that carries it
## on desktop is not drawn there.
const CONTROL_COUNT_TOUCH := 8

## Touch builds get one extra door (teams) because the fixture panel that
## carries it on desktop is not drawn in compact.
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

## A near-square design viewport (a test viewport, or a phone held to the ear)
## is narrower than any real landscape handset; the bar keeps 44-unit doors by
## giving up its outer margin rather than shrinking a tap target.
static func control_margin(vp: Vector2) -> float:
	return 8.0 if vp.x < 520.0 else PANEL_MARGIN

static func control_width(vp: Vector2, touch := false) -> float:
	var n := control_count(vp, touch)
	var avail: float = vp.x - 2.0 * control_margin(vp) - CONTROL_GAP * float(n - 1)
	return minf(CONTROL_W, avail / float(n))

static func controls_rect(vp: Vector2, touch := false) -> Rect2:
	var n := control_count(vp, touch)
	var w := control_width(vp, touch)
	var total: float = w * float(n) + CONTROL_GAP * float(n - 1)
	return Rect2(vp.x * 0.5 - total * 0.5, vp.y - 66.0, total, CONTROL_H)

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
