extends Control

## Pre-match fixture picker: choose the home and away club, then kick off.
## Drawn with the same broadcast palette as hud.gd so it feels part of the overlay.

signal confirmed(home_id: String, away_id: String)
signal cancelled()
## Entry into the encyclopedia: the league, or a club picked from a card.
signal browse(page: String, id: String)

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
## Opened from the main menu, so its way out is the menu rather than the match.
var back_to_menu := false
## The long press on a club card (#107), and the layer that paints its menu.
var interest := InterestHold.new()
var menu_layer: InterestLayer = null
## The followed club ids as a set: their card names print gold.
var followed := {}

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
	# A held card opens the Teams of Interest menu (#107); the card is already the
	# club's own door, so the hold reads it back.
	interest.club_at = func(p: Vector2) -> String:
		var id := button_at(p)
		if id == "team_home":
			return home_id()
		if id == "team_away":
			return away_id()
		return ""
	interest.season_of = func(): return LeagueSeason.active
	interest.on_changed = func(): queue_redraw()
	menu_layer = InterestLayer.new()
	menu_layer.hold = interest
	menu_layer.screen = self
	add_child(menu_layer)

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

## if/elif rather than match: the coverage injector cannot instrument a match
## statement, and an uninstrumentable file fails the patch gate.
func click(id: String) -> void:
	if interest.click(id):
		return
	if id == "back" or id == "cancel":
		cancelled.emit()
	elif id == "home_prev":
		cycle_home(-1)
	elif id == "home_next":
		cycle_home(1)
	elif id == "away_prev":
		cycle_away(-1)
	elif id == "away_next":
		cycle_away(1)
	elif id == "random":
		randomize_fixture()
	elif id == "confirm":
		confirm()
	elif id == "league":
		browse.emit(WikiModel.LEAGUE, "")
	elif id == "team_home":
		browse.emit(WikiModel.TEAM, home_id())
	elif id == "team_away":
		browse.emit(WikiModel.TEAM, away_id())

func key(code: int) -> bool:
	if code == KEY_LEFT or code == KEY_A:
		cycle_home(-1)
	elif code == KEY_RIGHT or code == KEY_D:
		cycle_home(1)
	elif code == KEY_UP or code == KEY_W:
		cycle_away(-1)
	elif code == KEY_DOWN or code == KEY_S:
		cycle_away(1)
	elif code == KEY_TAB:
		randomize_fixture()
	elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
		confirm()
	elif code == KEY_ESCAPE:
		cancelled.emit()
	elif code == KEY_L:
		browse.emit(WikiModel.LEAGUE, "")
	else:
		return false
	return true

func button_at(p: Vector2) -> String:
	# The open menu answers every press itself (#107).
	if interest.is_open():
		return interest.menu.hit(p, design_vp())
	for b in buttons:
		if (b["rect"] as Rect2).has_point(p):
			return b["id"]
	return ""

# ------------------------------------------------------------------ drawing --

func _process(d: float) -> void:
	if interest.tick(d):
		queue_redraw()
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
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, ChromeDensity.read_size(size), color)

