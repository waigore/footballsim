class_name HudBannersBand
extends RefCounted

## Case banners over the pitch: the goal card, the half/full-time card, the
## opening team sheet that fades out, the paused card and the broadcast vignette.

var touch := false
## The chrome has slid away (#158). A card's hint then cannot name a door that
## left with it, so the card becomes the door itself (#202).
var chrome_hidden := false

func events(p: HudPaint, c: CanvasItem, engine, game, f_bold: Font, f_med: Font) -> void:
	if engine.phase == "goal":
		_goal(p, c, engine, f_bold, f_med)
	if engine.phase == "half_time" or engine.phase == "full_time":
		_break(p, c, engine, game, f_bold, f_med)

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

func _break(p: HudPaint, c: CanvasItem, engine, game, f_bold: Font, f_med: Font) -> void:
	var sheet: Array = engine.goal_sheet
	var home_goals := 0
	var away_goals := 0
	for g in sheet:
		if int(g.get("team", 0)) == 0:
			home_goals += 1
		else:
			away_goals += 1
	# The card grows by the goals it can list and is capped at the band between
	# the scoreboard and the ticker, so a seven-goal game never covers either.
	var m: Dictionary = HudLayout.break_metrics(p.vp, home_goals, away_goals)
	var r: Rect2 = m["rect"]
	p.panel(c, Color(0.02, 0.03, 0.04, 0.94), r, 14, Color(1, 1, 1, 0.12))
	var cx: float = r.position.x + r.size.x * 0.5
	var title := "HALF TIME" if engine.phase == "half_time" else "FULL TIME"
	p.text_c(c, cx, r.position.y + float(m["title_y"]), title, int(m["title_size"]), UiChrome.C_GOLD, f_bold)
	p.text_c(c, cx, r.position.y + float(m["score_y"]), "%d  –  %d" % [engine.score[0], engine.score[1]], int(m["score_size"]), UiChrome.C_TEXT, f_bold)
	var compact := bool(m["compact"])
	if not compact and r.size.y >= HudLayout.BREAK_BASE_H:
		p.text_c(c, cx, r.position.y + float(m["abbr_y"]), "%s  ·  %s" % [engine.teams[0]["data"]["abbr"], engine.teams[1]["data"]["abbr"]], int(m["abbr_size"]), UiChrome.C_DIM, f_med)
	_goals(p, c, engine, r, m, f_med)
	# A league watch keeps this card until the player reads it (#124): the result
	# is in the save, and the season sheet is one tap behind the whistle.
	var held: bool = engine.phase == "full_time" and game != null and bool(game.result_hold)
	var sub := break_hint(str(engine.phase), touch, chrome_hidden, held)
	if float(m["sub_y"]) <= r.size.y - 4.0:
		p.text_c(c, cx, r.position.y + float(m["sub_y"]), sub, int(m["sub_size"]), UiChrome.C_DIM, f_med)
		if break_restarts(str(engine.phase), touch, chrome_hidden, held):
			# Nothing on screen carries RESTART while the chrome is hidden, so
			# the card the hint names is the door (#202).
			p.add_button("restart", r, sub, "")

## What the card says under the score. Every hint names a control the player can
## reach in this state: with the chrome hidden the bar's RESTART door and its
## key hint are gone, so a phone's card offers its own press instead (#202). The
## season's own SPACE stays live either way, because a key never leaves.
static func break_hint(phase: String, touch: bool, hidden: bool, held: bool) -> String:
	if phase == "half_time":
		return "SECOND HALF STARTS SHORTLY"
	if held:
		if touch:
			return "TAP TO RETURN TO THE SEASON"
		return "PRESS SPACE TO RETURN TO THE SEASON"
	if not touch:
		return "PRESS R TO PLAY AGAIN"
	if hidden:
		return "TAP THE CARD TO PLAY AGAIN"
	return "TAP RESTART TO PLAY AGAIN"

## Whether the full-time card is its own restart door: only on a phone, only
## while the chrome is hidden, and never over a league result the season holds.
static func break_restarts(phase: String, touch: bool, hidden: bool, held: bool) -> bool:
	return phase == "full_time" and touch and hidden and not held

