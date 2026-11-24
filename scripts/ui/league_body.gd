class_name LeagueBody
extends Control

## Scroll window for the league sheets. It clips the season content to the band
## between the header and the bottom bar, owns the scroll offset that the hit
## test and the painted rows must share, and hands the paint to the sheet that
## laid the rows out. Chrome (the header and the bottom bar) stays on the screen
## above it, exactly like the encyclopedia's body sits under its own header.

## Sheet chrome above the content (LeagueSheet.HEADER).
const TOP := LeagueSheet.HEADER
## Bottom action bar under the content (LeagueSheet.BAR_H).
const BAR := LeagueSheet.BAR_H

var scroll := 0.0
var content_height := 0.0
## Bound painter from the sheet on screen: `(c, vp, fonts, items, view)`.
var painter: Callable = Callable()
## The current sheet: rows that scroll, and doors that stay where they were put.
var content: Array = []
var pinned: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func max_scroll() -> float:
	return maxf(0.0, content_height - size.y)

func can_scroll() -> bool:
	return max_scroll() > 0.0

func scroll_by(delta: float) -> void:
	scroll_to(scroll + delta)

func scroll_to(at: float) -> void:
	var clamped := clampf(at, 0.0, max_scroll())
	if is_equal_approx(clamped, scroll):
		return
	scroll = clamped
	queue_redraw()

## Take a fresh sheet: the viewport sets the window, the rows set the height and
## a new pose starts at the top of the page. Returns the scrolling rows so the
## screen can bind the painter to them.
func set_sheet(items: Array, vp: Vector2, reset: bool) -> Array:
	position = Vector2(0.0, TOP)
	size = Vector2(vp.x, maxf(vp.y - TOP - BAR, 1.0))
	if reset:
		scroll = 0.0
	content = []
	pinned = []
	var bottom := TOP
	for item in items:
		if bool(item.get("pinned", false)):
			pinned.append(item)
		else:
			content.append(item)
			bottom = maxf(bottom, (item["rect"] as Rect2).end.y)
	content_height = bottom - TOP
	scroll_to(scroll)
	queue_redraw()
	return content

## Every door the screen can press, with the rows moved by the scroll offset and
## the fixed doors left where the layout put them.
func button_rects() -> Array:
	var out: Array = []
	for item in content:
		var copy: Dictionary = item.duplicate()
		var r: Rect2 = item["rect"]
		copy["rect"] = Rect2(r.position.x, r.position.y - scroll, r.size.x, r.size.y)
		out.append(copy)
	out.append_array(pinned)
	return out

## Front-most door under a design point. A row that has scrolled under the
## header or past the bar is not under the pointer any more, so the pointer has
## to be inside the window before a scrolling row can claim it.
func hit(p: Vector2) -> String:
	for i in range(pinned.size() - 1, -1, -1):
		if (pinned[i]["rect"] as Rect2).has_point(p):
			return str(pinned[i]["id"])
	var inside := Rect2(position, size).has_point(p)
	if not inside:
		return ""
	var items := button_rects()
	for i in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[i]
		if str(item["id"]) != "" and (item["rect"] as Rect2).has_point(p):
			return str(item["id"])
	return ""

# gd-tools: no cover start

## The sheets lay out in design coordinates, so the body only has to cancel its
## own offset; `clip_contents` trims what would run under the header or the bar.
func _draw() -> void:
	if painter.is_valid():
		draw_set_transform(Vector2(0.0, -position.y - scroll))
		painter.call(self)

# gd-tools: no cover end
