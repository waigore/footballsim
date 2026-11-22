extends Control

## Broadcast overlay: scoreboard, commentary, controls, tooltips, player card.

var game = null
var engine = null

var f_bold: FontFile
var f_med: FontFile
var f_body: FontFile

var buttons: Array = []
var mouse := Vector2.ZERO
var hover_button := -1
var panel_cache := {}

# Commentary ticker state lives in HudCommentary; the HUD only forwards time
# and draws it.
var ticker: HudCommentary = null
var manager_card: HudManagers = null

const C_PANEL := Color(0.035, 0.055, 0.070, 0.94)
const C_PANEL_LIGHT := Color(0.075, 0.105, 0.125, 0.94)
const C_BORDER := Color(1, 1, 1, 0.085)
const C_TEXT := Color(0.92, 0.95, 0.96)
const C_DIM := Color(0.55, 0.64, 0.69)
const C_GOLD := Color(0.96, 0.78, 0.30)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_bold = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	f_med = load("res://fonts/BarlowCondensed-Medium.ttf")
	f_body = load("res://fonts/Inter-Regular.ttf")
	ticker = HudCommentary.new(C_PANEL, C_GOLD, C_TEXT, C_DIM)
	manager_card = HudManagers.new(C_PANEL, C_GOLD, C_TEXT, C_DIM)

func _process(d: float) -> void:
	if ticker != null:
		ticker.tick(d, engine, game)
	if manager_card != null:
		manager_card.tick(d, engine, game)
	queue_redraw()

func _style(c: Color, r: int = 10, bc: Color = C_BORDER, bw: int = 1) -> StyleBoxFlat:
	var key := "%s|%d|%s|%d" % [c.to_html(), r, bc.to_html(), bw]
	if panel_cache.has(key):
		return panel_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.border_color = bc
	sb.set_border_width_all(bw)
	panel_cache[key] = sb
	return sb

func rect(c: Color, r: Rect2, radius: int = 10, bc: Color = C_BORDER) -> void:
	draw_style_box(_style(c, radius, bc), r)

func text(pos: Vector2, s: String, size: int, color: Color = C_TEXT, font: Font = null, outline: int = 0, outline_col: Color = Color(0, 0, 0, 0.5)) -> void:
	var f: Font = font if font != null else f_med
	if outline > 0:
		draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_col)
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func text_c(center_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else f_med
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2(center_x - w * 0.5, y), s, size, color, f)

func text_r(right_x: float, y: float, s: String, size: int, color: Color = C_TEXT, font: Font = null) -> void:
	var f: Font = font if font != null else f_med
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2(right_x - w, y), s, size, color, f)

func _draw() -> void:
	if game == null or engine == null:
		return
	buttons.clear()
	var vp := get_viewport().get_visible_rect().size
	_draw_world_labels(vp)
	_draw_top(vp)
	_draw_meta(vp)
	_draw_stats(vp)
	_draw_controls(vp)
	if ticker != null:
		ticker.draw(self, vp, f_bold, f_med, game)
	if manager_card != null:
		manager_card.draw(self, vp, f_bold, f_med, engine)
	_draw_status(vp)
	_draw_focus(vp)
	_draw_tooltip(vp)
	_draw_event_banners(vp)
	_draw_intro(vp)
	_draw_paused(vp)
	_draw_vignette(vp)

# --------------------------------------------------------------- world text --

