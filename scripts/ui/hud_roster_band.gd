class_name HudRosterBand
extends RefCounted

## Roster side of the broadcast: token numbers and surnames on the pitch, the
## match-stats card, the play-state line under the controls and the hovered
## player's tooltip. All read-only views of the engine; no overlay state.
## Design-space multiplier the overlay layer is scaled up by.
var ui_scale := 1.0
var touch := false
var mouse := Vector2.ZERO

## Screen-space world position read in the overlay's design units.
func w2s(p: HudPaint, c: CanvasItem, pos: Vector2) -> Vector2:
	return c.get_viewport().get_canvas_transform() * pos / maxf(ui_scale, 0.001)

func world_labels(p: HudPaint, c: CanvasItem, engine, game, f_bold: Font) -> void:
	var canvas := c.get_viewport().get_canvas_transform()
	var zoom: float = canvas.get_scale().x
	var s: float = maxf(ui_scale, 0.001)
	var show_names: bool = game.names_visible and (not p.compact() or zoom > 14.0)
	var ball_pos: Vector2 = engine.ball.pos
	var r: float = 0.86 * zoom * game.token_scale / s
	var ns: int = clampi(int(r * 0.95), 10, 24)
	# On a phone the tokens are dots at the wide framing: a 10-unit number is
	# wider than the body it sits on, so numbers wait for a zoomed-in view.
	var draw_num: bool = not p.compact() or r >= 6.0
	for pl in engine.players:
		if pl.sent_off:
			continue
		var near: bool = pl.pos.distance_to(ball_pos) < 26.0 or pl.id == game.focus_id or pl.id == game.hover_id
		var sp: Vector2 = w2s(p, c, pl.pos - Vector2(0, pl.z * 0.55))
		if sp.x < -40 or sp.x > p.vp.x + 40 or sp.y < -40 or sp.y > p.vp.y + 40:
			continue
		# shirt number
		if not draw_num:
			continue
		var num := str(pl.number)
		var nw: float = f_bold.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
		var ncol: Color = Color(1, 1, 1, 0.96) if pl.team == 0 else Color(0.08, 0.12, 0.16, 0.96)
		var kit: Dictionary = engine.teams[pl.team].get("kit", {})
		if pl.is_gk:
			ncol = Kits.ink(engine.teams[pl.team]["data"]["gk_color"])
		elif not kit.is_empty():
			ncol = Kits.ink(kit.get("shirt", engine.teams[pl.team]["data"]["color"]))
		p.text(c, Vector2(sp.x - nw * 0.5, sp.y + ns * 0.36), num, ns, ncol, f_bold, 2, Color(0, 0, 0, 0.35))
		# surnames
		if show_names and near and pl.id != game.focus_id:
			var fs: int = clampi(int(zoom / s * 1.02), 9, 15)
			var sw: float = f_bold.get_string_size(pl.surname_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var ny: float = sp.y + r + fs * 0.95
			p.text(c, Vector2(sp.x - sw * 0.5, ny), pl.surname_text(), fs, Color(0.97, 0.99, 0.99, 0.92), f_bold, 4, Color(0.00, 0.02, 0.02, 0.85))

func stats(p: HudPaint, c: CanvasItem, engine, f_bold: Font, f_med: Font) -> void:
	var box := HudLayout.stats_rect(p.vp)
	var w := box.size.x
	var x := box.position.x
	var y := box.position.y
	var col_home := x + w * 0.40
	var col_away := x + w * 0.72
	p.panel(c, UiChrome.C_PANEL, box, 10, Color(1, 1, 1, 0.07))
	p.text(c, Vector2(x + 14, y + 21), "MATCH STATS", 11, UiChrome.C_DIM, f_bold)
	# Team abbreviations sit centred on the value columns below them.
	p.text_c(c, col_home, y + 21, engine.teams[0]["data"]["abbr"], 12, engine.teams[0]["data"]["color"].lightened(0.35), f_bold)
	p.text_c(c, col_away, y + 21, engine.teams[1]["data"]["abbr"], 12, engine.teams[1]["data"]["color"].lightened(0.35), f_bold)
	c.draw_line(Vector2(x + 14, y + 28), Vector2(x + w - 14, y + 28), Color(1, 1, 1, 0.07), 1)
	var s0: Dictionary = engine.stats[0]
	var s1: Dictionary = engine.stats[1]
	var rows := [
		["SHOTS", str(s0["shots"]), str(s1["shots"])],
		["ON TARGET", str(s0["on_target"]), str(s1["on_target"])],
		["xG", "%.2f" % s0["xg"], "%.2f" % s1["xg"]],
		["CORNERS", str(s0["corners"]), str(s1["corners"])],
		["FOULS", str(s0["fouls"]), str(s1["fouls"])],
	]
	var rows_n := HudLayout.stats_row_limit(p.vp)
	if rows_n < rows.size():
		rows = rows.slice(0, rows_n)
	var step: float = 16.0 if p.compact() else 18.0
	var yy := y + 45.0
	for row in rows:
		p.text(c, Vector2(x + 14, yy), str(row[0]), 10, UiChrome.C_DIM, f_med)
		p.text_c(c, col_home, yy, str(row[1]), 15, UiChrome.C_TEXT, f_bold)
		p.text_c(c, col_away, yy, str(row[2]), 15, UiChrome.C_TEXT, f_bold)
		c.draw_line(Vector2(x + 14, yy + 5), Vector2(x + w - 14, yy + 5), Color(1, 1, 1, 0.05), 1)
		yy += step

## Play-state line: paused, highlights simming, or the full-match speed.
func status(p: HudPaint, c: CanvasItem, game, speed_label: String, f_bold: Font, f_med: Font) -> void:
	var y := p.vp.y - 72.0
	var label := ""
	var col := UiChrome.C_DIM
	if game.paused:
		label = "PAUSED"
		col = UiChrome.C_GOLD
	elif game.mode == "highlights" and game.fast_mode:
		label = "HIGHLIGHTS  ·  SIMMING 24x"
		col = Color(0.55, 0.82, 0.86)
	elif game.mode == "highlights":
		label = "HIGHLIGHTS  ·  LIVE"
		col = Color(0.62, 0.88, 0.66)
	else:
		label = "FULL MATCH  ·  %sx" % speed_label
	if p.compact():
		# One line, level with the commentary ticker: the key-hint row it sits
		# under on desktop would run into the control bar here.
		p.text_r(c, p.vp.x - 24.0, y - 24.0, label, 11, col, f_bold)
		return
	p.text_r(c, p.vp.x - 24.0, y + 16, label, 11, col, f_bold)
	p.text_r(c, p.vp.x - 24.0, y + 32, "HOVER A PLAYER  ·  CLICK TO TRACK THEIR MATCH", 9, UiChrome.C_DIM, f_med)

## Hovered player's dossier card, offset from the pointer and flipped near edges.
func tooltip(p: HudPaint, c: CanvasItem, engine, game, f_bold: Font, f_med: Font) -> void:
	if game.hover_id < 0 or game.focus_id == game.hover_id:
		return
	var pl = engine.by_id.get(game.hover_id, null)
	if pl == null:
		return
	var w := 258.0
	var h := 128.0
	var x: float = mouse.x + 18.0
	var y: float = mouse.y + 16.0
	if x + w > p.vp.x - 8:
		x = mouse.x - w - 18.0
	if y + h > p.vp.y - 8:
		y = mouse.y - h - 16.0
	p.panel(c, Color(0.03, 0.05, 0.06, 0.97), Rect2(x, y, w, h), 10, Color(1, 1, 1, 0.14))
	var team: Dictionary = engine.teams[pl.team]["data"]
	c.draw_rect(Rect2(x + 1, y + 1, w - 2, 3), team["color"])
	p.text(c, Vector2(x + 14, y + 26), pl.name, 17, UiChrome.C_TEXT, f_bold)
	p.text(c, Vector2(x + 14, y + 42), "%s  ·  %s  ·  #%d" % [team["name"].to_upper(), pl.pos_label, pl.number], 9, UiChrome.C_DIM, f_med)
	p.text_r(c, x + w - 14, y + 28, str(pl.attr["ovr"]), 22, UiChrome.C_GOLD, f_bold)
	var attrs := [["PAC", "pac"], ["SHO", "sho"], ["PAS", "pas"], ["DRI", "dri"], ["DEF", "def"], ["PHY", "phy"]]
	if pl.is_gk:
		attrs = [["DIV", "div"], ["HAN", "han"], ["REF", "ref"]]
	var ax := x + 14.0
	var ay := y + 62.0
	for a in attrs:
		var val: float = float(pl.gk[a[1]]) if pl.is_gk else float(pl.attr[a[1]])
		p.text(c, Vector2(ax, ay), a[0], 8, UiChrome.C_DIM, f_bold)
		c.draw_rect(Rect2(ax, ay + 5, 30, 4), Color(1, 1, 1, 0.08))
		c.draw_rect(Rect2(ax, ay + 5, 30 * val / 100.0, 4), team["color"].lightened(0.15))
		p.text(c, Vector2(ax, ay + 20), str(int(val)), 9, UiChrome.C_TEXT, f_bold)
		ax += 39.0
	p.text(c, Vector2(x + 14, y + 100), "PASSES", 8, UiChrome.C_DIM, f_bold)
	p.text(c, Vector2(x + 62, y + 100), "%d/%d" % [pl.stats["passes_ok"], pl.stats["passes"]], 10, UiChrome.C_TEXT, f_med)
	p.text(c, Vector2(x + 120, y + 100), "SHOTS", 8, UiChrome.C_DIM, f_bold)
	p.text(c, Vector2(x + 162, y + 100), str(pl.stats["shots"]), 10, UiChrome.C_TEXT, f_med)
	p.text(c, Vector2(x + 14, y + 118), "TAP TO TRACK THIS PLAYER" if touch else "CLICK TO TRACK THIS PLAYER", 8, UiChrome.C_GOLD, f_med)
