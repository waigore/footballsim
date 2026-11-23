class_name WikiBody
extends Control

## Scrollable body of an encyclopedia page. `WikiBody.layout()` turns the block
## list from WikiModel into positioned rows (pure, no fonts, testable headless);
## this node only draws those rows and reports which target a tap hit.

const MARGIN := 6.0
const GAP := 14.0
const SECTION_H := 30.0
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

func _ready() -> void:
	f_bold = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	f_med = load("res://fonts/BarlowCondensed-Medium.ttf")
	f_body = load("res://fonts/Inter-Regular.ttf")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

## Positioned rows for a block list at a given content width. Every row keeps
## its own rect and (for rows that open a page) its target.
static func layout(blocks: Array, width: float, compact: bool = false) -> Dictionary:
	var rows: Array = []
	var y := MARGIN
	var row_h := 24.0 if compact else 22.0
	for block in blocks:
		var kind := str(block.get("k", ""))
		var x := 0.0
		if kind == "section":
			rows.append({"k": kind, "rect": Rect2(x, y, width, SECTION_H), "text": str(block.get("text", ""))})
			y += SECTION_H
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
				})
				y += row_h
			y += 6.0
		y += GAP
	return {"rows": rows, "height": y + MARGIN}

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
	var built := layout(page.get("blocks", []), size.x, compact)
	_rows = built["rows"]
	_height = float(built["height"])
	scroll = 0.0
	_focus = -1

func max_scroll() -> float:
	return maxf(0.0, _height - size.y)

func scroll_by(delta: float) -> void:
	scroll = clampf(scroll + delta, 0.0, max_scroll())

func rows() -> Array:
	return _rows

func content_height() -> float:
	return _height

## First row whose target sits under a body-local point (hover/tap).
func hit(p: Vector2) -> Dictionary:
	var local := p - position
	for row in _rows:
		var rect: Rect2 = row["rect"]
		if rect.has_point(local) and not (row.get("target", {}) as Dictionary).is_empty():
			return row["target"]
	return {}

func row_at(p: Vector2) -> int:
	var local := p - position
	for i in range(_rows.size()):
		if (_rows[i]["rect"] as Rect2).has_point(local):
			return i
	return -1

# ------------------------------------------------------------------ drawing --

func _draw() -> void:
	if _rows.is_empty():
		return
	var focus_row := row_at(mouse) if mouse.x > -500.0 else -1
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var rect: Rect2 = row["rect"]
		var top: float = rect.position.y - scroll
		if top + rect.size.y < 0.0 or top > size.y:
			continue
		var shifted := Rect2(rect.position.x, top, rect.size.x, rect.size.y)
		_draw_row(row, shifted, i == focus_row)

func _draw_row(row: Dictionary, rect: Rect2, hovered: bool) -> void:
	var kind := str(row["k"])
	if kind == "section":
		draw_rect(Rect2(rect.position.x, rect.position.y + 12, 3, 12), Color(0.96, 0.78, 0.30))
		_text(Vector2(rect.position.x + 12, rect.position.y + 22), str(row["text"]), 11, Color(0.55, 0.64, 0.69), true)
		draw_line(Vector2(rect.position.x, rect.position.y + 28), Vector2(rect.position.x + rect.size.x, rect.position.y + 28), Color(1, 1, 1, 0.07), 1)
	elif kind == "note":
		_text(Vector2(rect.position.x, rect.position.y + 16), _clip(str(row["text"]), 130), 9, Color(0.55, 0.64, 0.69), false)
	elif kind == "kv":
		var items: Array = row["items"]
		var cw: float = rect.size.x / float(row["cols"])
		for i in range(items.size()):
			var item: Array = items[i]
			var x: float = rect.position.x + cw * float(i)
			var big: bool = item.size() > 2 and bool(item[2])
			_text(Vector2(x, rect.position.y + 12), str(item[0]), 8, Color(0.55, 0.64, 0.69), true)
			_text(Vector2(x, rect.position.y + 28), str(item[1]), 17 if big else 13, Color(0.92, 0.95, 0.96), true)
	elif kind == "bar":
		var label := str(row["label"])
		var value := clampf(float(row["value"]), 0.0, 1.0)
		_text(Vector2(rect.position.x, rect.position.y + 16), label, 9, Color(0.55, 0.64, 0.69), true)
		var bar_x: float = rect.position.x + minf(150.0, rect.size.x * 0.30)
		var bar_w: float = rect.size.x - (bar_x - rect.position.x) - 46.0
		draw_rect(Rect2(bar_x, rect.position.y + 8, bar_w, 6), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(bar_x, rect.position.y + 8, bar_w * value, 6), Color(0.62, 0.82, 0.86))
		_text(Vector2(bar_x + bar_w + 8, rect.position.y + 16), str(int(round(value * 100.0))), 12, Color(0.92, 0.95, 0.96), true)
	elif kind == "chip":
		var accent := Color(str(row["accent"])) if str(row["accent"]) != "" else Color(0.35, 0.45, 0.5)
		draw_rect(rect, Color(0.075, 0.105, 0.125, 0.95 if not hovered else 1.0), true)
		draw_rect(Rect2(rect.position, Vector2(4, rect.size.y)), accent)
		_text(Vector2(rect.position.x + 14, rect.position.y + 19), str(row["text"]), 13, Color(0.92, 0.95, 0.96), true)
	elif kind == "thead":
		var cols: Array = row["cols"]
		var widths: Array = row["widths"]
		var text_cols: Array = row["text_cols"]
		var x := rect.position.x
		for i in range(cols.size()):
			var cw: float = rect.size.x * float(widths[i])
			if text_cols.has(i) or i == 0:
				_text(Vector2(x, rect.position.y + 15), str(cols[i]), 9, Color(0.62, 0.72, 0.78), true)
			else:
				_text_right(x + cw - 8.0, rect.position.y + 15.0, str(cols[i]), 9, Color(0.62, 0.72, 0.78), true)
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
		for i in range(cells.size()):
			var cw: float = (rect.size.x - 6.0) * float(widths[i])
			var right: bool = not text_cols.has(i) and i != 0
			if right:
				_text_right(x + cw - 8.0, rect.position.y + 16.0, str(cells[i]), 11, Color(0.92, 0.95, 0.96), i == cells.size() - 1)
			else:
				_text(Vector2(x, rect.position.y + 16), _clip(str(cells[i]), 34), 11, Color(0.92, 0.95, 0.96), i == 1 and cells.size() >= 4)
			x += cw
		draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y), Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), Color(1, 1, 1, 0.05), 1)

func _clip(s: String, max_chars: int) -> String:
	return s if s.length() <= max_chars else s.substr(0, max_chars - 1) + "…"

func _text(pos: Vector2, s: String, size_px: int, color: Color, bold: bool) -> void:
	draw_string(f_bold if bold else f_body, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _text_right(right_x: float, y: float, s: String, size_px: int, color: Color, bold: bool) -> void:
	var font: Font = f_bold if bold else f_body
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
