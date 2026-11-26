extends "res://scripts/sim/match_engine_decider.gd"

class_name MatchEngine

## A deterministic, full-Laws football match engine. The class is split across a
## chain of files (core → pitch → presentation → duels → actions → play → rules
## → clock); this leaf is the dead-ball lane. A restart's judgement (the taker's
## picture, his reading of it, and how long he holds play up) lives in
## MatchRestarts; this file places bodies, picks the taker and takes the kick.

func _start_restart(kind: String, team: int, pos: Vector2, delay: float = -1.0) -> void:
	if phase == "goal":
		return
	if kind == "goal_kick":
		pos = Vector2(5.5 if teams[team]["dir"] == 1 else L - 5.5, W * 0.5)
	elif kind == "penalty":
		pos = Vector2(L - PEN_D if teams[team]["dir"] == 1 else PEN_D, W * 0.5)
	phase = "restart"
	possession_team = team
	possession_loose = false
	stoppage_seq += 1
	ball.owner_id = -1
	ball.vel = Vector2.ZERO
	ball.vz = 0.0
	ball.z = 0.0
	ball.spin = 0.0
	ball.planned_goal = false
	ball.planned_save = false
	ball.pos = pos
	for q in players:
		q.offside_flag = false
	var taker = null
	if kind == "goal_kick":
		taker = _gk_of(team)
	elif kind == "penalty":
		taker = _best_penalty_taker(team)
	else:
		taker = _nearest_teammate_to(pos, team, kind == "goal_kick")
	var d = 2.2
	if delay > 0.0:
		d = delay
	match kind:
		"throw_in":
			d = 1.5
			stoppage_events += 1
		"corner":
			stats[team]["corners"] += 1
			MatchStats.bump(momentum, team, "corner")
			d = 3.2
			stoppage_events += 1
		"goal_kick":
			d = 2.4
		"free_kick":
			d = 2.8
			stoppage_events += 1
		"penalty":
			d = 3.6
			stoppage_events += 1
	restart = {"type": kind, "team": team, "pos": pos, "timer": d, "taker": taker.id if taker != null else -1,
		"base_delay": d, "wait": 0.0, "patience": MatchRestarts.patience(self, taker, kind, team), "called_wait": false}
	restart_timer = d
	if taker != null:
		taker.target = pos + (pos - own_goal_pos(team)).normalized() * 0.9
		taker.speed_scale = 1.0
		ball.last_touch_team = team
	# Push opponents the required distance away for a free kick.
	if kind in ["free_kick", "corner"]:
		var min_d = 9.15
		for q in players:
			if q.team == team or q.sent_off:
				continue
			var dq: float = q.pos.distance_to(pos)
			if dq < min_d:
				var away: Vector2 = (q.pos - pos).normalized()
				if away.length() < 0.1:
					away = Vector2(0, 1)
				q.pos = pos + away * (min_d + 0.4)
	elif kind == "penalty":
		_arrange_penalty(team, taker, pos)
	_vlog("RESTART %s team %s at (%.1f,%.1f)" % [kind, teams[team]["id"], pos.x, pos.y])
	_emit(kind, _restart_text(kind, team, taker), team, taker)
	# A dead ball is the manager's legal moment to change a player.
	if manager != null:
		manager.on_stoppage(kind, team)

## Before a penalty only the two keepers and the taker stay near the box:
## everyone else waits outside it, behind the ball.
func _arrange_penalty(team: int, taker, pos: Vector2) -> void:
	var dir: int = teams[team]["dir"]
	for q in players:
		if q.sent_off:
			continue
		if q.team != team and q.is_gk:
			continue
		if taker != null and q.id == taker.id:
			continue
		if q.is_gk:
			q.pos = Vector2(L - 0.5 if dir == 1 else 0.5, W * 0.5)
			q.target = q.pos
			continue
		var behind_x: float = pos.x - dir * (4.5 + rng.randf_range(0.0, 7.0))
		var yy = clampf(W * 0.5 + rng.randf_range(-14.0, 14.0), 3.0, W - 3.0)
		q.pos = Vector2(behind_x, yy)
		q.target = q.pos

func _restart_text(kind: String, team: int, taker) -> String:
	var who: String = taker.name if taker != null else ""
	return CommentaryRestarts.restart(rng, kind, teams[team]["data"]["short"], who, false)

