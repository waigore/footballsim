class_name HudBannersBand
extends RefCounted

## Case banners over the pitch: the goal card, the half/full-time card, the
## opening team sheet that fades out, the paused card and the broadcast vignette.

var touch := false

func events(p: HudPaint, c: CanvasItem, engine, f_bold: Font, f_med: Font) -> void:
	if engine.phase == "goal":
		_goal(p, c, engine, f_bold, f_med)
	if engine.phase == "half_time" or engine.phase == "full_time":
		_break(p, c, engine, f_bold, f_med)

func _goal(p: HudPaint, c: CanvasItem, engine, f_bold: Font, f_med: Font) -> void:
	var gk: Dictionary = engine.last_goal
	if gk.is_empty():
		return
	var t: int = int(gk.get("team", 0))
	var bw: float = minf(720.0, p.vp.x - 48.0)
	var bh := 128.0
	var x := p.vp.x * 0.5 - bw * 0.5
	var y := p.vp.y * 0.5 - bh * 0.5 - 40
	p.panel(c, Color(0.02, 0.03, 0.04, 0.92), Rect2(x, y, bw, bh), 14, Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(x + 1, y + 1, 8, bh - 2), engine.teams[t]["data"]["color"])
	var gx: float = x + minf(200.0, bw * 0.28)
	p.text(c, Vector2(x + 32, y + 64), "GOAL", 64, Color(1, 1, 1), f_bold)
	p.text(c, Vector2(gx, y + 48), str(gk.get("scorer", "")), 22, Color(1, 1, 1), f_bold)
	var team_name: String = engine.teams[t]["data"]["name"].to_upper()
	p.text(c, Vector2(gx, y + 72), "%s  ·  %d'" % [team_name, int(gk.get("minute", 0))], 12, Color(0.8, 0.85, 0.88), f_med)
	p.text(c, Vector2(gx, y + 98), "%s %d  –  %d %s" % [engine.teams[0]["data"]["abbr"], engine.score[0], engine.score[1], engine.teams[1]["data"]["abbr"]], 14, UiChrome.C_GOLD, f_bold)

func _break(p: HudPaint, c: CanvasItem, engine, f_bold: Font, f_med: Font) -> void:
	var bw: float = minf(460.0, p.vp.x - 48.0)
	var bh := 190.0
	var x := p.vp.x * 0.5 - bw * 0.5
	var y := p.vp.y * 0.5 - bh * 0.5
	p.panel(c, Color(0.02, 0.03, 0.04, 0.94), Rect2(x, y, bw, bh), 14, Color(1, 1, 1, 0.12))
	var title := "HALF TIME" if engine.phase == "half_time" else "FULL TIME"
	p.text_c(c, p.vp.x * 0.5, y + 48, title, 30, UiChrome.C_GOLD, f_bold)
	p.text_c(c, p.vp.x * 0.5, y + 104, "%d  –  %d" % [engine.score[0], engine.score[1]], 48, UiChrome.C_TEXT, f_bold)
	p.text_c(c, p.vp.x * 0.5, y + 132, "%s  ·  %s" % [engine.teams[0]["data"]["abbr"], engine.teams[1]["data"]["abbr"]], 11, UiChrome.C_DIM, f_med)
	var sub := "SECOND HALF STARTS SHORTLY" if engine.phase == "half_time" else ("TAP RESTART TO PLAY AGAIN" if touch else "PRESS R TO PLAY AGAIN")
	p.text_c(c, p.vp.x * 0.5, y + 168, sub, 10, UiChrome.C_DIM, f_med)

## Opening team sheet; waits out the kickoff and fades across the first seconds.
func intro(p: HudPaint, c: CanvasItem, engine, game, f_bold: Font, f_med: Font) -> void:
	if engine.clock > 90.0 or engine.phase in ["full_time", "half_time", "goal"]:
		return
	var a: float = clampf(1.0 - (game.match_time - 6.5) / 2.0, 0.0, 1.0)
	if a <= 0.01:
		return
	var w: float = minf(690.0, p.vp.x - 48.0)
	var h := 96.0
	var x := 24.0 - (1.0 - a) * 30.0
	var y := p.vp.y - 300.0
	p.panel(c, Color(0.03, 0.05, 0.06, 0.94 * a), Rect2(x, y, w, h), 10, Color(1, 1, 1, 0.10 * a))
	var home: Dictionary = engine.teams[0]["data"]
	var away: Dictionary = engine.teams[1]["data"]
	c.draw_rect(Rect2(x + 1, y + 1, 6, h - 2), _alpha(home["color"], a))
	c.draw_rect(Rect2(x + w - 7, y + 1, 6, h - 2), _alpha(away["color"], a))
	p.text(c, Vector2(x + 22, y + 26), "FOOTBALL SIM  ·  PREMIER LEAGUE  ·  %s  ·  %s" % [str(home.get("stadium", "")).to_upper(), str(home.get("city", "")).to_upper()], 11, _alpha(UiChrome.C_GOLD, a), f_bold)
	p.text(c, Vector2(x + 22, y + 56), str(home["name"]).to_upper(), 26, _alpha(UiChrome.C_TEXT, a), f_bold)
	p.text_c(c, x + w * 0.5, y + 54, "v", 16, _alpha(UiChrome.C_DIM, a), f_med)
	p.text_r(c, x + w - 22, y + 56, str(away["name"]).to_upper(), 26, _alpha(UiChrome.C_TEXT, a), f_bold)
	p.text(c, Vector2(x + 22, y + 78), "%s  ·  %s" % [home["formation"], str(home["manager"]).to_upper()], 10, _alpha(UiChrome.C_DIM, a), f_med)
	p.text_r(c, x + w - 22, y + 78, "%s  ·  %s" % [away["formation"], str(away["manager"]).to_upper()], 10, _alpha(UiChrome.C_DIM, a), f_med)

func paused(p: HudPaint, c: CanvasItem, engine, game, f_bold: Font, f_med: Font) -> void:
	if not game.paused:
		return
	var w := 260.0
	var h := 54.0
	var x := p.vp.x * 0.5 - w * 0.5
	var y := p.vp.y * 0.5 - h * 0.5
	if engine.phase in ["goal", "half_time"]:
		y = 116.0
	p.panel(c, Color(0.02, 0.03, 0.04, 0.88), Rect2(x, y, w, h), 12, Color(0.96, 0.78, 0.30, 0.55))
	p.text_c(c, p.vp.x * 0.5, y + 25, "PAUSED", 20, UiChrome.C_GOLD, f_bold)
	p.text_c(c, p.vp.x * 0.5, y + 42, "TAP RESUME TO CARRY ON" if touch else "PRESS SPACE TO RESUME", 9, UiChrome.C_DIM, f_med)

func vignette(p: HudPaint, c: CanvasItem) -> void:
	# subtle broadcast frame
	c.draw_rect(Rect2(0, 0, p.vp.x, 3), Color(0, 0, 0, 0.35))
	c.draw_rect(Rect2(0, p.vp.y - 3, p.vp.x, 3), Color(0, 0, 0, 0.35))

static func _alpha(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, a)