func w2s(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p

func _draw_world_labels(vp: Vector2) -> void:
	var zoom: float = get_viewport().get_canvas_transform().get_scale().x
	var show_names: bool = game.names_visible
	var ball_pos: Vector2 = engine.ball.pos
	for p in engine.players:
		if p.sent_off:
			continue
		var near: bool = p.pos.distance_to(ball_pos) < 26.0 or p.id == game.focus_id or p.id == game.hover_id
		var sp: Vector2 = w2s(p.pos - Vector2(0, p.z * 0.55))
		if sp.x < -40 or sp.x > vp.x + 40 or sp.y < -40 or sp.y > vp.y + 40:
			continue
		var r: float = 0.86 * zoom
		# shirt number
		var num := str(p.number)
		var ns: int = clampi(int(r * 0.95), 10, 24)
		var nw: float = f_bold.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
		var ncol: Color = Color(1, 1, 1, 0.96) if p.team == 0 else Color(0.08, 0.12, 0.16, 0.96)
		var kit: Dictionary = engine.teams[p.team].get("kit", {})
		if p.is_gk:
			ncol = Kits.ink(engine.teams[p.team]["data"]["gk_color"])
		elif not kit.is_empty():
			ncol = Kits.ink(kit.get("shirt", engine.teams[p.team]["data"]["color"]))
		text(Vector2(sp.x - nw * 0.5, sp.y + ns * 0.36), num, ns, ncol, f_bold, 2, Color(0, 0, 0, 0.35))
		# surnames
		if show_names and near and p.id != game.focus_id:
			var bits: PackedStringArray = p.name.split(" ")
			var surname := bits[bits.size() - 1].to_upper()
			var fs: int = clampi(int(zoom * 1.02), 9, 15)
			var sw: float = f_bold.get_string_size(surname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var ny: float = sp.y + r + fs * 0.95
			text(Vector2(sp.x - sw * 0.5, ny), surname, fs, Color(0.97, 0.99, 0.99, 0.92), f_bold, 4, Color(0.00, 0.02, 0.02, 0.85))

# -------------------------------------------------------------------- top ----

func _draw_top(vp: Vector2) -> void:
	var w := 640.0
	var h := 86.0
	var x := vp.x * 0.5 - w * 0.5
	var y := 14.0
	var shadow := Rect2(x + 4, y + 6, w, h)
	rect(Color(0, 0, 0, 0.30), shadow, 14, Color(0, 0, 0, 0))
	rect(C_PANEL, Rect2(x, y, w, h), 14, Color(1, 1, 1, 0.10))
	# team colour edges
	draw_rect(Rect2(x + 2, y + 2, 5, h - 4), engine.teams[0]["data"]["color"])
	draw_rect(Rect2(x + w - 7, y + 2, 5, h - 4), engine.teams[1]["data"]["color"])
	# home
	_badge(Rect2(x + 22, y + 19, 48, 48), 0)
	text(Vector2(x + 82, y + 44), engine.teams[0]["data"]["abbr"], 30, C_TEXT, f_bold)
	text(Vector2(x + 82, y + 64), engine.teams[0]["data"]["name"].to_upper(), 11, C_DIM, f_med)
	# away
	_badge(Rect2(x + w - 70, y + 19, 48, 48), 1)
	text_r(x + w - 82, y + 44, engine.teams[1]["data"]["abbr"], 30, C_TEXT, f_bold)
	text_r(x + w - 82, y + 64, engine.teams[1]["data"]["name"].to_upper(), 11, C_DIM, f_med)
	# score
	var sc := "%d  –  %d" % [engine.score[0], engine.score[1]]
	text_c(vp.x * 0.5, y + 52, sc, 40, C_TEXT, f_bold)
	# clock
	text_c(vp.x * 0.5, y + 22, engine.display_clock(), 17, C_GOLD, f_bold)
	var half_txt := "1ST HALF" if engine.half == 1 else "2ND HALF"
	if engine.phase == "half_time":
		half_txt = "HALF TIME"
	elif engine.phase == "full_time":
		half_txt = "FULL TIME"
	text_c(vp.x * 0.5, y + 77, half_txt, 10, C_DIM, f_med)
	# possession bar under the panel
	var pos: Vector2 = engine.possession_pct()
	pos.y = 100.0 - pos.x
	var bar := Rect2(x + 18, y + h + 8, w - 36, 5)
	draw_rect(bar, Color(1, 1, 1, 0.08))
	var split: float = bar.size.x * pos.x / 100.0
	draw_rect(Rect2(bar.position, Vector2(split, bar.size.y)), engine.kit_color(0))
	draw_rect(Rect2(bar.position + Vector2(split, 0), Vector2(bar.size.x - split, bar.size.y)), engine.kit_color(1))
	if game.mode == "highlights" and game.fast_mode and not game.paused and game.match_time > 9.0:
		var sw := 226.0
		var sx := vp.x * 0.5 - sw * 0.5
		var pulse := 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
		rect(Color(0.03, 0.05, 0.06, 0.82), Rect2(sx, vp.y - 156, sw, 26), 6, Color(1, 1, 1, 0.10))
		text_c(vp.x * 0.5, vp.y - 138, "SIMULATING  ·  NEXT CHANCE", 11, Color(0.62, 0.82, 0.86, pulse), f_bold)
	if game.replay_banner > 0.0:
		var rw := 126.0
		var rxp := vp.x * 0.5 - rw * 0.5
		rect(Color(0.12, 0.09, 0.03, 0.95), Rect2(rxp, y + h + 34, rw, 24), 6, Color(0.96, 0.78, 0.30, 0.35))
		text_c(vp.x * 0.5, y + h + 51, "◀  REPLAY", 12, C_GOLD, f_bold)
	var pct_a := int(round(pos.x))
	text(Vector2(bar.position.x, y + h + 26), "%d%%" % pct_a, 11, C_DIM, f_bold)
	text_r(bar.position.x + bar.size.x, y + h + 26, "%d%%" % (100 - pct_a), 11, C_DIM, f_bold)

func _badge(r: Rect2, t: int) -> void:
	var d: Dictionary = engine.teams[t]["data"]
	rect(d["color"].darkened(0.25), r, 10, Color(1, 1, 1, 0.14))
	draw_rect(Rect2(r.position.x + 3, r.position.y + 3, r.size.x - 6, 10), d["color"].lightened(0.10))
	var code: String = d["abbr"]
	var w: float = f_bold.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var col: Color = Kits.ink(d["color"].lightened(0.10))
	text(Vector2(r.position.x + r.size.x * 0.5 - w * 0.5, r.position.y + r.size.y * 0.62), code, 17, col, f_bold)

func _draw_meta(vp: Vector2) -> void:
	var x := 24.0
	var y := 24.0
	rect(C_PANEL, Rect2(x, y, 286, 96), 10, Color(1, 1, 1, 0.07))
	draw_rect(Rect2(x + 1, y + 12, 3, 30), C_GOLD)
	var home: Dictionary = engine.teams[0]["data"]
	var venue := str(home.get("stadium", "")).to_upper()
	var city := str(home.get("city", "")).to_upper()
	text(Vector2(x + 14, y + 23), "%s  ·  %s" % [venue, city], 13, C_TEXT, f_bold)
	text(Vector2(x + 14, y + 40), "PREMIER LEAGUE  ·  ATT. %s" % _thousands(int(home.get("capacity", 0))), 9, C_DIM, f_med)
	text(Vector2(x + 14, y + 56), "REFEREE", 9, C_DIM, f_bold)
	text(Vector2(x + 70, y + 56), engine.referee_name, 10, C_TEXT, f_bold)
	var btn := Rect2(x + 12, y + 68, 262, 20)
	var hovered := btn.has_point(mouse)
	rect(C_PANEL_LIGHT if hovered else Color(0.05, 0.07, 0.09, 0.92), btn, 5, Color(1, 1, 1, 0.12 if hovered else 0.05))
	text(Vector2(x + 20, y + 82), "CHANGE TEAMS", 10, C_TEXT if hovered else C_DIM, f_bold)
	text_r(x + 266, y + 82, "T", 9, C_GOLD, f_bold)
	_add_button("teams", btn, "CHANGE TEAMS", "T")

func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

# ------------------------------------------------------------------ stats ----

func _draw_stats(vp: Vector2) -> void:
	var w := 300.0
	var x := vp.x - 24.0 - w
	var y := 24.0
	var col_home := x + w * 0.40
	var col_away := x + w * 0.72
	rect(C_PANEL, Rect2(x, y, w, 132), 10, Color(1, 1, 1, 0.07))
	text(Vector2(x + 14, y + 21), "MATCH STATS", 11, C_DIM, f_bold)
	# Team abbreviations sit centred on the value columns below them.
	text_c(col_home, y + 21, engine.teams[0]["data"]["abbr"], 12, engine.teams[0]["data"]["color"].lightened(0.35), f_bold)
	text_c(col_away, y + 21, engine.teams[1]["data"]["abbr"], 12, engine.teams[1]["data"]["color"].lightened(0.35), f_bold)
	draw_line(Vector2(x + 14, y + 28), Vector2(x + w - 14, y + 28), Color(1, 1, 1, 0.07), 1)
	var s0: Dictionary = engine.stats[0]
	var s1: Dictionary = engine.stats[1]
	var rows := [
		["SHOTS", str(s0["shots"]), str(s1["shots"])],
		["ON TARGET", str(s0["on_target"]), str(s1["on_target"])],
		["xG", "%.2f" % s0["xg"], "%.2f" % s1["xg"]],
		["CORNERS", str(s0["corners"]), str(s1["corners"])],
		["FOULS", str(s0["fouls"]), str(s1["fouls"])],
	]
	var yy := y + 45.0
	for row in rows:
		text(Vector2(x + 14, yy), str(row[0]), 10, C_DIM, f_med)
		text_c(col_home, yy, str(row[1]), 15, C_TEXT, f_bold)
		text_c(col_away, yy, str(row[2]), 15, C_TEXT, f_bold)
		draw_line(Vector2(x + 14, yy + 5), Vector2(x + w - 14, yy + 5), Color(1, 1, 1, 0.05), 1)
		yy += 18.0

# --------------------------------------------------------------- controls ----

func _add_button(id: String, r: Rect2, label: String, hint: String) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "hint": hint})

