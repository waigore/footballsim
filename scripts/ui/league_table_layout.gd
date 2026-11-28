class_name LeagueTableLayout
extends RefCounted


const COMPACT := "compact"
const FULL := "full"
const FORM := "form"

const CLUB_MIN := 150.0
const TAB_H := 30.0


static func columns(reading: String) -> Array:
	if reading == FORM:
		return LeagueFormColumns.FORM_COLS
	return LeagueColumns.FULL_COLS if reading == FULL else LeagueColumns.COMPACT_COLS


static func min_row(reading: String) -> float:
	if reading == COMPACT:
		return LeagueColumns.min_row(LeagueColumns.COMPACT_COLS)
	if reading == FORM:
		return LeagueFormColumns.min_row()
	return LeagueColumns.full_min_row(CLUB_MIN)


static func places(row: Rect2, reading: String) -> Dictionary:
	if reading == COMPACT:
		return LeagueColumns.of(row, LeagueColumns.COMPACT_COLS)
	if reading == FORM:
		return LeagueFormColumns.places(row)
	return LeagueColumns.full_of(row, CLUB_MIN)


static func tabs(comps: Array, current: String, vp: Vector2) -> Array:
	var items: Array = []
	var gap := 8.0
	var w: float = minf(180.0,
		(vp.x - 48.0 - gap * float(comps.size() - 1)) / float(maxi(comps.size(), 1)))
	var x := 24.0
	for comp in comps:
		var cid := str((comp as Dictionary).get("id", ""))
		var on := cid == current
		items.append({"id": "tbl:league:" + cid, "kind": "chip",
			"label": str((comp as Dictionary).get("short", cid)),
			"selected": on, "rect": Rect2(x, LeagueChrome.HEADER + 2.0, w, 24.0)})
		x += w + gap
	return items


static func current_tab(comps: Array, league_tab: String) -> String:
	for comp in comps:
		if str((comp as Dictionary).get("id", "")) == league_tab:
			return league_tab
	return str((comps[0] as Dictionary).get("id", "")) if not comps.is_empty() else ""


static func mode_bar(reading: String, vp: Vector2, touch: bool) -> Array:
	var bar_top := vp.y - LeagueChrome.BAR_H + 6.0
	var bar_h := UiChrome.tap_h(LeagueChrome.BAR_H - 14.0, touch)
	return [
		{"id": "tbl:mode:" + COMPACT, "kind": "button", "label": "COMPACT",
			"pinned": true, "primary": reading == COMPACT,
			"rect": Rect2(24.0, bar_top, 104.0, bar_h)},
		{"id": "tbl:mode:" + FULL, "kind": "button", "label": "FULL",
			"pinned": true, "primary": reading == FULL,
			"rect": Rect2(134.0, bar_top, 78.0, bar_h)},
		{"id": "tbl:mode:" + FORM, "kind": "button", "label": "FORM",
			"pinned": true, "primary": reading == FORM,
			"rect": Rect2(218.0, bar_top, 62.0, bar_h)},
	]


static func form_caption(places: Dictionary, row_w: float, top: float) -> Dictionary:
	return {"id": "", "kind": "caption", "label": LeagueFormColumns.FORM_CAPTION,
		"right": float((places["cols"] as Array)[0]["right"]),
		"rect": Rect2(float(places["club_x"]) - 2.0, top, row_w, LeagueFormColumns.CAPTION_H)}


static func rows(rows_in: Array, places: Dictionary, interest: Dictionary, view: Dictionary,
		top: float, row_h: float, row_w: float) -> Array:
	var items: Array = []
	for i in range(rows_in.size()):
		items.append({
			"id": "club:" + str(rows_in[i]["club_id"]), "kind": "table_row", "row": rows_in[i],
			"zone": LeagueRules.zone(int(rows_in[i]["position"]), view.get("rules", {})),
			"rect": Rect2(24.0, top + float(i) * row_h, row_w, row_h - 1.0), "places": places,
			"interested": interest.has(str(rows_in[i]["club_id"])),
			"form": (rows_in[i] as Dictionary).get("form", []),
		})
	return items
