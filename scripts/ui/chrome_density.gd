class_name ChromeDensity
extends RefCounted

## Reading density for every screen outside the match (issue #81).
##
## The menu, settings, league hub/table/calendar, encyclopedia, fixture picker,
## full-time sheets and confirms are read at a normal desktop distance, so one
## design unit must never land on a hairline. This module is the single place
## that decides how many density points a design unit is worth; the shells pass
## the result to their `ui_scale` (and to the layer transform) exactly like the
## handheld overlay path does.
##
## The match overlay is NOT part of this path: HudLayout/overlay_scale owns the
## broadcast HUD and keeps its own sizing (issue #81 leaves it alone).

## Density points per design unit on the reference window, so a 10-unit caption
## reads as 12.5 points instead of a squint.
const BASE := 1.25
## Window height (density points) the sheets are authored against.
const REF_H := 900.0
## A very tall window may spend its extra room on bigger chrome, but the layout
## still needs somewhere to put the content.
const MAX := 1.6

## Chrome scale for a window measured in density points. Floored at BASE, so a
## laptop fullscreen (fewer points than the reference) never shrinks the type,
## and growing with the window above the reference, so a large desktop enlarges
## the chrome instead of leaving fixed-size text on a huge sheet.
static func scale_for(points: Vector2) -> float:
	return clampf(BASE * maxf(points.y, REF_H) / REF_H, BASE, MAX)

## The smallest size a non-match caption is painted at, in design units (#126).
## A caption authored below it lands on a hairline at the base scale — the
## calendar's `10/10` counter was 7 — so the paint primitives lift anything
## smaller to this floor instead of trusting every sheet to remember it.
const MIN_READ := 10

## The size a non-match caption is actually painted at: the caller's size, or
## the reading floor when it asked for less. Alignment and hit strips measure
## through the same call, so a lifted caption is placed on the width it draws.
static func read_size(size: int) -> int:
	return maxi(size, MIN_READ)

## The window in density points: engines report pixels, so a Retina window is
## halved before it is compared with the reference height.
static func window_points() -> Vector2:
	var px := Vector2(DisplayServer.window_get_size())
	if px.x <= 0.0 or px.y <= 0.0:
		return Vector2(REF_H * 16.0 / 9.0, REF_H)
	return px / maxf(DisplayServer.screen_get_scale(), 1.0)

## What the non-match layers read: one shared path on desktop, and the handset
## overlay scale on touch, where the phone layout is already tuned.
static func non_match_scale() -> float:
	return scale_for(window_points())
