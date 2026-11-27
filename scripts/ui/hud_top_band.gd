class_name HudTopBand
extends RefCounted


func scoreboard(p: HudPaint, c: CanvasItem, engine, game, f_bold: Font, f_med: Font) -> void:
	var bar := HudLayout.scoreboard_rect(p.vp)
	var x := bar.position.x
	var y := bar.position.y
	var w := bar.size.x
	var h := bar.size.y
	var cxm: float = x + w * 0.5
	p.panel(c, Color(0, 0, 0, 0.30), Rect2(x + 4, y + 6, w, h), 14, Color(0, 0, 0, 0))
	p.panel(c, UiChrome.C_PANEL, bar, 14, Color(1, 1, 1, 0.10))

	c.draw_rect(Rect2(x + 2, y + 2, 5, h - 4), engine.teams[0]["data"]["color"])
	c.draw_rect(Rect2(x + w - 7, y + 2, 5, h - 4), engine.teams[1]["data"]["color"])

	_badge(p, c, engine, Rect2(x + 22, y + 19, 48, 48), 0, f_bold)

	p.text(c, Vector2(x + 82, y + 44), engine.teams[0]["data"]["abbr"], 30,
		LeagueInterestMark.ink(p.followed, str(engine.teams[0]["id"])), f_bold)
	p.text(c, Vector2(x + 82, y + 64), engine.teams[0]["data"]["name"].to_upper(), 11, UiChrome.C_DIM, f_med)

	p.add_button("team_0", Rect2(x + 14, y + 14, 190, 58), "HOME CLUB", "CLUB")

	_badge(p, c, engine, Rect2(x + w - 70, y + 19, 48, 48), 1, f_bold)
	p.text_r(c, x + w - 82, y + 44, engine.teams[1]["data"]["abbr"], 30,
		LeagueInterestMark.ink(p.followed, str(engine.teams[1]["id"])), f_bold)
	p.text_r(c, x + w - 82, y + 64, engine.teams[1]["data"]["name"].to_upper(), 11, UiChrome.C_DIM, f_med)
	p.add_button("team_1", Rect2(x + w - 204, y + 14, 190, 58), "AWAY CLUB", "CLUB")

	p.text_c(c, cxm, y + 52, "%d  –  %d" % [engine.score[0], engine.score[1]], 40, UiChrome.C_TEXT, f_bold)

	p.text_c(c, cxm, y + 22, engine.display_clock(), 17, UiChrome.C_GOLD, f_bold)
	var half_txt := "1ST HALF"
	match engine.half:
		2:
			half_txt = "2ND HALF"
		3:
			half_txt = "EXTRA TIME"
		4:
			half_txt = "EXTRA TIME 2"
	if engine.phase == "half_time":
		half_txt = "HALF TIME"
	elif engine.phase == "full_time":
		half_txt = "FULL TIME"
	elif engine.phase == "et_break":
		half_txt = "EXTRA TIME"
	elif engine.phase == "shootout":
		half_txt = "PENALTIES"
	p.text_c(c, cxm, y + 77, half_txt, 10, UiChrome.C_DIM, f_med)
	_possession(p, c, engine, Rect2(x + 18, y + h + 8, w - 36, 5), y + h, f_bold)


func _possession(p: HudPaint, c: CanvasItem, engine, bar_r: Rect2, panel_bottom: float, f_bold: Font) -> void:
	var pos: Vector2 = engine.possession_pct()
	pos.y = 100.0 - pos.x
	c.draw_rect(bar_r, Color(1, 1, 1, 0.08))
	var split: float = bar_r.size.x * pos.x / 100.0
	c.draw_rect(Rect2(bar_r.position, Vector2(split, bar_r.size.y)), engine.kit_color(0))
	c.draw_rect(Rect2(bar_r.position + Vector2(split, 0), Vector2(bar_r.size.x - split, bar_r.size.y)), engine.kit_color(1))
	var pct_a := int(round(pos.x))
	p.text(c, Vector2(bar_r.position.x, panel_bottom + 26), "%d%%" % pct_a, 11, UiChrome.C_DIM, f_bold)
	p.text_r(c, bar_r.position.x + bar_r.size.x, panel_bottom + 26, "%d%%" % (100 - pct_a), 11, UiChrome.C_DIM, f_bold)


