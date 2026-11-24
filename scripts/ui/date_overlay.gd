class_name DateOverlay
extends Control

## The weekday bubble for the date under the pointer (issue #99). It is the last
## child of a sheet, so it paints above the scrolling body and the chrome.
##
## The sheet it watches owns two registries: `hints` for its chrome (design
## space) and `rows_hints` for the sheet on screen. Row strips come in two
## spaces — the encyclopedia body lays them out in its own window, the league
## sheets lay them out in design space and scroll the paint — so `rows_local`
## says which correction the pointer needs.
##
## A mouse reveals the weekday on hover. Touch has no hover, so the bubble
## answers a press that is still held; releasing puts it away.

var screen = null
## The scrolling window whose offset moves the row strips.
var body = null
## True when row strips sit in the body's own space (the encyclopedia), false
## when they sit in design space (the league sheets).
var rows_local := false
var cache := {}

## Attach an overlay to a sheet. It is added last, so it draws above the body.
static func attach(sheet, window, local_rows: bool) -> DateOverlay:
	var out := DateOverlay.new()
	out.screen = sheet
	out.body = window
	out.rows_local = local_rows
	sheet.add_child(out)
	return out

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

## The bubble answers a free pointer on desktop, and a held one on a touch
## screen, where there is no hover to answer.
func showing() -> bool:
	return screen != null and (not bool(screen.touch) or bool(screen.holding))

## The date strip under the pointer: the chrome's own dates first, then the rows
## of the sheet on screen.
func zone_at() -> Dictionary:
	if screen == null:
		return {}
	var p: Vector2 = screen.mouse
	var zone: Dictionary = screen.hints.at(p)
	if not zone.is_empty() or body == null or screen.rows_hints == null:
		return zone
	if not Rect2(body.position, body.size).has_point(p):
		return zone
	var origin: Vector2 = body.position if rows_local else Vector2.ZERO
	var offset := Vector2(0.0, body.scroll)
	if not rows_local:
		offset = Vector2(body.hscroll, body.scroll)
	return screen.rows_hints.at(p - origin + offset)

## The sheet under the overlay repaints on its own schedule (a scroll, a pose
## change), so the bubble re-reads its strip every frame rather than trusting a
## pointer-motion callback.
func _process(_delta: float) -> void:
	queue_redraw()

# gd-tools: no cover start

func _draw() -> void:
	if not showing():
		return
	var zone := zone_at()
	if zone.is_empty():
		return
	DateHints.paint(self, cache, zone, screen.design_vp(), UiChrome.fonts())

# gd-tools: no cover end
