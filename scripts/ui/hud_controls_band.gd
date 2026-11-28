class_name HudControlsBand
extends RefCounted


func controls(p: HudPaint, c: CanvasItem, game, touch: bool, mouse: Vector2, f_bold: Font, f_med: Font, phase: String = "") -> void:
	var bar := HudLayout.controls_rect(p.vp, touch)
	var bw: float = HudLayout.control_width(p.vp, touch)
	var gap: float = HudLayout.CONTROL_GAP
	var per: int = HudLayout.controls_per_row(p.vp, touch)
	var over: bool = phase == "full_time"


	var held: bool = over and game != null and bool(game.result_hold)
	var watch: bool = MatchBilling.league_watch(game)
	var specs := control_specs(p, game, touch, phase, held)
	for i in range(specs.size()):
		var spec: Array = specs[i]


		var dead: bool = not bool(spec[3])
		var row := i / per
		var r := Rect2(bar.position.x + float(i % per) * (bw + gap),
			bar.position.y + float(row) * (HudLayout.CONTROL_H + gap), bw, HudLayout.CONTROL_H)
		var hovered := not dead and r.has_point(mouse)


		var active: bool = (over and not held and spec[0] == "restart") \
			or (not over and spec[0] == "mode" and game.mode == "highlights") \
			or (not over and spec[0] == "skip" and game.get("skip_armed") == true)
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


		if not touch and not (dead and (held or watch)):
			p.text_c(c, r.position.x + r.size.x * 0.5, r.position.y + 36, spec[2], 9, UiChrome.C_DIM if not dead else Color(UiChrome.C_DIM.r, UiChrome.C_DIM.g, UiChrome.C_DIM.b, 0.35), f_med)
		if not dead:
			p.add_button(spec[0], r, spec[1], spec[2])


func control_specs(p: HudPaint, game, touch: bool, phase: String = "", held: bool = false) -> Array:
	var over: bool = phase == "full_time"
	var watch: bool = MatchBilling.league_watch(game)
	var speed_hint: String = "1-4"
	if game.mode != "full" and game.fast_mode:
		speed_hint = ""
	var specs := [
		["pause", "PAUSE" if not game.paused else "RESUME", "SPACE", not over],
		["speed", speed_label(game), speed_hint, not over],
		["mode", Prefs.mode_label(game.mode), "H", true],
		["skip", "STOP" if game.get("skip_armed") == true else "SKIP", "S", not over],
		["camera", "FOLLOW" if game.camera_follow else "WIDE", "C", true],
		["league", "LEAGUE", "L", true],
		["restart", "PLAY AGAIN" if over else "RESTART", "R", not (over and held) and not watch],
		["menu", "MENU", "M", true],
	]
	if touch or p.compact():
		specs.append(["teams", "TEAMS", "CLUBS", not watch])


	if over and held:
		for spec in specs:
			spec[3] = false
	return specs


func speed_label(game) -> String:
	if game.mode != "full" and game.fast_mode:
		return "SIM"
	var s: float = game.speed
	if s == int(s):
		return "%dx" % int(s)
	return "%.1fx" % s
