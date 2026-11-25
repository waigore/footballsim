class_name DateHints
extends RefCounted

## The weekday that rides a displayed date (issue #99). Every surface that writes
## a calendar date registers the strip its text occupies; the sheet's overlay
## then paints the weekday for the strip under the pointer, so the date itself
## stays `15/AUG/2026` instead of growing a weekday it does not need.
##
## Registries are per sheet and cleared when that sheet lays out again, so a pose
## change never leaves a stale strip behind. A repaint that did not move a strip
## leaves it as it was: hovering must not grow the list.

## Air inside the weekday bubble around its text.
const PAD := 7.0
## The bubble's height, and the gap it keeps from the date it explains.
const BUBBLE_H := 17.0

var zones: Array = []
var _seen := {}

## Forget every strip: a sheet that lays out again starts from nothing.
func clear() -> void:
	zones.clear()
	_seen.clear()

## Register a strip for a date. An empty date (a blank column, a sheet with no
## clock yet) registers nothing.
func add(rect: Rect2, date: String) -> void:
	if date == "" or rect.size.x <= 0.0:
		return
	var key := "%s|%d|%d|%d|%d" % [date, int(rect.position.x), int(rect.position.y),
		int(rect.size.x), int(rect.size.y)]
	if _seen.has(key):
		return
	_seen[key] = true
	zones.append({"rect": rect, "date": date})

## The strip under a point, top-most first.
func at(p: Vector2) -> Dictionary:
	for i in range(zones.size() - 1, -1, -1):
		if (zones[i]["rect"] as Rect2).has_point(p):
			return zones[i]
	return {}

## The strip a label occupies, so a painter can register the date it just wrote
## without measuring the text twice. Both the width and the strip use the size
## the caption really paints at (the non-match reading floor), so a hover strip
## still covers a lifted caption (#126).
static func width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, ChromeDensity.read_size(size)).x

## The strip a label drawn from `pos` occupies.
static func strip(font: Font, s: String, pos: Vector2, size: int) -> Rect2:
	var px := float(ChromeDensity.read_size(size))
	return Rect2(pos.x, pos.y - px, width(font, s, size), px + 4.0)

## The same strip for a label drawn against a right edge.
static func strip_right(font: Font, s: String, right_x: float, y: float, size: int) -> Rect2:
	var out := strip(font, s, Vector2(right_x, y), size)
	out.position.x -= out.size.x
	return out

# gd-tools: no cover start

## The bubble itself: the weekday under the date it belongs to, or over it when
## the date sits against the bottom of the sheet. Kept inside the viewport so a
## strip at the margin never pushes its bubble off the screen, and kept under the
## line so a header title above the date is never covered.
static func paint(c: CanvasItem, cache: Dictionary, zone: Dictionary, vp: Vector2,
		fonts: Dictionary) -> void:
	var label: String = FixtureCalendar.weekday_label(str(zone["date"]))
	if label == "":
		return
	var bold: Font = fonts["bold"]
	var size := ChromeDensity.MIN_READ
	var w: float = bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + PAD * 2.0
	var rect: Rect2 = zone["rect"]
	var x: float = clampf(rect.position.x, 4.0, maxf(vp.x - w - 4.0, 4.0))
	var y: float = rect.end.y + 2.0
	if y + BUBBLE_H > vp.y - 2.0:
		y = rect.position.y - BUBBLE_H - 3.0
	UiChrome.panel(c, cache, Rect2(x, y, w, BUBBLE_H), UiChrome.C_PANEL_LIGHT, 4,
		UiChrome.C_GOLD, 1)
	UiChrome.text_c(c, x + w * 0.5, y + 12.0, label, size, UiChrome.C_GOLD, bold)

# gd-tools: no cover end
