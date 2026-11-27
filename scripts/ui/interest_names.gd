class_name InterestNames
extends RefCounted


var zones: Array = []
var _seen := {}


func clear() -> void:
	zones.clear()
	_seen.clear()


func add(rect: Rect2, club_id: String) -> void:
	if club_id == "" or rect.size.x <= 0.0:
		return
	var key := "%s|%d|%d|%d|%d" % [club_id, int(rect.position.x), int(rect.position.y),
		int(rect.size.x), int(rect.size.y)]
	if _seen.has(key):
		return
	_seen[key] = true
	zones.append({"rect": rect, "club_id": club_id})


func at(p: Vector2) -> String:
	for i in range(zones.size() - 1, -1, -1):
		if (zones[i]["rect"] as Rect2).has_point(p):
			return str(zones[i]["club_id"])
	return ""


static func width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, ChromeDensity.read_size(size)).x


static func run(c: CanvasItem, names: InterestNames, club_id: String, s: String,
		at: Vector2, size: int, ink: Color, font: Font) -> float:
	UiChrome.text(c, at, s, size, ink, font)
	if names != null:
		names.add(strip(font, s, at.x, at.y, size), club_id)
	return width(font, s, size)


static func strip(font: Font, s: String, x: float, baseline: float, size: int) -> Rect2:
	var px := float(ChromeDensity.read_size(size))
	return Rect2(x, baseline - px, maxf(width(font, s, size), 12.0), px + 4.0)
