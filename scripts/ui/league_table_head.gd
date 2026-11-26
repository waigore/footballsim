class_name LeagueTableHead
extends RefCounted

## The league table's column band: the sort captions (`#`, `CLUB`, the record)
## that ride above the rows, and the group labels the full reading puts over the
## overall, home and away splits.
##
## It sits beside `LeagueTableView` and owns the half of it that is band geometry
## rather than rows: the table still owns the reading, the sort and the press;
## this module only says where the band goes and how it is painted.
##
## On a touch sheet the band is a row-height handhold (#204): a header press is a
## sort — the table's other action — and a 12-unit line of type is not something a
## thumb can aim at. On a desktop sheet it stays the one-line caption it was.

## A desktop band: one caption line above one line of rows.
const CAPTION_H := 12.0
## The handhold a touch band gets: the same 48 density points a club row gets.
const TAP_H := 48.0
## The group labels (OVERALL / HOME / AWAY) sit in their own line above it.
const GROUPS_H := 12.0
## Air between the band and the first row.
const GAP := 4.0

## How tall the band answers to on this pose: a thumb-sized handhold on touch,
## the caption line on desktop (#204).
static func height(touch: bool) -> float:
	return TAP_H if touch else CAPTION_H

## Top of the band: under the sheet header, and under the group labels when the
## full reading prints them. `offset` is air the sheet reserves above the band
## for its own chips (the table's league tabs).
static func top(full: bool, offset: float = 0.0) -> float:
	return LeagueChrome.HEADER + offset + 6.0 + (GROUPS_H if full else 0.0)

## First row below the band.
static func rows_top(full: bool, touch: bool, offset: float = 0.0) -> float:
	return top(full, offset) + height(touch) + GAP

## The band's cells, in paint order: the place, the club, then one per number
## column on the rail `places` measured.
static func cells(places: Dictionary, full: bool, sort: String, touch: bool,
		offset: float = 0.0) -> Array:
	var items: Array = []
	var y := top(full, offset)
	var band := height(touch)
	if full:
		items.append_array(captions(places, y - GROUPS_H))
	items.append(cell(y, float(places["pos_x"]), 20.0, "#", "", false, sort, band))
	items.append(cell(y, float(places["club_x"]), float(places["club_w"]),
		"CLUB", "club", false, sort, band))
	for col in places["cols"]:
		items.append(cell(y, float(col["right"]) - float(col["w"]), float(col["w"]),
			str(col["label"]), str(col["key"]), true, sort, band))
	return items

static func captions(places: Dictionary, y: float) -> Array:
	var out: Array = []
	var bands: Array = []
	for col in places["cols"]:
		var group := str(col["group"])
		if group == "":
			continue
		var left := float(col["right"]) - float(col["w"])
		if bands.is_empty() or str(bands[bands.size() - 1]["label"]) != group:
			bands.append({"label": group, "left": left, "right": float(col["right"])})
		else:
			bands[bands.size() - 1]["right"] = float(col["right"])
	for band in bands:
		out.append({"id": "", "kind": "caption", "label": str(band["label"]),
			"rect": Rect2(float(band["left"]), y, float(band["right"]) - float(band["left"]), 11.0)})
	return out

static func cell(y: float, x: float, w: float, label: String, key: String,
		right_align: bool, sort: String, band_h: float) -> Dictionary:
	var id: String = "" if key == "" else "tbl:sort:" + key
	return {"id": id, "kind": "head", "label": label, "align_right": right_align,
		"sorted": key != "" and key == sort, "rect": Rect2(x, y, w, band_h)}

# gd-tools: no cover start

## One header cell. A desktop band paints its caption at the top of the strip; a
## touch band centres it in the handhold and hangs the sorted rule under the
## glyphs, clear of the row below (#204).
static func draw(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary,
		compact: bool) -> void:
	var size: int = 9 if compact else 8
	var colour: Color = UiChrome.C_GOLD if bool(item["sorted"]) else UiChrome.C_DIM
	var tall: bool = rect.size.y > 20.0
	var y: float = rect.position.y + rect.size.y * 0.5 + float(size) * 0.36 if tall \
		else rect.position.y + float(size) + 1.0
	if bool(item["align_right"]):
		UiChrome.text_r(c, rect.end.x, y, str(item["label"]), size, colour, fonts["bold"])
	else:
		UiChrome.text(c, Vector2(rect.position.x, y), str(item["label"]), size, colour, fonts["bold"])
	if bool(item["sorted"]):
		var rule_y: float = y + 3.0 if tall else rect.end.y - 1.0
		c.draw_rect(Rect2(rect.position.x, rule_y, rect.size.x, 1.0), UiChrome.C_GOLD)

# gd-tools: no cover end
