class_name LeagueSideTable
extends RefCounted


const ROW_H := 19.0
const EUROPE_GAP := 6.0

const ROWS := 20


const CLUB_MIN := 100.0
const CLUB_SHARE := 0.24

var cache := {}


static func box(vp: Vector2, plan_right: float) -> Rect2:
	var tx := plan_right + 22.0
	return Rect2(tx, 0.0, vp.x - tx - 24.0, ROW_H)


static func places(box: Rect2) -> Dictionary:
	return LeagueColumns.of(box, LeagueColumns.COMPACT_COLS, CLUB_MIN, CLUB_SHARE)


static func layout(rows: Array, rules: Dictionary, interest: Dictionary, box: Rect2,
		top: float) -> Array:
	var items: Array = []
	var rail := places(box)
	var y := top
	for i in range(mini(rows.size(), ROWS)):
		if i == 6:
			y += EUROPE_GAP
		var row: Dictionary = rows[i]
		var club := str(row["club_id"])
		items.append({
			"id": "club:" + club, "kind": "table_row",
			"rect": Rect2(box.position.x, y, box.size.x, ROW_H), "row": row,
			"zone": LeagueRules.zone(int(row["position"]), rules),
			"places": rail, "interested": interest.has(club),
		})
		y += ROW_H
	return items

# gd-tools: no cover start


func draw_head(c: CanvasItem, box: Rect2, top: float, fonts: Dictionary) -> void:
	var rail := places(box)
	var bold: Font = fonts["bold"]
	UiChrome.text(c, Vector2(float(rail["club_x"]), top + 16.0), "CLUB", 10, UiChrome.C_DIM, bold)
	for col in rail["cols"]:
		UiChrome.text_r(c, float(col["right"]), top + 16.0, str(col["label"]), 10,
			UiChrome.C_DIM, bold)


func draw(c: CanvasItem, items: Array, fonts: Dictionary, names: InterestNames) -> void:
	for item in items:
		LeaguePlanRows.paint_table_row(c, item["rect"], item["row"], str(item["zone"]),
			item["places"], bool(item.get("interested", false)), fonts, names)

# gd-tools: no cover end
