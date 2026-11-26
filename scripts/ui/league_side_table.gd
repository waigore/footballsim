class_name LeagueSideTable
extends RefCounted

## The season hub's side standings on a wide sheet: the top of the league table
## beside today's plan, on the compact record the TABLE sheet paints (#102).
##
## It was the hub's third row grammar, mixed into the same paint method as the
## plan rows. Here it owns its own geometry — the lane it takes beside the plan,
## and the club column `LeagueColumns` measures for abbreviations — so the hub
## only has to ask where the table starts.
##
## Geometry and paint only: the rows are the season's table, the zones the
## league's rules, and nothing here calls the sim.

## A row of the side table, and the gap the European line gets after sixth.
const ROW_H := 19.0
const EUROPE_GAP := 6.0
## How many places the side table prints.
const ROWS := 20
## The hub's side table shows the club abbreviation, not the full name, so its
## club column needs far less room than the TABLE sheet's (#102). The record
## spreads across the lane instead of leaving a dead gap before points.
const CLUB_MIN := 46.0
const CLUB_SHARE := 0.14

var cache := {}

## The lane the side table occupies beside a plan of the hub's column width.
static func box(vp: Vector2, plan_right: float) -> Rect2:
	var tx := plan_right + 22.0
	return Rect2(tx, 0.0, vp.x - tx - 24.0, ROW_H)

## The column rail: the compact set the TABLE sheet paints, spread across the
## whole lane so the numbers fill it.
static func places(box: Rect2) -> Dictionary:
	return LeagueColumns.of(box, LeagueColumns.COMPACT_COLS, CLUB_MIN, CLUB_SHARE)

## The side table's rows, with the place `i` of every club the season lists.
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

## Paint the column captions above the first row, at `top`. `fonts` is the
## sheet's type set, like every other paint here.
func draw_head(c: CanvasItem, box: Rect2, top: float, fonts: Dictionary) -> void:
	var rail := places(box)
	var bold: Font = fonts["bold"]
	UiChrome.text(c, Vector2(float(rail["club_x"]), top + 16.0), "CLUB", 10, UiChrome.C_DIM, bold)
	for col in rail["cols"]:
		UiChrome.text_r(c, float(col["right"]), top + 16.0, str(col["label"]), 10,
			UiChrome.C_DIM, bold)

## Paint the side-table rows this module laid out.
func draw(c: CanvasItem, items: Array, fonts: Dictionary, names: InterestNames) -> void:
	for item in items:
		LeaguePlanRows.paint_table_row(c, item["rect"], item["row"], str(item["zone"]),
			item["places"], bool(item.get("interested", false)), fonts, names)

# gd-tools: no cover end
