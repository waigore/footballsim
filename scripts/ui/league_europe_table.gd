class_name LeagueEuropeTable
extends RefCounted


const KINDS := ["eu_legend", "eu_head", "eu_row"]

const ROW_H := 22.0
const ROW_TOUCH_H := 44.0

const MIN_ROW_W := 404.0
const MIN_CLUB_W := 60.0


static func layout(vp: Vector2, view: Dictionary, y: float) -> Array:
	var touch := bool(view.get("touch", false))
	var rows: Array = view.get("table", [])
	var row_w: float = maxf(vp.x - 48.0, MIN_ROW_W)
	var out: Array = []
	out.append({"id": "", "kind": "eu_legend",
		"rect": Rect2(24.0, y, row_w, 16.0)})
	y += 18.0
	if rows.is_empty():
		out.append({"id": "", "kind": "note",
			"label": "THE LEAGUE PHASE OPENS AFTER THE PLAY-OFF ROUND",
			"rect": Rect2(24.0, y, row_w, 20.0)})
		return out
	out.append({"id": "", "kind": "eu_head", "rect": Rect2(24.0, y, row_w, 18.0)})
	y += 20.0
	var h: float = ROW_TOUCH_H if touch else ROW_H
	var interest := LeagueInterestMark.set_of(view.get("interests", []))
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var position := int(row.get("position", i + 1))
		out.append({"id": "club:" + str(row.get("club_id", "")), "kind": "eu_row", "row": row,
			"zone": LeagueUefaLeaguePhase.zone(position),
			"interested": interest.has(str(row.get("club_id", ""))),
			"rect": Rect2(24.0, y + float(i) * h, row_w, h - 1.0)})
	return out

# gd-tools: no cover start


static func places(rect: Rect2) -> Dictionary:
	return LeagueColumns.of(rect, LeagueColumns.COMPACT_COLS, MIN_CLUB_W)


static func paint(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary,
		names: InterestNames) -> void:
	match str(item.get("kind", "")):
		"eu_legend":
			_legend(c, rect, fonts["bold"])
		"eu_head":
			_head(c, rect, fonts["bold"])
		"eu_row":
			_row(c, rect, item, fonts, names)


static func _legend(c: CanvasItem, rect: Rect2, bold: Font) -> void:
	var parts := [["1–8 R16", "r16"], ["9–24 KO PLAY-OFF", "kopo"], ["25–36 OUT", "out"]]
	var x := rect.position.x
	for part in parts:
		UiChrome.text(c, Vector2(x, rect.position.y + 11.0), str(part[0]), 8,
			LeagueChrome.zone_color(str(part[1])), bold)
		x += UiChrome.text_width(bold, str(part[0]), 8) + 12.0


static func _head(c: CanvasItem, rect: Rect2, bold: Font) -> void:
	var rig := places(rect)
	UiChrome.text(c, Vector2(float(rig["pos_x"]), rect.position.y + 12.0), "#", 8,
		UiChrome.C_DIM, bold)
	UiChrome.text(c, Vector2(float(rig["club_x"]), rect.position.y + 12.0), "CLUB", 8,
		UiChrome.C_DIM, bold)
	for col in rig["cols"]:
		UiChrome.text_r(c, float(col["right"]), rect.position.y + 12.0, str(col["label"]), 8,
			UiChrome.C_DIM, bold)


static func _row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary,
		names: InterestNames) -> void:
	var row: Dictionary = item["row"]
	c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, 3.0, rect.size.y - 4.0),
		LeagueChrome.zone_color(str(item.get("zone", ""))))
	var rig := places(rect)
	var y := rect.position.y + rect.size.y * 0.5 + 4.0
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	UiChrome.text(c, Vector2(float(rig["pos_x"]), y), "%d" % int(row.get("position", 0)), 9,
		UiChrome.C_DIM, med)
	var name: String = LeagueColumns.fit_name(LeagueColumns.club_label(row), bold, 11,
		float(rig["club_w"]))
	InterestNames.run(c, names, str(row.get("club_id", "")), name,
		Vector2(float(rig["club_x"]), y), 11,
		UiChrome.C_GOLD if bool(item.get("interested", false)) else UiChrome.C_TEXT, bold)
	for col in rig["cols"]:
		var key := str(col["key"])
		var points := key == "points"
		UiChrome.text_r(c, float(col["right"]), y, LeagueColumns.text(row, key), 9 if not points else 10,
			UiChrome.C_TEXT if points else UiChrome.C_SOFT, bold if points else med)

# gd-tools: no cover end