func _best_penalty_taker(t: int):
	var best = null
	var bs = -1.0
	for p in players:
		if p.team != t or p.sent_off or p.is_gk:
			continue
		var s = float(p.attr["sho"]) * 1.4 + float(p.attr["ovr"])
		if s > bs:
			bs = s
			best = p
	return best

func _update_restart(dt: float) -> void:
	restart_timer -= dt
	brain.update_restart(dt, restart)
	var taker = by_id.get(restart.get("taker", -1), null)
	if taker != null and not taker.sent_off:
		var spot: Vector2 = restart["pos"]
		var stand: Vector2 = spot + (spot - own_goal_pos(taker.team)).normalized() * 0.75
		taker.target = stand
		taker.speed_scale = 1.0
		if restart["type"] == "penalty":
			taker.target = restart["pos"] + Vector2(-teams[taker.team]["dir"] * 2.2, 0)
			taker.pos = taker.target
	# attackers arrange for corners
	if restart["type"] == "corner":
		_arrange_corner(restart["team"], restart["pos"])
	if restart_timer <= 0.0:
		var ready := 1.0
		if taker != null and not taker.sent_off:
			var pic := MatchRestarts.picture(self, int(restart["team"]), taker, restart["pos"])
			ready = pic.x
			MatchRestarts.note_picture(restart, pic)
		if MatchRestarts.should_wait(self, restart, ready, taker):
			# Hold the restart: re-read the picture in short steps so the taker
			# kicks as soon as his side is set, not on a fixed delay.
			restart["wait"] = float(restart.get("wait", 0.0)) + MatchRestarts.WAIT_STEP
			restart_timer = MatchRestarts.WAIT_STEP
			if not bool(restart.get("called_wait", false)):
				restart["called_wait"] = true
				_emit("restart_wait",
					CommentaryRestarts.restart(rng, str(restart["type"]), teams[restart["team"]]["data"]["short"],
						taker.name if taker != null else "", true), int(restart["team"]), taker)
			if verbose:
				_vlog("RESTART WAIT %s ready=%.2f/%.2f waited=%.1f/%.1f" % [restart["type"], ready,
					MatchRestarts.ready_needed(self, taker), float(restart.get("wait", 0.0)), float(restart.get("patience", 0.0))])
		else:
			_execute_restart()

func _arrange_corner(team: int, corner: Vector2) -> void:
	var box_x = L - 8.0 if corner.x > L * 0.5 else 8.0
	var spots = [Vector2(box_x, 30.0), Vector2(box_x, 38.0), Vector2(box_x + (6.0 if corner.x > L * 0.5 else -6.0), 34.0), Vector2(box_x - (3.0 if corner.x > L * 0.5 else -3.0), 27.0)]
	var idx = 0
	for p in players:
		if p.team != team or p.sent_off or p.is_gk:
			continue
		if idx < spots.size() and (p.role in ["ST", "RCB", "LCB", "CAM", "RW", "LW", "RDM", "LDM"]):
			p.target = spots[idx]
			idx += 1

