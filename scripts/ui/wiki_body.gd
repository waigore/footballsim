class_name WikiBody
extends Control


const MARGIN := 6.0
const COMPACT_MARGIN := 0.0
const GAP := 14.0
const COMPACT_GAP := 6.0
const SECTION_H := 30.0
const SECTION_COMPACT_H := 18.0
const NOTE_H := 24.0
const KV_H := 34.0
const BAR_H := 24.0
const SPARK_H := 96.0
const SPARK_COMPACT_H := 78.0
const CHIP_H := 34.0
const HEADER_ROW := 22.0
const GRID_HEAD := 20.0
const GRID_ROW := 26.0
const GRID_COMPACT_ROW := 22.0
const DOOR_H := 34.0

var f_bold: FontFile
var f_med: FontFile
var f_body: FontFile
var touch := false
var scroll := 0.0

var _rows: Array = []
var _height := 0.0
var _focus := -1
var mouse := Vector2(-1000, -1000)


var hints := DateHints.new()


var names := InterestNames.new()


var followed := {}

func _ready() -> void:
	f_bold = UiTheme.bold()
	f_med = UiTheme.medium()
	f_body = UiTheme.body()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


const TAP_ROW_H := 49.0


static func layout(blocks: Array, width: float, compact: bool = false,
		touch: bool = false) -> Dictionary:
	var rows: Array = []
	var y := COMPACT_MARGIN if compact else MARGIN
	var row_h := 24.0 if compact else 22.0
	if touch:
		row_h = TAP_ROW_H
	for block in blocks:
		var kind := str(block.get("k", ""))
		var x := 0.0
		if kind == "section":
			var h: float = SECTION_COMPACT_H if compact else SECTION_H
			rows.append({"k": kind, "rect": Rect2(x, y, width, h), "text": str(block.get("text", ""))})
			y += h
		elif kind == "note":
			rows.append({"k": kind, "rect": Rect2(x, y, width, NOTE_H), "text": str(block.get("text", ""))})
			y += NOTE_H
		elif kind == "kv":
			var cols := 2 if compact else 3
			var items: Array = block.get("items", [])
			var lines := int(ceil(float(items.size()) / float(cols)))
			for line in range(lines):
				var rect := Rect2(x, y + float(line) * KV_H, width, KV_H)
				var slice: Array = items.slice(line * cols, mini((line + 1) * cols, items.size()))
				rows.append({"k": "kv", "rect": rect, "items": slice, "cols": cols})
			y += KV_H * float(lines)
		elif kind == "bars":
			for item in block.get("items", []):
				rows.append({"k": "bar", "rect": Rect2(x, y, width, BAR_H), "label": str(item[0]), "value": float(item[1])})
				y += BAR_H
			y += 4.0
		elif kind == "grid":
			var grid_cols := 2 if compact else int(block.get("cols", 3))
			var grid_row_h: float = GRID_COMPACT_ROW if compact else GRID_ROW
			var groups: Array = block.get("groups", [])
			var lines := int(ceil(float(groups.size()) / float(maxi(grid_cols, 1))))
			for line in range(lines):
				var chunk: Array = groups.slice(line * grid_cols, mini((line + 1) * grid_cols, groups.size()))
				var deepest := 0
				for group in chunk:
					deepest = maxi(deepest, (group as Dictionary).get("cells", []).size())
				var h: float = GRID_HEAD + float(deepest) * grid_row_h + 6.0
				rows.append({
					"k": "gridrow", "rect": Rect2(x, y, width, h), "groups": chunk,
					"cols": grid_cols, "rows": deepest, "row_h": grid_row_h,
				})
				y += h
			y += 4.0
		elif kind == "door":
			var items: Array = block.get("items", [])
			var door_w: float = width / float(maxi(items.size(), 1))
			for i in range(items.size()):
				var door: Dictionary = items[i]
				rows.append({
					"k": "door", "rect": Rect2(x + door_w * float(i), y, door_w - 8.0, DOOR_H),
					"text": str(door.get("text", "")), "id": str(door.get("id", "")),
					"accent": str(door.get("accent", "")), "on": bool(door.get("on", false)),
				})
			y += DOOR_H
		elif kind == "spark":
			var h: float = SPARK_COMPACT_H if compact else SPARK_H
			rows.append({
				"k": "spark", "rect": Rect2(x, y, width, h), "points": block.get("points", []),
				"clubs": int(block.get("clubs", 0)), "place": int(block.get("place", 0)),
				"best": int(block.get("best", 0)), "worst": int(block.get("worst", 0)),
				"accent": str(block.get("accent", "")),
			})
			y += h
		elif kind == "chips":
			if bool(block.get("strip", false)) and compact:
				continue
			var per := 4 if compact else 8
			var chips: Array = block.get("items", [])
			var chip_w := width / float(per)
			for i in range(chips.size()):
				var line := int(i / per)
				var rect := Rect2(x + float(i % per) * chip_w, y + float(line) * CHIP_H, chip_w - 8.0, CHIP_H - 6.0)
				var chip: Dictionary = chips[i]
				rows.append({
					"k": "chip", "rect": rect, "text": str(chip.get("text", "")),
					"accent": str(chip.get("accent", "")), "target": chip.get("target", {}),
				})
			y += CHIP_H * float(ceil(float(chips.size()) / float(per)))
		elif kind == "table":
			var cols: Array = block.get("cols", [])
			var widths := _widths(block, cols.size())
			rows.append({
				"k": "thead", "rect": Rect2(x, y, width, HEADER_ROW), "cols": cols,
				"widths": widths, "text_cols": block.get("text_cols", [1]), "index": -1,
			})
			y += HEADER_ROW
			var table_rows: Array = block.get("rows", [])
			for i in range(table_rows.size()):
				var tr: Dictionary = table_rows[i]
				rows.append({
					"k": "trow", "rect": Rect2(x, y, width, row_h), "cells": tr.get("cells", []),
					"widths": widths, "cols": cols, "target": tr.get("target", {}),
					"accent": str(tr.get("accent", "")), "index": i,
					"text_cols": block.get("text_cols", [1]),
					"dates": tr.get("dates", {}),
				})
				y += row_h
			y += 6.0
		y += COMPACT_GAP if compact else GAP
	return {"rows": rows, "height": y + (COMPACT_MARGIN if compact else MARGIN)}

