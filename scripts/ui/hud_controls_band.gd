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
	var specs := control_specs(p, game, touch, phase)
	var over: bool = phase == "full_time"
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
		# Live play marks HIGHLIGHTS; at the whistle PLAY AGAIN is the way on.
		var active: bool = (over and spec[0] == "restart") \
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
		if not touch:
			p.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 36, spec[2], 9, UiChrome.C_DIM if not dead else Color(UiChrome.C_DIM.r, UiChrome.C_DIM.g, UiChrome.C_DIM.b, 0.35), f_med)
		if not dead:
			p.add_button(spec[0], r, spec[1], spec[2])

## `[id, label, key-or-tap hint, answers-presses]` per door, in bar order. Once
## the whistle has gone there is no play to pause, pace or skip, so those three
## doors are painted dead (`phase` is the engine's own). The restart door then
## reads PLAY AGAIN so the card's hint names a control that is on the bar (#276).
func control_specs(p: HudPaint, game, touch: bool, phase: String = "") -> Array:
	var over: bool = phase == "full_time"
	var specs := [
		["pause", "PAUSE" if not game.paused else "RESUME", "SPACE", not over],
		["speed", "%sx" % speed_label(game), "1-4", not over],
		["mode", Prefs.mode_label(game.mode), "H", true],
		["skip", "SKIP", "S", not over],
		["camera", "FOLLOW" if game.camera_follow else "WIDE", "C", true],
		["league", "LEAGUE", "L", true],
		["restart", "PLAY AGAIN" if over else "RESTART", "R", true],
		["menu", "MENU", "M", true],
	]
	if touch or p.compact():
		specs.append(["teams", "TEAMS", "CLUBS", true])
	return specs

func speed_label(game) -> String:
	if game.mode != "full" and game.fast_mode:
		return "SIM"
	var s: float = game.speed
	if s == int(s):
		return str(int(s))
	return "%.1f" % s
