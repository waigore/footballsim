class_name LeagueTableSort
extends RefCounted

## How the table orders its rows (#72/#74): the player's chosen column and
## direction, remembered per save, and the reading each choice is legal in.
##
## Sorting never renumbers the league: the table keeps every row's official
## `position` and only reorders the list, so the `#` column and the zone bands
## always show the real place (the list order is the player's, the numbers are
## the league's).
##
## The chance lives in the save's `save_meta`, so leaving the sheet or reopening
## the save brings them back. It sits beside `LeagueTableView` because the table
## asks it what it may sort and how; the table still lays the rows out.

const META_SORT := "table_sort"
const META_DIR := "table_dir"
const FULL_COLS := LeagueTableView.FULL_COLS

## Sorted column ("" is the official order) and direction (1 asc, -1 desc).
var key := ""
var dir := -1

## Take the sort and direction one save remembers. Called when the table opens,
## so two saves never share one table's choices.
func attach(save: LeagueSave) -> void:
	key = ""
	dir = -1
	if save == null:
		return
	var meta := save.read_meta()
	var saved_sort := str(meta.get(META_SORT, ""))
	key = saved_sort if sortable(saved_sort) else ""
	dir = 1 if str(meta.get(META_DIR, "desc")) == "asc" else -1

## A header press: a new first sort on that column, or the reverse of the one
## already on it. Writes the choice through to the save so it is the save's, not
## this run's, and returns true when the press changed anything.
func press(column: String, save: LeagueSave) -> bool:
	if not sortable(column):
		return false
	if column == key:
		dir = -dir
	else:
		key = column
		dir = 1 if column == "club" else -1
	_store(save, META_SORT, key)
	_store(save, META_DIR, "asc" if dir > 0 else "desc")
	return true

func _store(save: LeagueSave, meta_key: String, value: String) -> void:
	if save != null:
		save.put_meta(meta_key, value)

## Keys a header can sort by: every visible field except the official place.
static func sortable(column: String) -> bool:
	if column == "" or column == "position":
		return false
	for col in FULL_COLS:
		if str(col["key"]) == column:
			return true
	return false

## How many columns are number boxes: the rail width walks them.
static func numeric(cols: Array) -> int:
	var count := 0
	for col in cols:
		if bool(col["num"]):
			count += 1
	return count

## A row's value for one column. Goal difference is derived, the club column
## sorts by name, everything else is a saved integer.
static func cell(row: Dictionary, column: String) -> int:
	if column == "gd":
		return int(row.get("gf", 0)) - int(row.get("ga", 0))
	return int(row.get(column, 0))

## How many number boxes a column set carries (geometry for the full sheet).
static func numeric(cols: Array) -> int:
	var count := 0
	for col in cols:
		if bool(col["num"]):
			count += 1
	return count

## Rows in the player's chosen order, each keeping its official position. Ties
## fall back to the official place so a re-sort is never arbitrary. A sort on a
## column the current reading does not show is left for the reading that does:
## the compact strip never sorts by a number the player cannot see.
func ordered(rows: Array, shown: Array) -> Array:
	if key == "" or rows.size() < 2 or not _shown(shown):
		return rows
	var out := rows.duplicate()
	var column := key
	var sign := dir
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if column == "club":
			var na := str(a["club_name"])
			var nb := str(b["club_name"])
			if na != nb:
				return na < nb if sign > 0 else na > nb
		else:
			var va := cell(a, column)
			var vb := cell(b, column)
			if va != vb:
				return va < vb if sign > 0 else va > vb
		return int(a["position"]) < int(b["position"])
	)
	return out

func _shown(columns: Array) -> bool:
	for col in columns:
		if str(col["key"]) == key:
			return true
	return false
