class_name WikiBodyPaint
extends RefCounted


static func row(body: WikiBody, row: Dictionary, rect: Rect2, hovered: bool) -> void:
	var kind := str(row["k"])
	if kind == "section":
		_section(body, row, rect)
	elif kind == "note":
		_text(body, Vector2(rect.position.x, rect.position.y + 16),
			_clip(str(row["text"]), 130), 10, Color(0.55, 0.64, 0.69), false)
	elif kind == "kv":
		_kv(body, row, rect)
	elif kind == "bar":
		_bar(body, row, rect)
	elif kind == "spark":
		_spark(body, row, rect)
	elif kind == "chip":
		_chip(body, row, rect, hovered)
	elif kind == "thead":
		_thead(body, row, rect)
	elif kind == "trow":
		_trow(body, row, rect, hovered)


static func _section(body: WikiBody, row: Dictionary, rect: Rect2) -> void:
	var section_h: float = WikiBody.SECTION_COMPACT_H if rect.size.y <= WikiBody.SECTION_COMPACT_H \
		else WikiBody.SECTION_H
	body.draw_rect(Rect2(rect.position.x, rect.position.y + section_h * 0.4, 3, 12),
		Color(0.96, 0.78, 0.30))
	_text(body, Vector2(rect.position.x + 12, rect.position.y + section_h * 0.74),
		str(row["text"]), 11, Color(0.55, 0.64, 0.69), true)
	body.draw_line(Vector2(rect.position.x, rect.position.y + section_h - 2.0),
		Vector2(rect.position.x + rect.size.x, rect.position.y + section_h - 2.0),
		Color(1, 1, 1, 0.07), 1)


static func _kv(body: WikiBody, row: Dictionary, rect: Rect2) -> void:
	var items: Array = row["items"]
	var cw: float = rect.size.x / float(row["cols"])
	for i in range(items.size()):
		var item: Array = items[i]
		var x: float = rect.position.x + cw * float(i)
		var big: bool = item.size() > 2 and bool(item[2])
		_text(body, Vector2(x, rect.position.y + 12), str(item[0]), 10, Color(0.55, 0.64, 0.69), true)
		_text(body, Vector2(x, rect.position.y + 28), str(item[1]), 17 if big else 13,
			Color(0.92, 0.95, 0.96), true)


static func _bar(body: WikiBody, row: Dictionary, rect: Rect2) -> void:
	var label := str(row["label"])
	var value := clampf(float(row["value"]), 0.0, 1.0)
	_text(body, Vector2(rect.position.x, rect.position.y + 16), label, 10,
		Color(0.55, 0.64, 0.69), true)
	var bar_x: float = rect.position.x + minf(150.0, rect.size.x * 0.30)
	var bar_w: float = rect.size.x - (bar_x - rect.position.x) - 46.0
	body.draw_rect(Rect2(bar_x, rect.position.y + 8, bar_w, 6), Color(1, 1, 1, 0.07))
	body.draw_rect(Rect2(bar_x, rect.position.y + 8, bar_w * value, 6), Color(0.62, 0.82, 0.86))
	_text(body, Vector2(bar_x + bar_w + 8, rect.position.y + 16),
		str(int(round(value * 100.0))), 12, Color(0.92, 0.95, 0.96), true)


static func _spark(body: WikiBody, row: Dictionary, rect: Rect2) -> void:
	var points: Array = row.get("points", [])
	var clubs: int = maxi(int(row.get("clubs", 0)), 2)
	if points.size() < 2:
		return
	var dim := Color(0.55, 0.64, 0.69)
	_text(body, Vector2(rect.position.x, rect.position.y + 12),
		"BEST " + PreMatchCopy.place(int(row.get("best", 0))), 9, dim, true)
	_text_right(body, rect.end.x, rect.position.y + 12.0,
		"WORST " + PreMatchCopy.place(int(row.get("worst", 0))), 9, dim, true)
	var plot := Rect2(rect.position.x + 22.0, rect.position.y + 24.0,
		maxf(rect.size.x - 22.0 - 48.0, 20.0), maxf(rect.size.y - 36.0, 12.0))
	_text(body, Vector2(rect.position.x, plot.position.y + 8.0), "1", 10, dim, true)
	_text(body, Vector2(rect.position.x, plot.end.y), str(clubs), 10, dim, true)
	body.draw_line(Vector2(plot.position.x, plot.position.y), Vector2(plot.end.x, plot.position.y),
		Color(1, 1, 1, 0.05), 1)
	body.draw_line(Vector2(plot.position.x, plot.end.y), Vector2(plot.end.x, plot.end.y),
		Color(1, 1, 1, 0.05), 1)
	var accent := Color(str(row.get("accent", ""))) if str(row.get("accent", "")) != "" \
		else Color(0.62, 0.82, 0.86)
	var laid: Array = []
	for i in range(points.size()):
		var position: int = clampi(int((points[i] as Dictionary).get("position", 1)), 1, clubs)
		var x: float = plot.position.x + plot.size.x * float(i) / float(points.size() - 1)
		var y: float = plot.position.y + plot.size.y * float(position - 1) / float(clubs - 1)
		laid.append(Vector2(x, y))
	for i in range(1, laid.size()):
		body.draw_line(laid[i - 1], laid[i], accent, 2.0)
	for i in range(laid.size() - 1):
		body.draw_circle(laid[i], 2.0, accent)
	var end: Vector2 = laid[laid.size() - 1]
	body.draw_circle(end, 4.0, UiChrome.C_GOLD)
	body.draw_circle(end, 1.8, Color(0.02, 0.03, 0.04))
	_text(body, Vector2(plot.end.x + 10.0,
		clampf(end.y + 4.0, plot.position.y + 10.0, plot.end.y)),
		PreMatchCopy.place(int(row.get("place", 0))), 12, UiChrome.C_GOLD, true)


