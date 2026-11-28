class_name LeagueTableView
extends RefCounted


const COMPACT := LeagueTableLayout.COMPACT
const FULL := LeagueTableLayout.FULL
const FORM := LeagueTableLayout.FORM
const MODES := [COMPACT, FULL, FORM]

const META_MODE := "table_mode"
const META_SORT := LeagueTableSort.META_SORT
const META_DIR := LeagueTableSort.META_DIR

const ROW_H := 22.0
const TAP_ROW_H := 49.0
const ZONE_BAND_W := LeagueTablePaint.ZONE_BAND_W
const TAB_H := LeagueTableLayout.TAB_H

const COMPACT_COLS := LeagueColumns.COMPACT_COLS
const FORM_COLS := LeagueFormColumns.FORM_COLS
const FORM_CAPTION := LeagueFormColumns.FORM_CAPTION
const FULL_COLS := LeagueColumns.FULL_COLS


var mode := ""
var order := LeagueTableSort.new()
var league_tab := ""
var cache := {}
var names := InterestNames.new()


func attach(save: LeagueSave) -> void:
	mode = ""
	league_tab = ""
	if save == null:
		order.attach(null)
		return
	var saved_mode := str(save.read_meta().get(META_MODE, ""))
	mode = saved_mode if MODES.has(saved_mode) else ""
	order.attach(save)


static func columns(reading: String) -> Array:
	return LeagueTableLayout.columns(reading)


static func numeric(cols: Array) -> int:
	return LeagueColumns.numeric(cols)


func layout(vp: Vector2, view: Dictionary) -> Array:
	var reading := _reading(vp)
	var rows := order.ordered(view.get("table", []), columns(reading))
	var row_h := row_height(view)
	var row_w := maxf(vp.x - 48.0, LeagueTableLayout.min_row(reading))
	var places := LeagueTableLayout.places(Rect2(24.0, 0.0, row_w, row_h), reading)
	var comps: Array = view.get("competitions", [])
	var tab_h: float = TAB_H if comps.size() > 1 else 0.0
	var touch := bool(view.get("touch", false))
	var top: float = LeagueTableHead.rows_top(reading == FULL, touch, tab_h)
	var items: Array = []
	if tab_h > 0.0:
		items.append_array(LeagueTableLayout.tabs(comps,
			LeagueTableLayout.current_tab(comps, league_tab), vp))
	items.append_array(LeagueTableHead.cells(places, reading == FULL, order.key, touch, tab_h))
	if reading == FORM:
		items.append(LeagueTableLayout.form_caption(places, row_w, top))
		top += LeagueFormColumns.CAPTION_H
	var interest := LeagueInterestMark.set_of(view.get("interests", []))
	items.append_array(LeagueTableLayout.rows(rows, places, interest, view, top, row_h, row_w))
	items.append({"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": LeagueExtra.back_rect(touch)})
	items.append_array(LeagueTableLayout.mode_bar(reading, vp, touch))
	return items


static func row_height(view: Dictionary) -> float:
	return TAP_ROW_H if bool(view.get("touch", false)) else ROW_H


func _reading(vp: Vector2) -> String:
	if mode == "":
		mode = COMPACT if LeagueChrome.compact(vp) else FULL
	return mode


func ordered(rows: Array) -> Array:
	return order.ordered(rows, columns(mode if mode != "" else COMPACT))


func press(id: String, save: LeagueSave) -> bool:
	if id.begins_with("tbl:league:"):
		var tab := id.substr(11)
		if tab == league_tab:
			return false
		league_tab = tab
		return true
	if id.begins_with("tbl:sort:"):
		return order.press(id.substr(9), save)
	if not id.begins_with("tbl:mode:"):
		return false
	var wanted := id.substr(9)
	var current: String = mode if mode != "" else COMPACT
	if not MODES.has(wanted) or wanted == current:
		return false
	mode = wanted
	_store(save, META_MODE, mode)
	return true


func _store(save: LeagueSave, key: String, value: String) -> void:
	if save != null:
		save.put_meta(key, value)


# gd-tools: no cover start


func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	LeagueTableChrome.draw(c, vp, fonts, view, hints)


func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary, strips: InterestNames = null) -> void:
	LeagueTablePaint.draw_body(c, fonts, items, mode, cache, strips)


static func club_label(row: Dictionary) -> String:
	return LeagueColumns.club_label(row)

# gd-tools: no cover end