func _draw_controls(vp: Vector2) -> void:
	var bar := HudLayout.controls_rect(vp)
	var bw: float = HudLayout.CONTROL_W
	var gap: float = HudLayout.CONTROL_GAP
	var x: float = bar.position.x
	var y: float = bar.position.y
	var h: float = bar.size.y
	var specs := [
		["pause", "PAUSE" if not game.paused else "RESUME", "SPACE"],
		["speed", "%sx" % _speed_label(), "1-4"],
		["mode", "HIGHLIGHTS" if game.mode == "highlights" else "FULL MATCH", "H"],
		["skip", "SKIP", "S"],
		["camera", "FOLLOW" if game.camera_follow else "WIDE", "C"],
		["restart", "RESTART", "R"],
	]
	for i in range(specs.size()):
		var r := Rect2(x + i * (bw + gap), y, bw, h)
		var hovered := r.has_point(mouse)
		var active: bool = specs[i][0] == "mode" and game.mode == "highlights"
		var bg: Color = C_PANEL_LIGHT if hovered else C_PANEL
		if active:
			bg = Color(0.16, 0.13, 0.05, 0.96)
		rect(bg, r, 8, Color(1, 1, 1, 0.10 if hovered else 0.06))
		if active:
			draw_rect(Rect2(r.position.x + 2, r.position.y + r.size.y - 3, r.size.x - 4, 2), C_GOLD)
		text_c(r.position.x + r.size.x * 0.5, r.position.y + 22, specs[i][1], 13, C_TEXT if hovered else Color(0.85, 0.90, 0.92), f_bold)
		text_c(r.position.x + r.size.x * 0.5, r.position.y + 36, specs[i][2], 9, C_DIM, f_med)
		_add_button(specs[i][0], r, specs[i][1], specs[i][2])

