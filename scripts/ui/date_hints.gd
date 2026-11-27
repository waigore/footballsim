class_name DateHints
extends RefCounted


const PAD := 7.0

const BUBBLE_H := 17.0

var zones: Array = []
var _seen := {}


func clear() -> void:
	zones.clear()
	_seen.clear()


func add(rect: Rect2, date: String) -> void:
	if date == "" or rect.size.x <= 0.0:
		return
	var key := "%s|%d|%d|%d|%d" % [date, int(rect.position.x), int(rect.position.y),
		int(rect.size.x), int(rect.size.y)]
	if _seen.has(key):
		return
	_seen[key] = true
	zones.append({"rect": rect, "date": date})


func at(p: Vector2) -> Dictionary:
	for i in range(zones.size() - 1, -1, -1):
		if (zones[i]["rect"] as Rect2).has_point(p):
			return zones[i]
	return {}


static func width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, ChromeDensity.read_size(size)).x


static func strip(font: Font, s: String, pos: Vector2, size: int) -> Rect2:
	var px := float(ChromeDensity.read_size(size))
	return Rect2(pos.x, pos.y - px, width(font, s, size), px + 4.0)


static func strip_right(font: Font, s: String, right_x: float, y: float, size: int) -> Rect2:
	var out := strip(font, s, Vector2(right_x, y), size)
	out.position.x -= out.size.x
	return out

# gd-tools: no cover start


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
