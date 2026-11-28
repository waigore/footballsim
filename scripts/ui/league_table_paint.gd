class_name LeagueTablePaint
extends RefCounted


const ZONE_BAND_W := 4.0


# gd-tools: no cover start

static func draw_body(c: CanvasItem, fonts: Dictionary, items: Array, mode: String,
		cache: Dictionary, strips: InterestNames = null) -> void:
	if strips != null:
		strips.clear()
	for item in items:
		var kind := str(item["kind"])
		if kind == "table_row":
			draw_row(c, item["rect"], item, fonts, mode, cache, strips)
		elif kind == "head":
			LeagueTableHead.draw(c, item["rect"], item, fonts, mode == LeagueTableLayout.COMPACT)
		elif kind == "caption":
			draw_caption(c, item, fonts)
		elif kind == "chip":
			draw_chip(c, item, fonts, cache)


static func draw_caption(c: CanvasItem, item: Dictionary, fonts: Dictionary) -> void:
	var cap: Rect2 = item["rect"]
	if item.has("right"):
		UiChrome.text_r(c, float(item["right"]), cap.position.y + 8.0, str(item["label"]), 7,
			UiChrome.C_DIM, fonts["bold"])
	else:
		UiChrome.text(c, Vector2(cap.position.x + 2.0, cap.position.y + 8.0),
			str(item["label"]), 7, UiChrome.C_DIM, fonts["bold"])


static func draw_chip(c: CanvasItem, item: Dictionary, fonts: Dictionary,
		cache: Dictionary) -> void:
	var on := bool(item.get("selected", false))
	UiChrome.panel(c, cache, item["rect"],
		UiChrome.C_GOLD.darkened(0.1) if on else UiChrome.C_PANEL, 5,
		UiChrome.C_GOLD if on else UiChrome.C_BORDER, 1)
	UiChrome.text_c(c, (item["rect"] as Rect2).get_center().x,
		(item["rect"] as Rect2).position.y + 16.0, str(item["label"]), 10,
		Color(0.06, 0.06, 0.05) if on else UiChrome.C_SOFT, fonts["bold"])


static func draw_row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary,
		mode: String, cache: Dictionary, strips: InterestNames = null) -> void:
	var row: Dictionary = item["row"]
	var band := str(item["zone"])
	if band != "":
		c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, ZONE_BAND_W, rect.size.y - 4.0),
			LeagueChrome.zone_color(band))
	var places: Dictionary = item["places"]
	var y := rect.position.y + rect.size.y * 0.5 + 4.0
	UiChrome.text(c, Vector2(float(places["pos_x"]), y), "%d" % int(row["position"]), 10,
		UiChrome.C_DIM, fonts["med"])
	var size: int = 12 if mode == LeagueTableLayout.COMPACT else 11
	var club_x: float = float(places["club_x"])
	var label: String = LeagueColumns.fit_name(LeagueColumns.club_label(row), fonts["bold"], size,
		float(places["club_w"]))
	UiChrome.text(c, Vector2(club_x, y), label, size,
		UiChrome.C_GOLD if bool(item.get("interested", false)) else UiChrome.C_TEXT, fonts["bold"])
	if strips != null:
		strips.add(InterestNames.strip(fonts["bold"], label, club_x, y, size), str(row["club_id"]))
	for col in places["cols"]:
		if bool(col.get("form", false)):
			LeagueFormColumns.draw(c, cache, col, rect, item.get("form", []), fonts)
			continue
		var key := str(col["key"])
		var points := key == "points"
		UiChrome.text_r(c, float(col["right"]), y, LeagueColumns.text(row, key), 10 if points else 9,
			UiChrome.C_TEXT if points else UiChrome.C_SOFT, fonts["bold"] if points else fonts["med"])

# gd-tools: no cover end