static func _chip(body: WikiBody, row: Dictionary, rect: Rect2, hovered: bool) -> void:
	var accent := Color(str(row["accent"])) if str(row["accent"]) != "" else Color(0.35, 0.45, 0.5)
	body.draw_rect(rect, Color(0.075, 0.105, 0.125, 0.95 if not hovered else 1.0), true)
	body.draw_rect(Rect2(rect.position, Vector2(4, rect.size.y)), accent)
	var chip_id := str((row.get("target", {}) as Dictionary).get("id", ""))
	_text(body, Vector2(rect.position.x + 14, rect.position.y + 19),
		WikiChrome.fit(body.f_bold, str(row["text"]), 13, rect.size.x - 22.0), 13,
		UiChrome.C_GOLD if body.followed.has(chip_id) else Color(0.92, 0.95, 0.96), true)


static func _thead(body: WikiBody, row: Dictionary, rect: Rect2) -> void:
	var cols: Array = row["cols"]
	var widths: Array = row["widths"]
	var text_cols: Array = row["text_cols"]
	var x := rect.position.x
	for i in range(cols.size()):
		var cw: float = rect.size.x * float(widths[i])
		if text_cols.has(i) or i == 0:
			_text(body, Vector2(x, rect.position.y + 15), str(cols[i]), 10,
				Color(0.62, 0.72, 0.78), true)
		else:
			_text_right(body, x + cw - 8.0, rect.position.y + 15.0, str(cols[i]), 10,
				Color(0.62, 0.72, 0.78), true)
		x += cw
	body.draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Color(1, 1, 1, 0.10), 1)


static func _trow(body: WikiBody, row: Dictionary, rect: Rect2, hovered: bool) -> void:
	if hovered:
		body.draw_rect(rect, Color(0.075, 0.105, 0.125, 0.75))
	elif int(row.get("index", 0)) % 2 == 1:
		body.draw_rect(rect, Color(1, 1, 1, 0.022))
	var accent := str(row.get("accent", ""))
	if accent != "":
		body.draw_rect(Rect2(rect.position.x, rect.position.y + 3, 2, rect.size.y - 6), Color(accent))
	var widths: Array = row["widths"]
	var cells: Array = row["cells"]
	var x := rect.position.x + 6.0
	var text_cols: Array = row.get("text_cols", [1])
	var dates: Dictionary = row.get("dates", {})
	var mark := int(row.get("club_cell", -1))
	var marked: bool = mark >= 0 and body.followed.has(
		str((row.get("target", {}) as Dictionary).get("id", "")))
	for i in range(cells.size()):
		var cw: float = (rect.size.x - 6.0) * float(widths[i])
		if dates.has(i):
			body.hints.add(Rect2(x, rect.position.y + 2.0, cw, rect.size.y - 4.0), str(dates[i]))
		var ink: Color = UiChrome.C_GOLD if marked and i == mark else Color(0.92, 0.95, 0.96)
		var right: bool = not text_cols.has(i) and i != 0
		if right:
			_text_right(body, x + cw - 8.0, _row_baseline(rect), str(cells[i]), 11, ink,
				i == cells.size() - 1)
		else:
			var bold_cell: bool = i == 1 and cells.size() >= 4
			var font: Font = body.f_bold if bold_cell else body.f_body
			_text(body, Vector2(x, _row_baseline(rect)),
				WikiChrome.fit(font, str(cells[i]), 11, cw - 8.0), 11, ink, bold_cell)
		x += cw
	body.draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y),
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
		Color(1, 1, 1, 0.05), 1)


static func _clip(s: String, max_chars: int) -> String:
	return s if s.length() <= max_chars else s.substr(0, max_chars - 1) + "…"


static func _row_baseline(rect: Rect2) -> float:
	if rect.size.y > 30.0:
		return rect.position.y + rect.size.y * 0.5 + 4.0
	return rect.position.y + 16.0


static func _text(body: WikiBody, pos: Vector2, s: String, size_px: int, color: Color,
		bold: bool) -> void:
	body.draw_string(body.f_bold if bold else body.f_body, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1,
		WikiChrome.text_size(size_px), color)


static func _text_right(body: WikiBody, right_x: float, y: float, s: String, size_px: int,
		color: Color, bold: bool) -> void:
	var font: Font = body.f_bold if bold else body.f_body
	var px := WikiChrome.text_size(size_px)
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	body.draw_string(font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
