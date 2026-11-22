extends Control

## Pre-match fixture picker: choose the home and away club, then kick off.
## Drawn with the same broadcast palette as hud.gd so it feels part of the overlay.

signal confirmed(home_id: String, away_id: String)
signal cancelled()

const C_PANEL := Color(0.035, 0.055, 0.070, 0.97)
const C_PANEL_LIGHT := Color(0.075, 0.105, 0.125, 0.97)
const C_BORDER := Color(1, 1, 1, 0.085)
const C_TEXT := Color(0.92, 0.95, 0.96)
const C_DIM := Color(0.55, 0.64, 0.69)
const C_GOLD := Color(0.96, 0.78, 0.30)

var ids: Array = []
var home_idx := 0
var away_idx := 1
## Design-space multiplier and touch flag, pushed in by main.gd: on a phone the
## whole layer is scaled up, so every rect here is derived from the smaller
## design viewport.
var ui_scale := 1.0
var touch := false
var mouse := Vector2(-1000, -1000)
var buttons: Array = []

var f_bold: FontFile
var f_med: FontFile
var f_body: FontFile

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_bold = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	f_med = load("res://fonts/BarlowCondensed-Medium.ttf")
	f_body = load("res://fonts/Inter-Regular.ttf")
	ids = TeamData.team_ids()
	ids.sort()

func setup(home_id: String, away_id: String) -> void:
	if ids.is_empty():
		ids = TeamData.team_ids()
		ids.sort()
	home_idx = maxi(0, ids.find(home_id))
	away_idx = maxi(0, ids.find(away_id))
	if away_idx == home_idx:
		away_idx = (home_idx + 1) % ids.size()
	mouse = Vector2(-1000, -1000)

func home_id() -> String:
	return str(ids[home_idx]) if not ids.is_empty() else "MUN"

func away_id() -> String:
	return str(ids[away_idx]) if not ids.is_empty() else "MCI"

# ------------------------------------------------------------------ actions --

func cycle_home(dir: int) -> void:
	if ids.size() < 2:
		return
	home_idx = posmod(home_idx + dir, ids.size())
	if home_idx == away_idx:
		home_idx = posmod(home_idx + dir, ids.size())

func cycle_away(dir: int) -> void:
	if ids.size() < 2:
		return
	away_idx = posmod(away_idx + dir, ids.size())
	if away_idx == home_idx:
		away_idx = posmod(away_idx + dir, ids.size())

func randomize_fixture() -> void:
	if ids.size() < 2:
		return
	home_idx = randi() % ids.size()
	away_idx = randi() % ids.size()
	if away_idx == home_idx:
		away_idx = (home_idx + 1) % ids.size()

func confirm() -> void:
	confirmed.emit(home_id(), away_id())

func click(id: String) -> void:
	match id:
		"back": cancelled.emit()
		"home_prev": cycle_home(-1)
		"home_next": cycle_home(1)
		"away_prev": cycle_away(-1)
		"away_next": cycle_away(1)
		"random": randomize_fixture()
		"confirm": confirm()
		"cancel": cancelled.emit()

func key(code: int) -> bool:
	match code:
		KEY_LEFT, KEY_A: cycle_home(-1)
		KEY_RIGHT, KEY_D: cycle_home(1)
		KEY_UP, KEY_W: cycle_away(-1)
		KEY_DOWN, KEY_S: cycle_away(1)
		KEY_TAB: randomize_fixture()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: confirm()
		KEY_ESCAPE: cancelled.emit()
		_: return false
	return true

func button_at(p: Vector2) -> String:
	for b in buttons:
		if (b["rect"] as Rect2).has_point(p):
			return b["id"]
	return ""

# ------------------------------------------------------------------ drawing --

func _process(_d: float) -> void:
	queue_redraw()

var style_cache := {}

func _style(c: Color, r: int = 10, bc: Color = C_BORDER, bw: int = 1) -> StyleBoxFlat:
	var key := "%s|%d|%s|%d" % [c.to_html(), r, bc.to_html(), bw]
	if style_cache.has(key):
		return style_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.border_color = bc
	sb.set_border_width_all(bw)
	style_cache[key] = sb
	return sb

func rect(c: Color, r: Rect2, radius: int = 10, bc: Color = C_BORDER) -> void:
	draw_style_box(_style(c, radius, bc), r)

func text(pos: Vector2, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else f_med
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func text_c(center_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else f_med
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2(center_x - w * 0.5, y), s, size, color, f)

func _add_button(id: String, r: Rect2) -> void:
	buttons.append({"id": id, "rect": r})

func _arrow(r: Rect2, glyph: String, id: String) -> void:
	var hovered := r.has_point(mouse)
	rect(C_PANEL_LIGHT if hovered else C_PANEL, r, 8, Color(1, 1, 1, 0.14 if hovered else 0.07))
	text_c(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.66, glyph, 24, C_TEXT if hovered else C_DIM, f_bold)
	_add_button(id, r)

func _card(r: Rect2, t: Dictionary, side: int) -> void:
	rect(C_PANEL, r, 14, Color(1, 1, 1, 0.10))
	draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 6, r.size.y - 2), t["color"])
	var cx := r.position.x + r.size.x * 0.5
	text_c(cx, r.position.y + r.size.y * 0.30, str(t["abbr"]), 54, C_TEXT, f_bold)
	text_c(cx, r.position.y + r.size.y * 0.50, str(t["name"]).to_upper(), 17, C_TEXT, f_med)
	text_c(cx, r.position.y + r.size.y * 0.64, str(t["nickname"]).to_upper(), 11, C_DIM, f_med)
	text_c(cx, r.position.y + r.size.y * 0.80, "%s  ·  %s" % [str(t["formation"]), str(t["manager"]).to_upper()], 10, C_GOLD, f_med)
	var label := "HOME" if side == 0 else "AWAY"
	text_c(cx, r.position.y - 10, label, 11, C_DIM, f_bold)

