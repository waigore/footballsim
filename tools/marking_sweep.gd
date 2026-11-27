extends SceneTree

## Witness for the `marking` opposition instruction (wiki Live tactics:
## `zonal` / `man` — "man-marking radius (30 m vs 26 m)").
##
## Staged geometry sweep: one home striker stands a fixed distance from the away
## goal, one away centre-back stands `gap` metres further out, and the ball sits
## beyond them both — the picture where a defender may legally step out to a man
## (a mark upfield of the ball is refused by the block's own guard). For each
## cell it records the mark handed out and the target the defender runs to, under
## `zonal` and under `man`.
##
##   godot --headless --path . --script res://tools/marking_sweep.gd
##
## Only the 26–30 m band can tell the two instructions apart: inside 26 m both
## reach, beyond 30 m neither does. A whole match cannot resolve it — one
## defender's mark moves a metre or two inside a chaotic picture.

func _init() -> void:
	var cells := 0
	var differs := 0
	var zonal_marks := 0
	var man_marks := 0
	var band_hits := 0
	for gap in [14.0, 18.0, 22.0, 25.0, 26.5, 28.0, 29.5, 33.0]:
		for ay in [0.38, 0.46, 0.54, 0.62]:
			var z: Dictionary = _cell(gap, ay, "zonal")
			var m: Dictionary = _cell(gap, ay, "man")
			cells += 1
			if z["mark"] >= 0:
				zonal_marks += 1
			if m["mark"] >= 0:
				man_marks += 1
			if gap > 26.0 and gap < 30.0:
				band_hits += 1
				var line := "gap=%4.1f ay=%.2f  zonal %s  man %s  z=(%.1f,%.1f) m=(%.1f,%.1f)" % [
					gap, ay,
					"MARK " if z["mark"] >= 0 else "free ",
					"MARK " if m["mark"] >= 0 else "free ",
					z["target"].x, z["target"].y, m["target"].x, m["target"].y]
				if z["mark"] != m["mark"]:
					line += "  <- assignment differs"
				print(line)
			if z["target"].distance_to(m["target"]) > 0.05:
				differs += 1
	print("CELLS %d  band cells=%d  zonal marks=%d  man marks=%d  TARGET DIFFERS=%d" % [
		cells, band_hits, zonal_marks, man_marks, differs])
	quit()

## One cell: away (team 1) defends and carries the instruction; its right
## centre-back is `gap` metres from a home striker who has dropped goal-side of
## the ball.
func _cell(gap: float, ay: float, instruction: String) -> Dictionary:
	var eng := MatchEngine.new(770)
	eng.phase = "play"
	eng.possession_team = 0
	# Park every other body out of the picture so only this pair is read.
	for q in eng.players:
		if q.sent_off or q.is_gk:
			continue
		q.pos = Vector2(eng.L * 0.02 if q.team == 1 else eng.L * 0.98, 1.0 + float(q.id % 66))
	var own: Vector2 = eng.own_goal_pos(1)
	var dir: float = 1.0 if own.x < eng.L * 0.5 else -1.0
	var runner = null
	for q in eng.players:
		if q.team == 0 and q.role == "ST":
			runner = q
			break
	runner.pos = own + Vector2(dir * 36.0, eng.W * ay - eng.W * 0.5)
	var back = null
	for q in eng.players:
		if q.team == 1 and q.role == "RCB":
			back = q
			break
	back.pos = runner.pos - Vector2(dir * gap, 0.0)
	# The ball sits beyond the pair, away from the away goal: the block's guard
	# refuses a mark that is further upfield than the ball.
	eng.ball.pos = own + Vector2(dir * 46.0, 0.0)
	eng.ball.owner_id = -1
	eng.ball.vel = Vector2.ZERO
	var t: Tactics = eng.manager.tactics_for(1)
	t.opposition["marking"] = instruction
	eng.live_style[1] = t.style()
	eng.brain._assign_marks()
	var mark: int = back.mark_id
	eng.brain._update_shapes()
	return {"target": back.target, "mark": mark}
