extends "res://scripts/sim/match_engine_pitch.gd"


func _start_restart(kind: String, team: int, pos: Vector2, delay: float = -1.0) -> void:
	pass


func _update_restart(dt: float) -> void:
	pass


func _offside(p) -> void:
	pass


func _injure(p) -> void:
	pass

func _vlog(msg: String) -> void:
	if verbose:
		print("[%6.2f] %s" % [clock, msg])

func _nearest_teammate_to(pos: Vector2, t: int, include_gk: bool = false, exclude_id: int = -1):
	var best = null
	var bd = 1e9
	for p in players:
		if p.team != t or p.sent_off or p.id == exclude_id:
			continue
		if p.is_gk and not include_gk:
			continue
		var d = p.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best

func elapsed_minutes() -> float:
	return clock / 60.0

func display_clock() -> String:
	if phase == "shootout":
		return "PENALTIES"
	if half >= 3:

		var end_clock: float = 6300.0 if half == 3 else 7200.0
		var board: String = "105:00" if half == 3 else "120:00"
		if clock <= end_clock:
			return "%02d:%02d" % [int(clock) / 60, int(clock) % 60]
		return "%s +%02d:%02d" % [board, int(clock - end_clock) / 60, int(clock - end_clock) % 60]
	if half == 1:
		if clock <= 2700.0:
			return "%02d:%02d" % [int(clock) / 60, int(clock) % 60]
		return "45:00 +%02d:%02d" % [int(clock - 2700.0) / 60, int(clock - 2700.0) % 60]
	if clock <= 5400.0:
		return "%02d:%02d" % [int(clock) / 60, int(clock) % 60]
	return "90:00 +%02d:%02d" % [int(clock - 5400.0) / 60, int(clock - 5400.0) % 60]

func minute_of(t: float) -> int:
	return clampi(int(ceil(t / 60.0)), 1, 120)


var goal_sheet: Array = []


func _emit(kind: String, text: String, team: int, player, extra: Dictionary = {}) -> void:
	ev_seq += 1
	var e = {
		"id": ev_seq, "type": kind, "text": text, "team": team,
		"player": player.name if player != null else "",
		"player_id": player.id if player != null else -1,
		"minute": minute_of(clock), "clock": clock, "pos": ball.pos,
	}
	for k in extra.keys():
		e[k] = extra[k]
	events.append(e)
	if events.size() > 600:
		events.pop_front()
	if kind == "goal":
		goal_sheet.append({
			"team": team, "minute": minute_of(clock),
			"scorer": player.name if player != null else "Unknown",
			"own_goal": bool(extra.get("own_goal", false)),
		})
	MatchStats.bump(momentum, team, kind, float(extra.get("xg", 0.0)))
	_official_reacts(kind, player)
	event_fired.emit(e)


func _official_reacts(kind: String, player) -> void:
	if not kind in ["foul", "card", "offside", "handball", "penalty", "penalty_taken",
			"kickoff", "half_time", "full_time", "injury"]:
		return
	referee.whistle = 0.8
	if player != null:
		referee.focus = player.pos
		referee.focus_t = 1.8


func _update_referee(dt: float) -> void:
	var r = referee
	r.whistle = maxf(0.0, r.whistle - dt)
	if r.focus_t > 0.0:
		r.focus_t -= dt
	var target: Vector2
	if r.focus_t > 0.0:
		target = r.focus + Vector2(0.0, 2.6)
	else:
		var dir: float = float(attacking_dir(possession_team))
		target = ball.pos - Vector2(dir * REF_TRAIL, 0.0)
		target.y += REF_SIDE if ball.pos.y <= W * 0.5 else -REF_SIDE
	target.x = clampf(target.x, 3.0, L - 3.0)
	target.y = clampf(target.y, 3.0, W - 3.0)
	var to: Vector2 = target - r.pos
	var d: float = to.length()
	var cap: float = REF_SPRINT if d > 20.0 else REF_JOG
	var desired := Vector2.ZERO
	if d > 0.5:
		desired = to / d * minf(cap, d * 1.8)
	var dv: Vector2 = desired - r.vel
	var acc: float = 11.0 * dt
	if dv.length() > acc:
		dv = dv.normalized() * acc
	r.vel += dv
	r.pos += r.vel * dt
	if r.vel.length() > 0.5:
		r.facing = r.vel.normalized()
	elif r.pos.distance_to(ball.pos) > 0.1:
		r.facing = (ball.pos - r.pos).normalized()

func _add_involvement(p, kind: String, text: String, pos: Vector2) -> void:
	if p == null:
		return
	p.involvements.append({"t": clock, "minute": minute_of(clock), "type": kind, "text": text, "pos": pos})

func _flash(v: float) -> void:
	flash = maxf(flash, v)

func possession_pct() -> Vector2:
	var tot: float = stats[0]["possession"] + stats[1]["possession"]
	if tot < 0.01:
		return Vector2(50, 50)
	var a: float = float(stats[0]["possession"]) / tot * 100.0
	return Vector2(snappedf(a, 0.1), snappedf(100.0 - a, 0.1))


func momentum_level() -> Vector2:
	return MatchStats.momentum_level(momentum)

func summary() -> Dictionary:
	return {
		"score": score.duplicate(), "half": half, "clock": display_clock(),
		"possession": possession_pct(), "stats": stats.duplicate(true),
		"events": events.size(), "phase": phase,

		"momentum": MatchStats.momentum_level(momentum),
	}