func _execute_restart() -> void:
	var kind: String = restart["type"]
	var team: int = restart["team"]
	var taker = by_id.get(restart.get("taker", -1), null)
	if taker == null or taker.sent_off:
		taker = _nearest_teammate_to(restart["pos"], team, true)
	if taker == null:
		phase = "play"
		return
	taker.pos = restart["pos"] - (restart["pos"] - own_goal_pos(team)).normalized() * 0.55
	ball.pos = restart["pos"]
	ball.owner_id = taker.id
	ball.last_touch_id = taker.id
	ball.last_touch_team = team
	phase = "play"
	possession_team = team
	possession_loose = false
	match kind:
		"kickoff":
			var mate = _nearest_teammate_to(taker.pos + Vector2(-teams[team]["dir"] * 6.0, 0.0), team, false, taker.id)
			if mate != null:
				pass_ball(taker, mate.pos + Vector2(-teams[team]["dir"] * 2.0, rng.randf_range(-1.0, 1.0)))
			else:
				_claim_ball(taker)
		"throw_in":
			var mate = _best_throw_target(team, taker)
			if mate != null:
				pass_ball(taker, mate.pos, true, mate)
			else:
				_claim_ball(taker)
		"goal_kick":
			var style: float = float(style_of(team)["possession"])
			if style > 0.58:
				var mate = _best_short_outlet(team, taker)
				if mate != null:
					pass_ball(taker, mate.pos, false, mate)
				else:
					_clear_long(taker, team)
			else:
				_clear_long(taker, team)
		"corner":
			var target = Vector2(L - 7.5 if restart["pos"].x > L * 0.5 else 7.5, _corner_aim(team) + rng.randf_range(-1.5, 1.5))
			var short: bool = manager != null and manager.tactics_for(team).corner_routine() == "short"
			var near = _nearest_teammate_to(restart["pos"] + Vector2(-teams[team]["dir"] * 6.0, 0.0), team, false, taker.id)
			if short and near != null:
				pass_ball(taker, near.pos, false, near)
			else:
				pass_ball(taker, target, true, null, "cross")
			stats[team]["crosses"] = stats[team].get("crosses", 0) + 1
		"free_kick":
			var goal: Vector2 = target_goal_pos(team)
			var d: float = taker.pos.distance_to(goal)
			var direct: bool = manager == null or manager.tactics_for(team).free_kick_routine() == "direct"
			var shoot_p: float = 0.45 if direct else 0.15
			if d < 27.0 and opponent_goal_angle(taker) > 0.16 and rng.randf() < shoot_p:
				shoot_ball(taker, rng.randf_range(-2.6, 2.6), rng.randf_range(0.4, 1.9), 1.0, "freekick")
			elif d < 45.0 and absf(taker.pos.y - W * 0.5) > 12.0:
				var target = Vector2(goal.x - teams[team]["dir"] * 8.0, W * 0.5 + rng.randf_range(-3.0, 3.0))
				pass_ball(taker, target, true, null, "cross")
			else:
				var mate = _best_short_outlet(team, taker)
				if mate != null:
					pass_ball(taker, mate.pos + Vector2(teams[team]["dir"] * 3.0, 0.0), false, mate)
				else:
					_claim_ball(taker)
		"penalty":
			_take_penalty(taker, team)
		_:
			_claim_ball(taker)

func _take_penalty(taker, team: int) -> void:
	var gk = _gk_of(1 - team)
	var side = 1.0 if rng.randf() < 0.5 else -1.0
	var aim_y = side * rng.randf_range(1.6, 3.3)
	var aim_z = rng.randf_range(0.3, 1.5)
	var conversion = 0.76 + float(taker.attr["sho"]) * 0.0018
	var scored: bool = rng.randf() <= conversion
	if not scored:
		aim_y = side * rng.randf_range(3.7, 4.6)
	shoot_ball(taker, aim_y, aim_z, 0.92, "penalty")
	# A scored penalty is a converted chance like any other: the line cannot get
	# a second dice at it. The stats record the probability it was taken with.
	ball.planned_goal = scored
	stats[team]["xg"] += conversion
	stats[team]["shots"] += 1
	stats[team]["on_target"] += 1
	ball.pos = restart["pos"]
	phase = "play"
	_emit("penalty_taken", CommentaryRestarts.penalty_taken(rng, taker.name), team, taker)

func _best_throw_target(team: int, taker):
	var best = null
	var bs = -1e9
	for p in players:
		if p.team != team or p.sent_off or p.id == taker.id:
			continue
		var d: float = taker.pos.distance_to(p.pos)
		if d > 26.0:
			continue
		var s = -absf(d - 10.0) * 0.3 + nearest_opponent_dist(p.pos, p.team) * 0.6 + attacking_x(team, p.pos) * 0.01
		if s > bs:
			bs = s
			best = p
	return best

func _best_short_outlet(team: int, taker):
	var best = null
	var bs = -1e9
	for p in players:
		if p.team != team or p.sent_off or p.id == taker.id or p.is_gk:
			continue
		var d: float = taker.pos.distance_to(p.pos)
		if d > 34.0:
			continue
		var openness: float = nearest_opponent_dist(p.pos, p.team)
		var prog: float = attacking_x(team, p.pos)
		var s: float = openness * 0.9 - d * 0.12 + prog * 0.02
		if s > bs:
			bs = s
			best = p
	return best

func _clear_long(taker, team: int) -> void:
	var aim = Vector2(L * 0.5 + teams[team]["dir"] * 12.0, W * 0.5 + rng.randf_range(-16.0, 16.0))
	clear_ball(taker, aim)

## Where the corner is aimed: the live set-piece routine decides near or far.
func _corner_aim(team: int) -> float:
	var routine := "far_post"
	if manager != null:
		routine = manager.tactics_for(team).corner_routine()
	match routine:
		"near_post":
			return W * 0.5 - 5.5
		"short":
			return W * 0.5
	return W * 0.5 + 5.5
