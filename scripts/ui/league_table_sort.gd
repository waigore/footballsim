class_name LeagueTableSort
extends RefCounted


const META_SORT := "table_sort"
const META_DIR := "table_dir"
const FULL_COLS := LeagueTableView.FULL_COLS


var key := ""
var dir := -1


func attach(save: LeagueSave) -> void:
	key = ""
	dir = -1
	if save == null:
		return
	var meta := save.read_meta()
	var saved_sort := str(meta.get(META_SORT, ""))
	key = saved_sort if sortable(saved_sort) else ""
	dir = 1 if str(meta.get(META_DIR, "desc")) == "asc" else -1


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


static func sortable(column: String) -> bool:
	if column == "" or column == "position":
		return false
	for col in FULL_COLS:
		if str(col["key"]) == column:
			return true
	return false


static func numeric(cols: Array) -> int:
	var count := 0
	for col in cols:
		if bool(col["num"]):
			count += 1
	return count


static func cell(row: Dictionary, column: String) -> int:
	if column == "gd":
		return int(row.get("gf", 0)) - int(row.get("ga", 0))
	return int(row.get(column, 0))


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