func _speed_label() -> String:
	if game.mode == "highlights" and game.fast_mode:
		return "SIM"
	var s: float = game.speed
	if s == int(s):
		return str(int(s))
	return "%.1f" % s

func button_at(p: Vector2) -> String:
	if manager_card != null and manager_card.button_at(p):
		return "manager_card"
	for b in buttons:
		if (b["rect"] as Rect2).has_point(p):
			return b["id"]
	return ""

# ---------------------------------------------------------------- status ----

func _draw_status(vp: Vector2) -> void:
	var x := vp.x - 24.0 - 300.0
	var y := vp.y - 72.0
	var label := ""
	var col := C_DIM
	if game.paused:
		label = "PAUSED"
		col = C_GOLD
	elif game.mode == "highlights" and game.fast_mode:
		label = "HIGHLIGHTS  ·  SIMMING 24x"
		col = Color(0.55, 0.82, 0.86)
	elif game.mode == "highlights":
		label = "HIGHLIGHTS  ·  LIVE"
		col = Color(0.62, 0.88, 0.66)
	else:
		label = "FULL MATCH  ·  %sx" % _speed_label()
		col = C_DIM
	text_r(vp.x - 24.0, y + 16, label, 11, col, f_bold)
	text_r(vp.x - 24.0, y + 32, "HOVER A PLAYER  ·  CLICK TO TRACK THEIR MATCH", 9, C_DIM, f_med)

# ------------------------------------------------------------------ focus ----