func flags(p: HudPaint, c: CanvasItem, game, touch: bool, f_bold: Font, phase: String = "") -> void:
	if chip_shown(game.mode, game.fast_mode, game.paused, game.match_time, phase):
		var band := HudLayout.pitch_band(p.vp, touch)
		var chip_y: float = band.position.y + 6.0 if p.compact() else p.vp.y - 156.0
		var sw := 226.0
		var sx := p.vp.x * 0.5 - sw * 0.5
		var pulse := 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
		p.panel(c, Color(0.03, 0.05, 0.06, 0.82), Rect2(sx, chip_y, sw, 26), 6, Color(1, 1, 1, 0.10))
		p.text_c(c, p.vp.x * 0.5, chip_y + 18.0, sim_chip_label(game.mode), 11, Color(0.62, 0.82, 0.86, pulse), f_bold)
	if game.replay_banner > 0.0:
		var ry: float = HudLayout.scoreboard_rect(p.vp).end.y + 34
		var rw := 126.0
		var rxp := p.vp.x * 0.5 - rw * 0.5
		p.panel(c, Color(0.12, 0.09, 0.03, 0.95), Rect2(rxp, ry, rw, 24), 6, Color(0.96, 0.78, 0.30, 0.35))
		p.text_c(c, p.vp.x * 0.5, ry + 17, "◀  REPLAY", 12, UiChrome.C_GOLD, f_bold)


static func sim_chip_label(mode: String) -> String:
	return "SIMULATING  ·  NEXT GOAL" if mode == "goals" else "SIMULATING  ·  NEXT CHANCE"


static func chip_shown(mode: String, fast: bool, paused: bool, match_time: float, phase: String) -> bool:
	if phase == "full_time" or paused or match_time <= 9.0:
		return false
	return mode != "full" and fast

func _badge(p: HudPaint, c: CanvasItem, engine, r: Rect2, t: int, f_bold: Font) -> void:
	var d: Dictionary = engine.teams[t]["data"]
	p.panel(c, d["color"].darkened(0.25), r, 10, Color(1, 1, 1, 0.14))
	c.draw_rect(Rect2(r.position.x + 3, r.position.y + 3, r.size.x - 6, 10), d["color"].lightened(0.10))
	var code: String = d["abbr"]
	var w: float = f_bold.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var col: Color = Kits.ink(d["color"].lightened(0.10))
	p.text(c, Vector2(r.position.x + r.size.x * 0.5 - w * 0.5, r.position.y + r.size.y * 0.62), code, 17, col, f_bold)


func meta(p: HudPaint, c: CanvasItem, engine, game, touch: bool, mouse: Vector2, f_bold: Font, f_med: Font) -> void:
	if touch or p.compact():
		return
	var x := 24.0
	var y := 24.0
	p.panel(c, UiChrome.C_PANEL, Rect2(x, y, 286, 96), 10, Color(1, 1, 1, 0.07))
	c.draw_rect(Rect2(x + 1, y + 12, 3, 30), UiChrome.C_GOLD)
	var home: Dictionary = engine.teams[0]["data"]
	var venue := str(home.get("stadium", "")).to_upper()
	var city := str(home.get("city", "")).to_upper()
	UiChrome.wordmark(c, Vector2(x + 14, y + 16), 13, f_bold)
	p.text(c, Vector2(x + 14, y + 33), "%s  ·  %s" % [venue, city], 13, UiChrome.C_TEXT, f_bold)
	p.text(c, Vector2(x + 14, y + 47), "%s  ·  ATT. %s" % [billing_name(game, engine), thousands(int(home.get("capacity", 0)))], 9, UiChrome.C_DIM, f_med)
	p.text(c, Vector2(x + 14, y + 60), "REFEREE", 9, UiChrome.C_DIM, f_bold)
	p.text(c, Vector2(x + 70, y + 60), engine.referee_name, 10, UiChrome.C_TEXT, f_bold)
	var btn := Rect2(x + 12, y + 68, 262, 20)
	var hovered := btn.has_point(mouse)
	p.panel(c, UiChrome.C_PANEL_LIGHT if hovered else Color(0.05, 0.07, 0.09, 0.92), btn, 5, Color(1, 1, 1, 0.12 if hovered else 0.05))


	p.add_button("teams", btn, "CHANGE TEAMS", "T")


static func billing_name(game, engine) -> String:
	var binding = game.get("billing") if game != null else null
	if binding is MatchBilling:
		return (binding as MatchBilling).chrome_name()
	var home: Dictionary = engine.teams[0]["data"]
	return str(home.get("competition_short", MatchBilling.FRIENDLY))

static func thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
