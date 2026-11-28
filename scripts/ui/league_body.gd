class_name LeagueBody
extends Control


const TOP := LeagueChrome.HEADER

const BAR := LeagueChrome.BAR_H

var scroll := 0.0

var hscroll := 0.0


var bottom_bar := BAR
var content_height := 0.0

var content_width := 0.0

var painter: Callable = Callable()


var frozen := false


var content: Array = []
var pinned: Array = []


var host: LeagueHost = null

var cue := false

var cue_font: Font = null

const CUE_H := 30.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


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


func pan_by(delta: Vector2) -> void:
	scroll_to(scroll + delta.y)
	hscroll_to(hscroll + delta.x)


func set_sheet(items: Array, vp: Vector2, reset: bool, bar: float = -1.0) -> Array:
	if bar >= 0.0:
		bottom_bar = bar
	position = Vector2(0.0, TOP)
	size = Vector2(vp.x, maxf(vp.y - TOP - bottom_bar, 1.0))


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


func button_rects() -> Array:
	var out: Array = []
	for item in content:
		var copy: Dictionary = item.duplicate()
		var r: Rect2 = item["rect"]
		copy["rect"] = Rect2(r.position.x - hscroll, r.position.y - scroll, r.size.x, r.size.y)
		out.append(copy)
	out.append_array(pinned)
	return out


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

func more_below() -> bool:
	return cue and can_scroll() and scroll < max_scroll() - 0.5

# gd-tools: no cover start


func _draw() -> void:
	if painter.is_valid():
		draw_set_transform(Vector2(-hscroll, -position.y - scroll))
		painter.call(self)
		draw_set_transform(Vector2.ZERO)
	if not more_below():
		return
	_draw_cue()


func _draw_cue() -> void:
	var h := CUE_H
	var top := size.y - h
	for i in range(5):
		var t := float(i) / 5.0
		draw_rect(Rect2(0.0, top + float(i) * h / 5.0, size.x, h / 5.0 + 1.0),
			Color(0.012, 0.020, 0.026, 0.94 * t))
	var font: Font = cue_font if cue_font != null else UiChrome.fonts()["bold"]
	var rule_w := 22.0
	var cx := size.x * 0.5
	draw_rect(Rect2(cx - rule_w * 0.5, size.y - 4.0, rule_w, 2.0), Color(0.96, 0.78, 0.30, 0.85))
	var label := "MORE BELOW"
	var at := Vector2(cx - UiChrome.text_width(font, label, 10) * 0.5, size.y - 8.0)
	UiChrome.text(self, at, label, 10, UiChrome.C_GOLD, font)

# gd-tools: no cover end
