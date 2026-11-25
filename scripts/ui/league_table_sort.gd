class_name LeagueTableSort
extends RefCounted

## The TABLE sheet's ordering rules: which columns may sort, what one row's value
## is for a column, and the player's chosen order with the official place kept as
## the tie-break. Split out of `LeagueTableView` so the paint and geometry module
## stays inside its line budget.

## Keys a header can sort by: every visible field except the official place.
static func sortable(key: String) -> bool:
	if key == "" or key == "position":
		return false
	for col in LeagueTableView.FULL_COLS:
		if str(col["key"]) == key:
			return true
	return false

## A row's value for one column. Goal difference is derived, the club column
## sorts by name, everything else is a saved integer.
static func cell(row: Dictionary, key: String) -> int:
	if key == "gd":
		return int(row.get("gf", 0)) - int(row.get("ga", 0))
	return int(row.get(key, 0))

static func numeric(cols: Array) -> int:
	var count := 0
	for col in cols:
		if bool(col["num"]):
			count += 1
	return count

static func shown(mode: String, key: String) -> bool:
	for col in LeagueTableView.columns(mode):
		if str(col["key"]) == key:
			return true
	return false

## Rows in the player's chosen order, each keeping its official position. Ties
## fall back to the official place so a re-sort is never arbitrary. A sort on a
## column the current reading does not show is left for the reading that does.
static func order(rows: Array, sort: String, dir: int, mode: String) -> Array:
	if sort == "" or rows.size() < 2 or not shown(mode, sort):
		return rows
	var out := rows.duplicate()
	var key := sort
	var sign := dir
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if key == "club":
			var na := str(a["club_name"])
			var nb := str(b["club_name"])
			if na != nb:
				return na < nb if sign > 0 else na > nb
		else:
			var va := cell(a, key)
			var vb := cell(b, key)
			if va != vb:
				return va < vb if sign > 0 else va > vb
		return int(a["position"]) < int(b["position"])
	)
	return out