## Design space this sheet draws in (the layer is scaled up by main.gd).
func design_vp() -> Vector2:
	return get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)

## A touch build has no Escape key, so the sheet needs a door that a tap can
## reach; the layout test reads this rect instead of a screenshot.
func back_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - 24.0 - 116.0, 18.0, 116.0, 44.0)

func _draw() -> void:
	var vp := design_vp()
	buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.025, 0.032, 0.94))
	draw_rect(Rect2(0, 0, vp.x, 3), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(0, vp.y - 3, vp.x, 3), Color(0, 0, 0, 0.5))
	text_c(vp.x * 0.5, vp.y * 0.16, "PREMIER LEAGUE", 13, C_GOLD, f_bold)
	text_c(vp.x * 0.5, vp.y * 0.235, "SELECT FIXTURE", 40, C_TEXT, f_bold)

	var card_w := minf(vp.x * 0.30, 460.0)
	var card_h := minf(vp.y * 0.32, 250.0)
	var gap := clampf(vp.x * 0.14, 130.0, 220.0)
	var card_y := vp.y * 0.42 - card_h * 0.5
	var home_rect := Rect2(vp.x * 0.5 - gap * 0.5 - card_w, card_y, card_w, card_h)
	var away_rect := Rect2(vp.x * 0.5 + gap * 0.5, card_y, card_w, card_h)

	if ids.is_empty():
		text_c(vp.x * 0.5, vp.y * 0.55, "NO SQUAD DATA", 20, C_DIM, f_bold)
		return

	var home := TeamData.get_team(home_id())
	var away := TeamData.get_team(away_id())
	_card(home_rect, home, 0)
	_card(away_rect, away, 1)

	var arrow := 46.0
	var ay := card_y + card_h * 0.5 - arrow * 0.5
	_arrow(Rect2(home_rect.position.x - arrow - 12.0, ay, arrow, arrow), "‹", "home_prev")
	_arrow(Rect2(home_rect.position.x + home_rect.size.x + 12.0, ay, arrow, arrow), "›", "home_next")
	_arrow(Rect2(away_rect.position.x - arrow - 12.0, ay, arrow, arrow), "‹", "away_prev")
	_arrow(Rect2(away_rect.position.x + away_rect.size.x + 12.0, ay, arrow, arrow), "›", "away_next")

	text_c(vp.x * 0.5, card_y + card_h * 0.50, "v", 22, C_DIM, f_med)
	var venue := str(home.get("stadium", "")).to_upper()
	if venue != "":
		text_c(vp.x * 0.5, card_y + card_h * 0.64, venue, 10, C_DIM, f_med)

	var bw := 190.0
	var bh := 50.0
	var by: float = minf(card_y + card_h + 54.0, vp.y - bh - 78.0)
	var confirm_rect := Rect2(vp.x * 0.5 - bw - 8.0, by, bw, bh)
	var random_rect := Rect2(vp.x * 0.5 + 8.0, by, bw, bh)
	for spec in [["confirm", confirm_rect, "KICK OFF", "ENTER"], ["random", random_rect, "RANDOM", "TAB"]]:
		var r: Rect2 = spec[1]
		var hovered := r.has_point(mouse)
		var bg: Color = Color(0.16, 0.13, 0.05, 0.98) if spec[0] == "confirm" else (C_PANEL_LIGHT if hovered else C_PANEL)
		rect(bg, r, 10, Color(0.96, 0.78, 0.30, 0.55) if spec[0] == "confirm" else Color(1, 1, 1, 0.10 if hovered else 0.06))
		var cap_y: float = r.position.y + (r.size.y * 0.5 + 6.0 if touch else 24.0)
		text_c(r.position.x + r.size.x * 0.5, cap_y, spec[2], 16, C_GOLD if spec[0] == "confirm" else C_TEXT, f_bold)
		if not touch:
			text_c(r.position.x + r.size.x * 0.5, r.position.y + 39, spec[3], 9, C_DIM, f_med)
		_add_button(spec[0], r)

	if touch:
		text_c(vp.x * 0.5, vp.y - 44, "TAP THE ARROWS TO CHANGE CLUBS  ·  TAP KICK OFF", 11, C_DIM, f_med)
		text_c(vp.x * 0.5, vp.y - 24, "20 PREMIER LEAGUE CLUBS", 9, Color(0.96, 0.78, 0.30, 0.55), f_med)
	else:
		text_c(vp.x * 0.5, vp.y - 64, "CLICK THE ARROWS OR USE  ← →  (HOME)   ·   ↑ ↓  (AWAY)", 11, C_DIM, f_med)
		text_c(vp.x * 0.5, vp.y - 44, "ENTER  KICK OFF   ·   TAB  RANDOM   ·   ESC  BACK", 10, C_DIM, f_med)
		text_c(vp.x * 0.5, vp.y - 24, "20 PREMIER LEAGUE CLUBS", 9, Color(0.96, 0.78, 0.30, 0.55), f_med)

	# A touch build has no Escape key: the sheet needs a visible way out.
	var back := back_rect(vp)
	var back_hover := back.has_point(mouse)
	rect(C_PANEL_LIGHT if back_hover else C_PANEL, back, 8, Color(1, 1, 1, 0.14 if back_hover else 0.07))
	text_c(back.position.x + back.size.x * 0.5, back.position.y + back.size.y * 0.66, "‹  BACK", 13, C_TEXT if back_hover else C_DIM, f_bold)
	_add_button("back", back)