func _draw_focus(vp: Vector2) -> void:
	if game.focus_id < 0:
		return
	var p = engine.by_id.get(game.focus_id, null)
	if p == null:
		return
	var w := 286.0
	var h := 452.0
	var x := vp.x - 12.0 - w
	var y := 176.0
	rect(C_PANEL, Rect2(x, y, w, h), 12, Color(1, 1, 1, 0.10))
	var team: Dictionary = engine.teams[p.team]["data"]
	draw_rect(Rect2(x + 1, y + 1, w - 2, 4), team["color"])
	# header
	text(Vector2(x + 14, y + 27), "#%d" % p.number, 16, C_GOLD, f_bold)
	text(Vector2(x + 44, y + 28), p.name.to_upper(), 17, C_TEXT, f_bold)
	text(Vector2(x + 14, y + 47), "%s  ·  %s" % [team["name"].to_upper(), p.pos_label], 9, C_DIM, f_med)
	var ovr: String = str(p.attr["ovr"])
	text_r(x + w - 14, y + 29, ovr, 24, C_TEXT, f_bold)
	text_r(x + w - 14, y + 45, "OVR", 8, C_DIM, f_bold)
	# attributes
	var attrs := [["PAC", "pac"], ["SHO", "sho"], ["PAS", "pas"], ["DRI", "dri"], ["DEF", "def"], ["PHY", "phy"]]
	if p.is_gk:
		attrs = [["DIV", "div"], ["HAN", "han"], ["KIC", "kic"], ["REF", "ref"], ["SPD", "spd"]]
	var ay := y + 68.0
	text(Vector2(x + 14, ay), "ATTRIBUTES", 9, C_DIM, f_bold)
	ay += 10.0
	for a in attrs:
		var val: float = float(p.gk[a[1]]) if p.is_gk else float(p.attr[a[1]])
		text(Vector2(x + 14, ay + 10), a[0], 9, C_DIM, f_bold)
		draw_rect(Rect2(x + 46, ay + 2, 168, 6), Color(1, 1, 1, 0.07))
		draw_rect(Rect2(x + 46, ay + 2, 168 * val / 100.0, 6), team["color"].lerp(Color.WHITE, 0.10))
		text_r(x + w - 14, ay + 10, str(int(val)), 10, C_TEXT, f_bold)
		ay += 15.0
	# match numbers
	ay += 8.0
	draw_line(Vector2(x + 16, ay), Vector2(x + w - 16, ay), Color(1, 1, 1, 0.07), 1)
	ay += 14.0
	var st: Dictionary = p.stats
	var pass_txt := "%d/%d" % [st["passes_ok"], st["passes"]]
	var cells := [
		["PASSES", pass_txt], ["SHOTS", str(st["shots"])], ["TACKLES", str(st["tackles"])],
		["TOUCHES", str(st["touches"])], ["DIST", "%.1f km" % (st["distance"] / 1000.0)], ["RATING", "%.1f" % _rating(p)],
	]
	var cw := (w - 28) / 3.0
	for i in range(cells.size()):
		var cx := x + 14 + (i % 3) * cw
		var cy := ay + int(i / 3) * 34
		text(Vector2(cx, cy), cells[i][0], 8, C_DIM, f_bold)
		text(Vector2(cx, cy + 16), cells[i][1], 15, C_TEXT, f_bold)
	ay += 76.0
	# involvements
	text(Vector2(x + 14, ay), "MATCH INVOLVEMENTS", 9, C_DIM, f_bold)
	ay += 8.0
	var list: Array = p.involvements
	var start := maxi(0, list.size() - 7)
	for i in range(start, list.size()):
		var inv: Dictionary = list[i]
		var ty: float = ay + 16 + (i - start) * 17
		text(Vector2(x + 14, ty), "%d'" % int(inv["minute"]), 9, C_GOLD, f_bold)
		var txt: String = str(inv["text"])
		if txt.length() > 32:
			txt = txt.substr(0, 31) + "…"
		text(Vector2(x + 40, ty), txt, 9, Color(0.84, 0.89, 0.91), f_med)
	text(Vector2(x + 14, y + h - 12), "CLICK PLAYER AGAIN TO CLEAR", 8, C_DIM, f_med)

func _rating(p) -> float:
	var st: Dictionary = p.stats
	var r := 6.0
	r += st["goals"] * 1.2 + st["assists"] * 0.7 + st["shots"] * 0.12
	r += st["passes_ok"] * 0.006 + st["tackles"] * 0.12
	r -= st["fouls"] * 0.05
	return clampf(r, 4.0, 10.0)

