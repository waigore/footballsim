class_name InterestNames
extends RefCounted

## The strips a sheet paints team names in (#107), so the long press can say
## which club is under the pointer without measuring a row twice.
##
## Painters register the strip they just wrote, exactly like `DateHints` does for
## dates: the registry is cleared when a sheet lays itself out again and a
## repaint that did not move a strip does not grow the list. Strips live in the
## space their painter draws in — content space inside a scrolling body — and the
## surface shifts the pointer by its own scroll before asking.

var zones: Array = []
var _seen := {}

## Forget every strip: a sheet that painted again starts from nothing.
func clear() -> void:
	zones.clear()
	_seen.clear()

## Register the strip a club name occupies. An empty club id (a row whose club is
## unknown) registers nothing.
func add(rect: Rect2, club_id: String) -> void:
	if club_id == "" or rect.size.x <= 0.0:
		return
	var key := "%s|%d|%d|%d|%d" % [club_id, int(rect.position.x), int(rect.position.y),
		int(rect.size.x), int(rect.size.y)]
	if _seen.has(key):
		return
	_seen[key] = true
	zones.append({"rect": rect, "club_id": club_id})

## The club whose strip is under a point, top-most first.
func at(p: Vector2) -> String:
	for i in range(zones.size() - 1, -1, -1):
		if (zones[i]["rect"] as Rect2).has_point(p):
			return str(zones[i]["club_id"])
	return ""

## The strip a caption occupies. Both the width and the strip use the size the
## caption really paints at (the non-match reading floor).
static func width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, ChromeDensity.read_size(size)).x

## Paint one club name and register the strip it occupies, so paint and the long
## press can never disagree about where a name is. Returns the ink's width, so the
## caller lays the next run after it (#107).
static func run(c: CanvasItem, names: InterestNames, club_id: String, s: String,
		at: Vector2, size: int, ink: Color, font: Font) -> float:
	UiChrome.text(c, at, s, size, ink, font)
	if names != null:
		names.add(strip(font, s, at.x, at.y, size), club_id)
	return width(font, s, size)

## The strip a club abbreviation drawn from `x` occupies, one line tall.
static func strip(font: Font, s: String, x: float, baseline: float, size: int) -> Rect2:
	var px := float(ChromeDensity.read_size(size))
	return Rect2(x, baseline - px, maxf(width(font, s, size), 12.0), px + 4.0)