## The goals that made the score, in the card's own space: two columns on a
## desktop scorecard (home left, visitors right) and two short entries per row on
## a phone, where each entry carries its club. Anything past the last row is
## counted (`+2`) instead of dropped silently.
func _goals(p: HudPaint, c: CanvasItem, engine, r: Rect2, m: Dictionary, f_med: Font) -> void:
	var rows: int = int(m["rows"])
	if rows <= 0:
		return
	var size: int = int(m["line_size"])
	var y0: float = r.position.y + float(m["rows_y"])
	var step: float = float(m["step"])
	if bool(m["compact"]):
		var entries: Array = []
		for g in engine.goal_sheet:
			entries.append(_entry(engine, g, true))
		var shown: int = mini(rows * int(m["per_row"]), entries.size())
		for i in range(rows):
			var from: int = i * int(m["per_row"])
			var to: int = mini(from + int(m["per_row"]), shown)
			if from >= to:
				break
			var line := "  ·  ".join(entries.slice(from, to))
			if i == rows - 1 and entries.size() > shown:
				line += "  +%d" % (entries.size() - shown)
			p.text_c(c, r.position.x + r.size.x * 0.5, y0 + step * float(i), line, size, UiChrome.C_TEXT, f_med)
		return
	var home: Array = []
	var away: Array = []
	for g in engine.goal_sheet:
		var entry := _entry(engine, g, false)
		if int(g.get("team", 0)) == 0:
			home.append(entry)
		else:
			away.append(entry)
	for i in range(rows):
		if i < home.size():
			var hl := str(home[i])
			if i == rows - 1 and home.size() > rows:
				hl += "  +%d" % (home.size() - rows)
			p.text(c, Vector2(r.position.x + 24.0, y0 + step * float(i)), hl, size, UiChrome.C_TEXT, f_med)
		if i < away.size():
			var al := str(away[i])
			if i == rows - 1 and away.size() > rows:
				al += "  +%d" % (away.size() - rows)
			p.text_r(c, r.end.x - 24.0, y0 + step * float(i), al, size, UiChrome.C_TEXT, f_med)

static func _entry(engine, g: Dictionary, with_club: bool) -> String:
	var name := str(g.get("scorer", "")).to_upper()
	if name == "":
		name = "UNKNOWN"
	if bool(g.get("own_goal", false)):
		name += " (OG)"
	var minute := int(g.get("minute", 0))
	if with_club:
		var t: int = clampi(int(g.get("team", 0)), 0, 1)
		return "%s %d'  %s" % [str(engine.teams[t]["data"]["abbr"]), minute, name]
	return "%d'  %s" % [minute, name]


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
	p.text(c, Vector2(x + 22, y + 26), "FOOTBALL SIM  ·  %s  ·  %s  ·  %s" % [HudTopBand.billing_name(game, engine), str(home.get("stadium", "")).to_upper(), str(home.get("city", "")).to_upper()], 11, _alpha(UiChrome.C_GOLD, a), f_bold)
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
	var r := Rect2(x, y, w, h)
	p.panel(c, Color(0.02, 0.03, 0.04, 0.88), r, 12, Color(0.96, 0.78, 0.30, 0.55))
	p.text_c(c, p.vp.x * 0.5, y + 25, "PAUSED", 20, UiChrome.C_GOLD, f_bold)
	p.text_c(c, p.vp.x * 0.5, y + 42, "TAP RESUME TO CARRY ON" if touch else "PRESS SPACE TO RESUME", 9, UiChrome.C_DIM, f_med)
	# RESUME rides the control bar, so a hidden chrome leaves the banner's own
	# copy pointing at a door nobody can see: the banner answers the tap instead
	# (#202). A whistle card keeps the press, because restart is the way on.
	if touch and chrome_hidden and engine.phase not in ["half_time", "full_time", "goal"]:
		p.add_button("pause", r, "RESUME", "")

func vignette(p: HudPaint, c: CanvasItem) -> void:
	# subtle broadcast frame
	c.draw_rect(Rect2(0, 0, p.vp.x, 3), Color(0, 0, 0, 0.35))
	c.draw_rect(Rect2(0, p.vp.y - 3, p.vp.x, 3), Color(0, 0, 0, 0.35))

static func _alpha(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, a)