# ---------------------------------------------------------------- tooltip ----

func _draw_tooltip(vp: Vector2) -> void:
	if game.hover_id < 0 or game.focus_id == game.hover_id:
		return
	var p = engine.by_id.get(game.hover_id, null)
	if p == null:
		return
	var w := 258.0
	var h := 128.0
	var x: float = mouse.x + 18.0
	var y: float = mouse.y + 16.0
	if x + w > vp.x - 8:
		x = mouse.x - w - 18.0
	if y + h > vp.y - 8:
		y = mouse.y - h - 16.0
	rect(Color(0.03, 0.05, 0.06, 0.97), Rect2(x, y, w, h), 10, Color(1, 1, 1, 0.14))
	var team: Dictionary = engine.teams[p.team]["data"]
	draw_rect(Rect2(x + 1, y + 1, w - 2, 3), team["color"])
	text(Vector2(x + 14, y + 26), p.name, 17, C_TEXT, f_bold)
	text(Vector2(x + 14, y + 42), "%s  ·  %s  ·  #%d" % [team["name"].to_upper(), p.pos_label, p.number], 9, C_DIM, f_med)
	text_r(x + w - 14, y + 28, str(p.attr["ovr"]), 22, C_GOLD, f_bold)
	var attrs := [["PAC", "pac"], ["SHO", "sho"], ["PAS", "pas"], ["DRI", "dri"], ["DEF", "def"], ["PHY", "phy"]]
	if p.is_gk:
		attrs = [["DIV", "div"], ["HAN", "han"], ["REF", "ref"]]
	var ax := x + 14.0
	var ay := y + 62.0
	for a in attrs:
		var val: float = float(p.gk[a[1]]) if p.is_gk else float(p.attr[a[1]])
		text(Vector2(ax, ay), a[0], 8, C_DIM, f_bold)
		draw_rect(Rect2(ax, ay + 5, 30, 4), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(ax, ay + 5, 30 * val / 100.0, 4), team["color"].lightened(0.15))
		text(Vector2(ax, ay + 20), str(int(val)), 9, C_TEXT, f_bold)
		ax += 39.0
	text(Vector2(x + 14, y + 100), "PASSES", 8, C_DIM, f_bold)
	text(Vector2(x + 62, y + 100), "%d/%d" % [p.stats["passes_ok"], p.stats["passes"]], 10, C_TEXT, f_med)
	text(Vector2(x + 120, y + 100), "SHOTS", 8, C_DIM, f_bold)
	text(Vector2(x + 162, y + 100), str(p.stats["shots"]), 10, C_TEXT, f_med)
	text(Vector2(x + 14, y + 118), "CLICK TO TRACK THIS PLAYER", 8, C_GOLD, f_med)

# ---------------------------------------------------------------- banners ----

func _draw_event_banners(vp: Vector2) -> void:
	if engine.phase == "goal":
		var gk: Dictionary = engine.last_goal
		if not gk.is_empty():
			var t: int = int(gk.get("team", 0))
			var col: Color = engine.teams[t]["data"]["color"]
			var bw := 720.0
			var bh := 128.0
			var x := vp.x * 0.5 - bw * 0.5
			var y := vp.y * 0.5 - bh * 0.5 - 40
			rect(Color(0.02, 0.03, 0.04, 0.92), Rect2(x, y, bw, bh), 14, Color(1, 1, 1, 0.12))
			draw_rect(Rect2(x + 1, y + 1, 8, bh - 2), col)
			text(Vector2(x + 32, y + 64), "GOAL", 64, Color(1, 1, 1), f_bold)
			text(Vector2(x + 200, y + 48), str(gk.get("scorer", "")), 22, Color(1, 1, 1), f_bold)
			var team_name: String = engine.teams[t]["data"]["name"].to_upper()
			text(Vector2(x + 200, y + 72), "%s  ·  %d'" % [team_name, int(gk.get("minute", 0))], 12, Color(0.8, 0.85, 0.88), f_med)
			text(Vector2(x + 200, y + 98), "%s %d  –  %d %s" % [engine.teams[0]["data"]["abbr"], engine.score[0], engine.score[1], engine.teams[1]["data"]["abbr"]], 14, C_GOLD, f_bold)
	if engine.phase == "half_time" or engine.phase == "full_time":
		var bw2 := 460.0
		var bh2 := 190.0
		var x2 := vp.x * 0.5 - bw2 * 0.5
		var y2 := vp.y * 0.5 - bh2 * 0.5
		rect(Color(0.02, 0.03, 0.04, 0.94), Rect2(x2, y2, bw2, bh2), 14, Color(1, 1, 1, 0.12))
		var title := "HALF TIME" if engine.phase == "half_time" else "FULL TIME"
		text_c(vp.x * 0.5, y2 + 48, title, 30, C_GOLD, f_bold)
		text_c(vp.x * 0.5, y2 + 104, "%d  –  %d" % [engine.score[0], engine.score[1]], 48, C_TEXT, f_bold)
		text_c(vp.x * 0.5, y2 + 132, "%s  ·  %s" % [engine.teams[0]["data"]["abbr"], engine.teams[1]["data"]["abbr"]], 11, C_DIM, f_med)
		var sub := "SECOND HALF STARTS SHORTLY" if engine.phase == "half_time" else "PRESS R TO PLAY AGAIN"
		text_c(vp.x * 0.5, y2 + 168, sub, 10, C_DIM, f_med)