static func _widths(block: Dictionary, count: int) -> Array:
	if block.has("widths"):
		var given: Array = block["widths"]
		if given.size() == count:
			return given
	var out: Array = []
	var width := 1.0 / float(maxi(count, 1))
	for i in range(count):
		out.append(width)
	return out

func set_page(page: Dictionary, compact: bool = false) -> void:
	var built := layout(page.get("blocks", []), size.x, compact, touch)
	_rows = built["rows"]
	_height = float(built["height"])
	scroll = 0.0
	_focus = -1
	queue_redraw()

func max_scroll() -> float:
	return maxf(0.0, _height - size.y)

func scroll_by(delta: float) -> void:
	scroll_to(scroll + delta)

func scroll_to(at: float) -> void:
	scroll = clampf(at, 0.0, max_scroll())
	queue_redraw()

func rows() -> Array:
	return _rows

func content_height() -> float:
	return _height


func has_open_row_in_view() -> bool:
	for row in _rows:
		if str(row.get("k", "")) != "trow":
			continue
		if (row.get("target", {}) as Dictionary).is_empty():
			continue
		var rect: Rect2 = row["rect"]
		var top: float = rect.position.y - scroll
		if top + rect.size.y > 0.0 and top < size.y:
			return true
	return false


func hit(p: Vector2) -> Dictionary:
	var local := _content_point(p)
	if local.x < 0.0:
		return {}
	for row in _rows:
		var rect: Rect2 = row["rect"]
		if rect.has_point(local) and not (row.get("target", {}) as Dictionary).is_empty():
			return row["target"]
	return {}


func button_id(p: Vector2) -> String:
	"""The door a press lands on, for the rows that carry one by id."""
	var local := _content_point(p)
	if local.x < 0.0:
		return ""
	for row in _rows:
		if str(row.get("k", "")) != "door":
			continue
		if (row["rect"] as Rect2).has_point(local):
			return str(row.get("id", ""))
	return ""


func club_at(p: Vector2) -> String:
	var local := p - position
	if not Rect2(Vector2.ZERO, size).has_point(local):
		return ""
	return names.at(local)


func _name_strip(row: Dictionary, rect: Rect2) -> void:
	var target: Dictionary = row.get("target", {})
	if str(target.get("page", "")) != WikiModel.TEAM:
		return
	if str(row.get("k", "")) == "chip":
		names.add(rect, str(target.get("id", "")))
		return
	var idx := int(row.get("club_cell", -1))
	var cells: Array = row.get("cells", [])
	if idx < 0 or idx >= cells.size():
		return
	var widths: Array = row["widths"]
	var inner: float = rect.size.x - 6.0
	var x: float = rect.position.x + 6.0
	for i in range(idx):
		x += inner * float(widths[i])
	names.add(Rect2(x, rect.position.y, inner * float(widths[idx]), rect.size.y), str(target["id"]))

func row_at(p: Vector2) -> int:
	var local := _content_point(p)
	if local.x < 0.0:
		return -1
	for i in range(_rows.size()):
		if (_rows[i]["rect"] as Rect2).has_point(local):
			return i
	return -1


func _content_point(p: Vector2) -> Vector2:
	var local := p - position
	if not Rect2(Vector2.ZERO, size).has_point(local):
		return Vector2(-1.0, -1.0)
	local.y += scroll
	return local


func _draw() -> void:
	if _rows.is_empty():
		return
	hints.clear()
	names.clear()
	var focus_row := row_at(mouse) if mouse.x > -500.0 else -1
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var rect: Rect2 = row["rect"]
		var top: float = rect.position.y - scroll
		if top + rect.size.y < 0.0 or top > size.y:
			continue
		var shifted := Rect2(rect.position.x, top, rect.size.x, rect.size.y)
		_name_strip(row, shifted)
		WikiBodyPaint.row(self, row, shifted, i == focus_row)


func _process(_d: float) -> void:
	queue_redraw()
