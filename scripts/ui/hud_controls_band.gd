class_name HudControlsBand
extends RefCounted

## Bottom control bar: one door per broadcast action, wrapped onto extra rows on
## a narrow design space, plus the label and key/tap hint each door shows. The
## bar carries the teams door on touch/compact because the fixture card that
## holds it on desktop is not drawn there.

func controls(p: HudPaint, c: CanvasItem, game, touch: bool, mouse: Vector2, f_bold: Font, f_med: Font, phase: String = "") -> void:
	var bar := HudLayout.controls_rect(p.vp, touch)
	var bw: float = HudLayout.control_width(p.vp, touch)
	var gap: float = HudLayout.CONTROL_GAP
	var per: int = HudLayout.controls_per_row(p.vp, touch)
	var over: bool = phase == "full_time"
	# A watched league fixture's result is already in the ledger: the held card
	# owns every press and every key until it is read, so the whole strip is
	# painted dead rather than advertising a `PLAY AGAIN` and an `R` the season
	# swallows (#124, #311).
	var held: bool = over and game != null and bool(game.result_hold)
	var specs := control_specs(p, game, touch, phase, held)
	for i in range(specs.size()):
		var spec: Array = specs[i]
		# A door with nothing left to do keeps its box but not its press: the
		# strip does not jump at the whistle, and a finished match offers no
		# control that would only stamp PAUSED over the result (#276).
		var dead: bool = not bool(spec[3])
		var row := i / per
		var r := Rect2(bar.position.x + float(i % per) * (bw + gap),
			bar.position.y + float(row) * (HudLayout.CONTROL_H + gap), bw, HudLayout.CONTROL_H)
		var hovered := not dead and r.has_point(mouse)
		# Live play marks HIGHLIGHTS; at the whistle PLAY AGAIN is the way on —
		# unless the season is holding the result, when there is no way on here.
		var active: bool = (over and not held and spec[0] == "restart") \
			or (not over and spec[0] == "mode" and game.mode == "highlights")
		var fill: Color = UiChrome.C_PANEL_LIGHT if hovered else UiChrome.C_PANEL
		if active:
			fill = Color(0.16, 0.13, 0.05, 0.96)
		if dead:
			fill = Color(0.03, 0.045, 0.055, 0.72)
		p.panel(c, fill, r, 8, Color(1, 1, 1, 0.10 if hovered else 0.06))
		if active:
			c.draw_rect(Rect2(r.position.x + 2, r.position.y + r.size.y - 3, r.size.x - 4, 2), UiChrome.C_GOLD)
		var ink: Color = UiChrome.C_TEXT if hovered else Color(0.85, 0.90, 0.92)
		if dead:
			ink = Color(UiChrome.C_DIM.r, UiChrome.C_DIM.g, UiChrome.C_DIM.b, 0.55)
		var cap_y: float = r.position.y + (r.size.y * 0.5 + 5.0 if touch else 22.0)
		p.text_c(c, r.position.x + r.size.x * 0.5, cap_y, spec[1], 13, ink, f_bold)
		# A key hint is a promise the key works. The held card's own keys are the
		# season's (SPACE / ENTER / ESC), so while one owns the screen the strip
		# prints no key at all — #276's dimmed dead doors keep theirs, because
		# those keys are inert but the match's own (#311).
		if not touch and not (held and dead):
			p.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 36, spec[2], 9, UiChrome.C_DIM if not dead else Color(UiChrome.C_DIM.r, UiChrome.C_DIM.g, UiChrome.C_DIM.b, 0.35), f_med)
		if not dead:
			p.add_button(spec[0], r, spec[1], spec[2])

## `[id, label, key-or-tap hint, answers-presses]` per door, in bar order. Once
## the whistle has gone there is no play to pause, pace or skip, so those three
## doors are painted dead (`phase` is the engine's own). The restart door then
## reads PLAY AGAIN so the card's hint names a control that is on the bar (#276).
## A watched league fixture's result stays in the ledger, so `held` paints the
## whole strip dead: the held card owns every press and every key until it is
## read (SPACE / ENTER / ESC, the season's own), and a bar that offers doors it
## cannot answer — `PLAY AGAIN` above all, a finished result cannot be replayed —
## promises actions the game will swallow (#124, #311).
## The key hint names what a press changes: while a replay view fast-forwards
## the clock runs at the director's own rate, so 1-4 would promise a control
## the bar does not have (#265).
func control_specs(p: HudPaint, game, touch: bool, phase: String = "", held: bool = false) -> Array:
	var over: bool = phase == "full_time"
	var speed_hint: String = "1-4"
	if game.mode != "full" and game.fast_mode:
		speed_hint = ""
	var specs := [
		["pause", "PAUSE" if not game.paused else "RESUME", "SPACE", not over],
		["speed", speed_label(game), speed_hint, not over],
		["mode", Prefs.mode_label(game.mode), "H", true],
		["skip", "SKIP", "S", not over],
		["camera", "FOLLOW" if game.camera_follow else "WIDE", "C", true],
		["league", "LEAGUE", "L", true],
		["restart", "PLAY AGAIN" if over else "RESTART", "R", not (over and held)],
		["menu", "MENU", "M", true],
	]
	if touch or p.compact():
		specs.append(["teams", "TEAMS", "CLUBS", true])
	# The held season result swallows every press and every key (SPACE / ENTER /
	# ESC are the card's own), so no door on the strip can answer: each keeps its
	# box and its caption — the shape #276 gave the play doors at the whistle —
	# and stops advertising a key or taking a press (#311).
	if over and held:
		for spec in specs:
			spec[3] = false
	return specs

## The speed door's caption: the player's own multiplier, or the word the state
## line above the bar uses while a replay view sims. It never glues the
## multiplier's `x` onto that word (#265).
func speed_label(game) -> String:
	if game.mode != "full" and game.fast_mode:
		return "SIM"
	var s: float = game.speed
	if s == int(s):
		return "%dx" % int(s)
	return "%.1fx" % s