func text_c(center_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else f_med
	var px := ChromeDensity.read_size(size)
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	text(Vector2(center_x - w * 0.5, y), s, px, color, f)

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
	# A followed club's card wears the interest mark (#107).
	var club := str(t.get("id", ""))
	if club == "":
		club = home_id() if side == 0 else away_id()
	var name_ink: Color = C_GOLD if followed.has(club) else C_TEXT
	text_c(cx, r.position.y + r.size.y * 0.30, str(t["abbr"]), 54, name_ink, f_bold)
	text_c(cx, r.position.y + r.size.y * 0.50, str(t["name"]).to_upper(), 17, name_ink, f_med)
	text_c(cx, r.position.y + r.size.y * 0.64, str(t["nickname"]).to_upper(), 11, C_DIM, f_med)
	text_c(cx, r.position.y + r.size.y * 0.80, "%s  ·  %s" % [str(t["formation"]), str(t["manager"]).to_upper()], 10, C_GOLD, f_med)
	text_c(cx, r.position.y + r.size.y - 12.0, "VIEW CLUB  ›", 10, C_DIM, f_bold)
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
	UiChrome.sheet_header(self, vp, {"bold": f_bold, "med": f_med, "body": f_body}, "PREMIER LEAGUE · 20 CLUBS", "SELECT FIXTURE")
	# The top corners belong to the league and menu doors, so the wordmark rides
	# the centre of the header where nothing covers it.
	UiChrome.wordmark_c(self, vp.x * 0.5, vp.y * (0.075 if vp.y < 620.0 else 0.105), 12, f_bold)

	var card_w := minf(vp.x * 0.30, 460.0)
	var card_h := minf(vp.y * 0.32, 250.0)
	var gap := clampf(vp.x * 0.14, 130.0, 220.0)
	var card_y := vp.y * 0.42 - card_h * 0.5
	var home_rect := Rect2(vp.x * 0.5 - gap * 0.5 - card_w, card_y, card_w, card_h)
	var away_rect := Rect2(vp.x * 0.5 + gap * 0.5, card_y, card_w, card_h)

	if ids.is_empty():
		text_c(vp.x * 0.5, vp.y * 0.55, "NO SQUAD DATA", 20, C_DIM, f_bold)
		return

	var season = LeagueSeason.active
	followed = LeagueInterestMark.set_of(season.state().get("interests", [])) \
		if season != null else {}
	var home := TeamData.get_team(home_id())
	var away := TeamData.get_team(away_id())
	_card(home_rect, home, 0)
	_card(away_rect, away, 1)
	# The cards are also encyclopedia doors: a club page is one tap away.
	_add_button("team_home", home_rect)
	_add_button("team_away", away_rect)

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
	# Doors take the shared grammar's radius so KICK OFF reads like every other
	# primary; its ENTER hint is a keyboard-only affordance under the caption.
	for spec in [["confirm", confirm_rect, "KICK OFF", "ENTER"],
			["random", random_rect, "RANDOM", "TAB"]]:
		var r: Rect2 = spec[1]
		var hovered := r.has_point(mouse)
		if spec[0] == "confirm":
			UiChrome.button(self, style_cache, r, str(spec[2]), f_bold, true, 16,
				"" if touch else str(spec[3]))
		else:
			# RANDOM stays the picker's quiet door: it keeps its hover fill.
			rect(C_PANEL_LIGHT if hovered else C_PANEL, r, 10,
				Color(1, 1, 1, 0.10 if hovered else 0.06))
			var middle: float = r.position.y + r.size.y * 0.5
			var cap_y: float = middle + (UiChrome.RISE if touch else -UiChrome.RISE)
			text_c(r.get_center().x, cap_y, str(spec[2]), 16, C_TEXT, f_bold)
			if not touch:
				text_c(r.get_center().x, middle + UiChrome.HINT_DROP, str(spec[3]), 10,
					C_DIM, f_med)
		_add_button(spec[0], r)

	if touch:
		text_c(vp.x * 0.5, vp.y - 44, "TAP THE ARROWS TO CHANGE CLUBS  ·  TAP KICK OFF", 11, C_DIM, f_med)
		text_c(vp.x * 0.5, vp.y - 24, "20 PREMIER LEAGUE CLUBS", 10, Color(0.96, 0.78, 0.30, 0.55), f_med)
	else:
		text_c(vp.x * 0.5, vp.y - 64, "CLICK THE ARROWS OR USE  ← →  (HOME)   ·   ↑ ↓  (AWAY)", 11, C_DIM, f_med)
		text_c(vp.x * 0.5, vp.y - 44, "ENTER  KICK OFF   ·   TAB  RANDOM   ·   ESC  %s" % ("MENU" if back_to_menu else "BACK"), 10, C_DIM, f_med)
		text_c(vp.x * 0.5, vp.y - 24, "20 PREMIER LEAGUE CLUBS", 10, Color(0.96, 0.78, 0.30, 0.55), f_med)

	# A touch build has no Escape key: the sheet needs a visible way out.
	var back := back_rect(vp)
	var back_hover := back.has_point(mouse)
	rect(C_PANEL_LIGHT if back_hover else C_PANEL, back, 8, Color(1, 1, 1, 0.14 if back_hover else 0.07))
	text_c(back.position.x + back.size.x * 0.5, back.position.y + back.size.y * 0.66, "‹  MENU" if back_to_menu else "‹  BACK", 13, C_TEXT if back_hover else C_DIM, f_bold)
	_add_button("back", back)

	# Encyclopedia door: the whole league is one tap from the fixture sheet.
	var league_btn := Rect2(24.0, 18.0, 138.0, 44.0)
	var league_hover := league_btn.has_point(mouse)
	rect(C_PANEL_LIGHT if league_hover else C_PANEL, league_btn, 8, Color(1, 1, 1, 0.14 if league_hover else 0.07))
	text_c(league_btn.position.x + league_btn.size.x * 0.5, league_btn.position.y + league_btn.size.y * 0.66, "◈  LEAGUE", 13, C_TEXT if league_hover else C_DIM, f_bold)
	_add_button("league", league_btn)
