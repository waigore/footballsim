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
const CHIP_H := 34.0
const HEADER_ROW := 22.0

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
	f_bold = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	f_med = load("res://fonts/BarlowCondensed-Medium.ttf")
	f_body = load("res://fonts/Inter-Regular.ttf")
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
		_draw_row(row, shifted, i == focus_row)


func _process(_d: float) -> void:
	queue_redraw()

func _draw_row(row: Dictionary, rect: Rect2, hovered: bool) -> void:
	var kind := str(row["k"])
	if kind == "section":
		var section_h: float = SECTION_COMPACT_H if rect.size.y <= SECTION_COMPACT_H else SECTION_H
		draw_rect(Rect2(rect.position.x, rect.position.y + section_h * 0.4, 3, 12), Color(0.96, 0.78, 0.30))
		_text(Vector2(rect.position.x + 12, rect.position.y + section_h * 0.74), str(row["text"]), 11, Color(0.55, 0.64, 0.69), true)
		draw_line(Vector2(rect.position.x, rect.position.y + section_h - 2.0), Vector2(rect.position.x + rect.size.x, rect.position.y + section_h - 2.0), Color(1, 1, 1, 0.07), 1)
	elif kind == "note":
		_text(Vector2(rect.position.x, rect.position.y + 16), _clip(str(row["text"]), 130), 10, Color(0.55, 0.64, 0.69), false)
	elif kind == "kv":
		var items: Array = row["items"]
		var cw: float = rect.size.x / float(row["cols"])
		for i in range(items.size()):
			var item: Array = items[i]
			var x: float = rect.position.x + cw * float(i)
			var big: bool = item.size() > 2 and bool(item[2])
			_text(Vector2(x, rect.position.y + 12), str(item[0]), 10, Color(0.55, 0.64, 0.69), true)
			_text(Vector2(x, rect.position.y + 28), str(item[1]), 17 if big else 13, Color(0.92, 0.95, 0.96), true)
	elif kind == "bar":
		var label := str(row["label"])
		var value := clampf(float(row["value"]), 0.0, 1.0)
		_text(Vector2(rect.position.x, rect.position.y + 16), label, 10, Color(0.55, 0.64, 0.69), true)
		var bar_x: float = rect.position.x + minf(150.0, rect.size.x * 0.30)
		var bar_w: float = rect.size.x - (bar_x - rect.position.x) - 46.0
		draw_rect(Rect2(bar_x, rect.position.y + 8, bar_w, 6), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(bar_x, rect.position.y + 8, bar_w * value, 6), Color(0.62, 0.82, 0.86))
		_text(Vector2(bar_x + bar_w + 8, rect.position.y + 16), str(int(round(value * 100.0))), 12, Color(0.92, 0.95, 0.96), true)
	elif kind == "chip":
		var accent := Color(str(row["accent"])) if str(row["accent"]) != "" else Color(0.35, 0.45, 0.5)
		draw_rect(rect, Color(0.075, 0.105, 0.125, 0.95 if not hovered else 1.0), true)
		draw_rect(Rect2(rect.position, Vector2(4, rect.size.y)), accent)
		var chip_id := str((row.get("target", {}) as Dictionary).get("id", ""))
		_text(Vector2(rect.position.x + 14, rect.position.y + 19),
			WikiChrome.fit(f_bold, str(row["text"]), 13, rect.size.x - 22.0), 13,
			UiChrome.C_GOLD if followed.has(chip_id) else Color(0.92, 0.95, 0.96), true)
	elif kind == "thead":
		var cols: Array = row["cols"]
		var widths: Array = row["widths"]
		var text_cols: Array = row["text_cols"]
		var x := rect.position.x
		for i in range(cols.size()):
			var cw: float = rect.size.x * float(widths[i])
			if text_cols.has(i) or i == 0:
				_text(Vector2(x, rect.position.y + 15), str(cols[i]), 10, Color(0.62, 0.72, 0.78), true)
			else:
				_text_right(x + cw - 8.0, rect.position.y + 15.0, str(cols[i]), 10, Color(0.62, 0.72, 0.78), true)
			x += cw
		draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y), Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), Color(1, 1, 1, 0.10), 1)
	elif kind == "trow":
		if hovered:
			draw_rect(rect, Color(0.075, 0.105, 0.125, 0.75))
		elif int(row.get("index", 0)) % 2 == 1:
			draw_rect(rect, Color(1, 1, 1, 0.022))
		var accent := str(row.get("accent", ""))
		if accent != "":
			draw_rect(Rect2(rect.position.x, rect.position.y + 3, 2, rect.size.y - 6), Color(accent))
		var widths: Array = row["widths"]
		var cells: Array = row["cells"]
		var x := rect.position.x + 6.0
		var text_cols: Array = row.get("text_cols", [1])
		var dates: Dictionary = row.get("dates", {})


		var mark := int(row.get("club_cell", -1))
		var marked: bool = mark >= 0 and followed.has(str((row.get("target", {}) as Dictionary).get("id", "")))
		for i in range(cells.size()):
			var cw: float = (rect.size.x - 6.0) * float(widths[i])

			if dates.has(i):
				hints.add(Rect2(x, rect.position.y + 2.0, cw, rect.size.y - 4.0), str(dates[i]))
			var ink: Color = UiChrome.C_GOLD if marked and i == mark else Color(0.92, 0.95, 0.96)
			var right: bool = not text_cols.has(i) and i != 0
			if right:
				_text_right(x + cw - 8.0, _row_baseline(rect), str(cells[i]), 11, ink, i == cells.size() - 1)
			else:
				_text(Vector2(x, _row_baseline(rect)), _clip(str(cells[i]), 34), 11, ink, i == 1 and cells.size() >= 4)
			x += cw
		draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y), Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), Color(1, 1, 1, 0.05), 1)

func _clip(s: String, max_chars: int) -> String:
	return s if s.length() <= max_chars else s.substr(0, max_chars - 1) + "…"


func _row_baseline(rect: Rect2) -> float:
	if rect.size.y > 30.0:
		return rect.position.y + rect.size.y * 0.5 + 4.0
	return rect.position.y + 16.0

func _text(pos: Vector2, s: String, size_px: int, color: Color, bold: bool) -> void:
	draw_string(f_bold if bold else f_body, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, WikiChrome.text_size(size_px), color)

func _text_right(right_x: float, y: float, s: String, size_px: int, color: Color, bold: bool) -> void:
	var font: Font = f_bold if bold else f_body
	var px := WikiChrome.text_size(size_px)
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