func _draw_intro(vp: Vector2) -> void:
	if engine.clock > 90.0 or engine.phase in ["full_time", "half_time", "goal"]:
		return
	var a: float = clampf(1.0 - (game.match_time - 6.5) / 2.0, 0.0, 1.0)
	if a <= 0.01:
		return
	var w := 690.0
	var h := 96.0
	var x := 24.0 - (1.0 - a) * 30.0
	var y := vp.y - 300.0
	var bg := Color(0.03, 0.05, 0.06, 0.94 * a)
	rect(bg, Rect2(x, y, w, h), 10, Color(1, 1, 1, 0.10 * a))
	draw_rect(Rect2(x + 1, y + 1, 6, h - 2), Color(engine.teams[0]["data"]["color"].r, engine.teams[0]["data"]["color"].g, engine.teams[0]["data"]["color"].b, a))
	draw_rect(Rect2(x + w - 7, y + 1, 6, h - 2), Color(engine.teams[1]["data"]["color"].r, engine.teams[1]["data"]["color"].g, engine.teams[1]["data"]["color"].b, a))
	var home: Dictionary = engine.teams[0]["data"]
	var away: Dictionary = engine.teams[1]["data"]
	text(Vector2(x + 22, y + 26), "PREMIER LEAGUE  ·  %s  ·  %s" % [str(home.get("stadium", "")).to_upper(), str(home.get("city", "")).to_upper()], 11, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, a), f_bold)
	text(Vector2(x + 22, y + 56), str(home["name"]).to_upper(), 26, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, a), f_bold)
	text_c(x + w * 0.5, y + 54, "v", 16, Color(C_DIM.r, C_DIM.g, C_DIM.b, a), f_med)
	text_r(x + w - 22, y + 56, str(away["name"]).to_upper(), 26, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, a), f_bold)
	text(Vector2(x + 22, y + 78), "%s  ·  %s" % [home["formation"], str(home["manager"]).to_upper()], 10, Color(C_DIM.r, C_DIM.g, C_DIM.b, a), f_med)
	text_r(x + w - 22, y + 78, "%s  ·  %s" % [away["formation"], str(away["manager"]).to_upper()], 10, Color(C_DIM.r, C_DIM.g, C_DIM.b, a), f_med)

func _draw_paused(vp: Vector2) -> void:
	if not game.paused:
		return
	var w := 260.0
	var h := 54.0
	var x := vp.x * 0.5 - w * 0.5
	var y := vp.y * 0.5 - h * 0.5
	if engine.phase in ["goal", "half_time"]:
		y = 116.0
	rect(Color(0.02, 0.03, 0.04, 0.88), Rect2(x, y, w, h), 12, Color(0.96, 0.78, 0.30, 0.55))
	text_c(vp.x * 0.5, y + 25, "PAUSED", 20, C_GOLD, f_bold)
	text_c(vp.x * 0.5, y + 42, "PRESS SPACE TO RESUME", 9, C_DIM, f_med)

func _draw_vignette(vp: Vector2) -> void:
	# subtle broadcast frame
	draw_rect(Rect2(0, 0, vp.x, 3), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(0, vp.y - 3, vp.x, 3), Color(0, 0, 0, 0.35))
