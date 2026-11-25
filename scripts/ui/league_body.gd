class_name LeagueBody
extends Control

## Scroll window for the league sheets. It clips the season content to the band
## between the header and the bottom bar, owns the scroll offset (both axes) that
## the hit test and the painted rows must share, and hands the paint to the sheet
## that laid the rows out. The doors a sheet pins (the header band's BACK and
## primary door, the bottom bar's reading doors) are its paint too: they are not
## clipped, and they cover the rows underneath them, exactly like the encyclopedia's
## body sits under its own header.

## Sheet chrome above the content (LeagueChrome.HEADER).
const TOP := LeagueChrome.HEADER
## Bottom action bar under the content (LeagueChrome.BAR_H).
const BAR := LeagueChrome.BAR_H

var scroll := 0.0
## Sideways offset for a sheet wider than the window (the full table on a phone).
var hscroll := 0.0
## Bottom chrome reserved by the pose on screen: the table's reading doors and
## the podium's exits need it; the panel-era hub, calendar and reports do not.
var bottom_bar := BAR
var content_height := 0.0
## Content width including its right margin, from the window's left edge.
var content_width := 0.0
## Bound painter from the sheet on screen: `(c, vp, fonts, items, view)`.
var painter: Callable = Callable()
## The font set the painter and the pinned doors draw with, refreshed by the
## screen on every layout.
var fonts: Dictionary = {}
## The sheet's style cache for the pinned doors: the body builds one when nobody
## hands it the host's, so a bare body in a test still paints its buttons.
var cache: Dictionary = {}
## The live pause: set by a modal layer (the load list's delete question, the
## long-press menu) so the body draws the sheet but its doors go quiet.
var frozen := false
## The current sheet: rows that scroll, and doors that stay where they were put.
var content: Array = []
var pinned: Array = []
## The host above the sheet: a leftover watched match takes a slice of its
## engine each frame from here (#100).
var host: LeagueHost = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

## The season sheet paints every frame it is up, so the leftover match rides the
## same frame instead of needing a ticker of its own.
func _process(_delta: float) -> void:
	if host != null and host.watch != null:
		host.watch.tick()

func max_scroll() -> float:
	return maxf(0.0, content_height - size.y)

func can_scroll() -> bool:
	return max_scroll() > 0.0

func max_hscroll() -> float:
	return maxf(0.0, content_width - size.x)

func scroll_by(delta: float) -> void:
	scroll_to(scroll + delta)

func scroll_to(at: float) -> void:
	var clamped := clampf(at, 0.0, max_scroll())
	if is_equal_approx(clamped, scroll):
		return
	scroll = clamped
	queue_redraw()

func hscroll_to(at: float) -> void:
	var clamped := clampf(at, 0.0, max_hscroll())
	if is_equal_approx(clamped, hscroll):
		return
	hscroll = clamped
	queue_redraw()

## A drag or a trackpad pan moves the sheet on both axes: the table is wider
## than a phone in its full reading and taller than any window.
func pan_by(delta: Vector2) -> void:
	scroll_to(scroll + delta.y)
	hscroll_to(hscroll + delta.x)

## Take a fresh sheet: the viewport sets the window, the rows set the height and
## a new pose starts at the top of the page. `bar` is the bottom chrome the pose
## reserves; it defaults to the fixed action bar of the older sheets. Returns
## the scrolling rows so the screen can bind the painter to them.
func set_sheet(items: Array, vp: Vector2, reset: bool, bar: float = -1.0) -> Array:
	if bar >= 0.0:
		bottom_bar = bar
	position = Vector2(0.0, TOP)
	size = Vector2(vp.x, maxf(vp.y - TOP - bottom_bar, 1.0))
	# The rows are replaced every refresh; only a new pose also returns to the
	# top-left corner. Keeping the old rows made every same-pose refresh stack
	# another copy of the sheet.
	content = []
	pinned = []
	if reset:
		scroll = 0.0
		hscroll = 0.0
	var bottom := TOP
	var right := 0.0
	for item in items:
		if bool(item.get("pinned", false)):
			pinned.append(item)
			continue
		content.append(item)
		var rect: Rect2 = item["rect"]
		bottom = maxf(bottom, rect.end.y)
		right = maxf(right, rect.end.x)
	content_height = bottom - TOP
	content_width = right + 24.0
	scroll_to(scroll)
	hscroll_to(hscroll)
	queue_redraw()
	return content

## Every door the screen can press, with the rows moved by the scroll offset and
## the fixed doors left where the layout put them.
func button_rects() -> Array:
	var out: Array = []
	for item in content:
		var copy: Dictionary = item.duplicate()
		var r: Rect2 = item["rect"]
		copy["rect"] = Rect2(r.position.x - hscroll, r.position.y - scroll, r.size.x, r.size.y)
		out.append(copy)
	out.append_array(pinned)
	return out

## Front-most door under a design point: the pinned doors first (they are painted
## over the clip), then the rows. A row that has scrolled under the header or past
## the bar is not under the pointer any more, so the pointer has to be inside the
## window before a scrolling row can claim it. A frozen body answers nothing: a
## modal layer owns the click while it is up.
func hit(p: Vector2) -> String:
	if frozen:
		return ""
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

## Layers, bottom to top: the sheet's scrolling rows (offset and clipped by
## `clip_contents`), then the doors it pins — which are laid out in screen space,
## so they are painted after the offset is cancelled and cover the clip.
func _draw() -> void:
	if painter.is_valid():
		draw_set_transform(Vector2(-hscroll, -position.y - scroll))
		painter.call(self)
		draw_set_transform(Vector2.ZERO)
	for item in pinned:
		_door(item)

func _door(item: Dictionary) -> void:
	LeagueChrome.pinned_door(self, cache, item, fonts)

# gd-tools: no cover end
