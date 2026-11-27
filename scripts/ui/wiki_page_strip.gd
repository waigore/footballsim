class_name WikiPageStrip
extends RefCounted


const H := 26.0
const GAP := 6.0
const MIN_W := 62.0
const PAD := 22.0
const SIZE := 12


static func items(page: Dictionary) -> Array:
	var out: Array = []
	for block in page.get("blocks", []):
		if bool((block as Dictionary).get("strip", false)):
			out.append_array(block.get("items", []))
	return out


static func _width_for(font: Font, text: String) -> float:
	var px := WikiChrome.text_size(SIZE)
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + PAD


static func _total(font: Font, chips: Array, key: String) -> float:
	var sum := 0.0
	for chip in chips:
		sum += maxf(_width_for(font, str((chip as Dictionary).get(key, ""))), MIN_W) + GAP
	return sum - GAP


static func layout(font: Font, width: float, chips: Array) -> Dictionary:
	if chips.is_empty():
		return {"rects": [], "short": false}
	var usable: float = maxf(width, MIN_W)
	var short := false
	if _total(font, chips, "text") > usable:
		short = _total(font, chips, "short") <= usable
		if not short:
			return {"rects": _equal_row(usable, chips.size()), "short": true}
	var key := "short" if short else "text"
	var out: Array = []
	var x := 0.0
	for chip in chips:
		var w: float = clampf(_width_for(font, str((chip as Dictionary).get(key, ""))), MIN_W, usable)
		out.append(Rect2(x, 0.0, w, H))
		x += w + GAP
	return {"rects": out, "short": short}


static func _equal_row(width: float, count: int) -> Array:
	var out: Array = []
	var w: float = (width - GAP * float(count - 1)) / float(maxi(count, 1))
	for i in range(count):
		out.append(Rect2(float(i) * (w + GAP), 0.0, maxf(w, 1.0), H))
	return out


static func height(has_strip: bool) -> float:
	return H if has_strip else 0.0


static func label_for(font: Font, chip: Dictionary, width: float, short: bool) -> String:
	var text := str(chip.get("short" if short else "text", ""))
	return WikiChrome.fit(font, text, SIZE, width - PAD + 4.0)


static func paint(c: CanvasItem, font: Font, origin: Vector2, rects: Array, chips: Array,
		followed: Dictionary, mouse: Vector2, short: bool) -> void:
	for i in range(mini(rects.size(), chips.size())):
		var local: Rect2 = rects[i]
		var rect := Rect2(local.position.x + origin.x, local.position.y + origin.y,
			local.size.x, local.size.y)
		var chip: Dictionary = chips[i]
		var accent := Color(str(chip["accent"])) if str(chip.get("accent", "")) != "" \
			else Color(0.35, 0.45, 0.5)
		WikiChrome.chip(c, font, rect, label_for(font, chip, rect.size.x, short), accent,
			followed.has(str((chip.get("target", {}) as Dictionary).get("id", ""))),
			rect.has_point(mouse))


static func doors(origin: Vector2, rects: Array, chips: Array) -> Array:
	var out: Array = []
	for i in range(mini(rects.size(), chips.size())):
		var target: Dictionary = (chips[i] as Dictionary).get("target", {})
		if target.is_empty():
			continue
		var local: Rect2 = rects[i]
		out.append({
			"id": "page:%s:%s" % [str(target.get("page", "")), str(target.get("id", ""))],
			"rect": Rect2(local.position.x + origin.x, local.position.y + origin.y,
				local.size.x, local.size.y),
		})
	return out
