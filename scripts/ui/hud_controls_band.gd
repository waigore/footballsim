class_name HudControlsBand
extends RefCounted

## Bottom control bar: one door per broadcast action, wrapped onto extra rows on
## a narrow design space, plus the label and key/tap hint each door shows. The
## bar carries the teams door on touch/compact because the fixture card that
## holds it on desktop is not drawn there.

func controls(p: HudPaint, c: CanvasItem, game, touch: bool, mouse: Vector2, f_bold: Font, f_med: Font) -> void:
	var bar := HudLayout.controls_rect(p.vp, touch)
	var bw: float = HudLayout.control_width(p.vp, touch)
	var gap: float = HudLayout.CONTROL_GAP
	var per: int = HudLayout.controls_per_row(p.vp, touch)
	var specs := control_specs(p, game, touch)
	for i in range(specs.size()):
		var row := i / per
		var r := Rect2(bar.position.x + float(i % per) * (bw + gap),
			bar.position.y + float(row) * (HudLayout.CONTROL_H + gap), bw, HudLayout.CONTROL_H)
		var hovered := r.has_point(mouse)
		var active: bool = specs[i][0] == "mode" and game.mode == "highlights"
		p.panel(c, (UiChrome.C_PANEL_LIGHT if hovered else UiChrome.C_PANEL) if not active else Color(0.16, 0.13, 0.05, 0.96),
			r, 8, Color(1, 1, 1, 0.10 if hovered else 0.06))
		if active:
			c.draw_rect(Rect2(r.position.x + 2, r.position.y + r.size.y - 3, r.size.x - 4, 2), UiChrome.C_GOLD)
		var cap_y: float = r.position.y + (r.size.y * 0.5 + 5.0 if touch else 22.0)
		p.text_c(c, r.position.x + r.size.x * 0.5, cap_y, specs[i][1], 13, UiChrome.C_TEXT if hovered else Color(0.85, 0.90, 0.92), f_bold)
		if not touch:
			p.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 36, specs[i][2], 9, UiChrome.C_DIM, f_med)
		p.add_button(specs[i][0], r, specs[i][1], specs[i][2])

## `[id, label, key-or-tap hint]` per door, in bar order.
func control_specs(p: HudPaint, game, touch: bool) -> Array:
	# The key hint names what a press changes: while a replay view fast-forwards
	# the clock runs at the director's own rate, so 1-4 would promise a control
	# the bar does not have (#265).
	var speed_hint: String = "1-4"
	if game.mode != "full" and game.fast_mode:
		speed_hint = ""
	var specs := [
		["pause", "PAUSE" if not game.paused else "RESUME", "SPACE"],
		["speed", speed_label(game), speed_hint],
		["mode", Prefs.mode_label(game.mode), "H"],
		["skip", "SKIP", "S"],
		["camera", "FOLLOW" if game.camera_follow else "WIDE", "C"],
		["league", "LEAGUE", "L"],
		["restart", "RESTART", "R"],
		["menu", "MENU", "M"],
	]
	if touch or p.compact():
		specs.append(["teams", "TEAMS", "CLUBS"])
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
