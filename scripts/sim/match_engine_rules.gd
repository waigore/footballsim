extends "res://scripts/sim/match_engine_play.gd"


const ASSIST_WINDOW := 16.0


func _check_rules() -> void:

	if ball.pos.x <= 0.0 or ball.pos.x >= L:
		var at_left: bool = ball.pos.x <= 0.0
		var goal_team := -1
		for tt in range(2):
			if (teams[tt]["dir"] == 1) == at_left:
				goal_team = tt
		if goal_team < 0:
			return
		if absf(ball.pos.y - W * 0.5) <= GOAL_W * 0.5 and ball.z <= GOAL_H:


			if ball.owner_id >= 0:
				var carrier = by_id.get(ball.owner_id, null)
				if carrier != null and carrier.is_gk and carrier.team == goal_team:
					ball.pos.x = 0.45 if at_left else L - 0.45
					return
				if carrier != null and carrier.team != goal_team:


					stats[carrier.team]["xg"] += 0.85
					stats[carrier.team]["shots"] += 1
					stats[carrier.team]["on_target"] += 1
				_score_goal(goal_team)
				return
			var was_shot: bool = ball.shot_team >= 0 and not ball.shot_saved
			var gk = _gk_of(goal_team)
			if gk != null:
				var cross_y: float = MatchStats.goal_plane_point(
					ball.pos, ball.vel, ball.z, ball.vz, 0.0 if at_left else L).x
				var save_p: float = line_save_chance(gk, goal_team, cross_y, ball.vel.length())
				gk_debug.append("GOALCHECK reach_p=%.2f z=%.1f speed=%.1f" % [save_p, ball.z, ball.vel.length()])
				var kept_out: bool = save_p > 0.0 and rng.randf() < save_p
				if kept_out and not ball.planned_goal:

					var push: Vector2 = Vector2(teams[goal_team]["dir"], rng.randf_range(-1.0, 1.0)).normalized()
					ball.pos = Vector2(0.7 if own_goal_pos(goal_team).x < 1.0 else L - 0.7, clampf(ball.pos.y, 1.0, W - 1.0))
					ball.vel = push * rng.randf_range(7.0, 13.0)
					ball.z = 0.3
					ball.vz = 1.8
					ball.shot_team = -1
					ball.shot_saved = true
					gk.cooldown = 0.5
					if was_shot:
						gk.stats["saves"] += 1
						stats[goal_team]["saves"] += 1
						_emit("save", Commentary.save(rng, gk.name, _shot_credit(gk), "goal_line", ball.shot_xg), goal_team, gk)
						_flash(1.0)
					return
			var lt = by_id.get(ball.last_touch_id, null)
			if lt != null and lt.team == goal_team and lt.is_gk:

				_start_restart("corner", 1 - goal_team, Vector2(own_goal_pos(goal_team).x, 0.0 if ball.pos.y < W * 0.5 else W))
				return
			_score_goal(goal_team)
			return


		if not ball.planned_goal:
			var cross: Vector2 = MatchStats.goal_plane_point(
				ball.pos, ball.vel, ball.z, ball.vz, 0.0 if at_left else L)
			var frame: String = MatchStats.frame_hit(W * 0.5, GOAL_W, GOAL_H, cross.x, cross.y)
			if frame != "" and _woodwork(goal_team, frame):
				return
		_goal_line_out(goal_team)
		return
	if ball.pos.y <= 0.0 or ball.pos.y >= W:
		var to_team = 1 - ball.last_touch_team if ball.last_touch_team >= 0 else 0
		_start_restart("throw_in", to_team, Vector2(clampf(ball.pos.x, 0.5, L - 0.5), 0.0 if ball.pos.y < 0.0 else W))
		return

func _score_goal(conceding_team: int) -> void:
	var scoring_team = 1 - conceding_team
	var scorer = by_id.get(ball.last_touch_id, null)
	var own_goal: bool = scorer != null and scorer.team == conceding_team
	score[scoring_team] += 1
	teams[scoring_team]["score"] = score[scoring_team]
	stats[scoring_team]["goals"] += 1
	var scorer_name = "Unknown"
	var assister = null
	if own_goal:
		scorer_name = "Own goal — " + scorer.name
		var recent := []
		for i in range(maxi(0, events.size() - 4), events.size()):
			recent.append(events[i]["type"])
		if verbose:
			_vlog("OWNGOAL %s gk=%s team=%d conceding=%d pos=(%.1f,%.1f) vel=(%.1f,%.1f) z=%.2f lasttouch=%.1fs shot_team=%d dirs=%d/%d recent=%s" % [scorer.name, str(scorer.is_gk), scorer.team, conceding_team, ball.pos.x, ball.pos.y, ball.vel.x, ball.vel.y, ball.z, clock - ball.last_touch_time, ball.shot_team, teams[0]["dir"], teams[1]["dir"], str(recent)])
		scorer.stats["own_goals"] = scorer.stats.get("own_goals", 0) + 1
	elif scorer != null:
		scorer_name = scorer.name
		scorer.stats["goals"] += 1
		scorer.celebrate = 3.0
		assister = _assister_for(scorer, scoring_team)
		if assister != null:
			assister.stats["assists"] += 1
			_add_involvement(assister, "assist", "Assist for %s" % scorer_name, assister.pos)
	last_goal = {
		"team": scoring_team, "conceded_by": conceding_team,
		"scorer": scorer_name, "minute": minute_of(clock), "own_goal": own_goal,
		"assist": assister.name if assister != null else "",
		"assist_key": str(assister.key) if assister != null else "",
	}
	phase = "goal"
	goal_timer = 3.4
	ball.planned_goal = false
	ball.owner_id = -1
	ball.vel *= 0.2
	ball.vz = 0.0
	ball.z = 0.0
	ball.shot_team = -1
	stoppage_events += 1
	var goal_extra := {"xg": 0.0, "own_goal": own_goal}
	if assister != null:
		goal_extra["assist_key"] = str(assister.key)
		goal_extra["assist_name"] = str(assister.name)
	_emit("goal", Commentary.goal(rng, scorer.name if scorer != null else "Unknown",
		str(last_goal.get("assist", "")), own_goal,
		teams[scoring_team]["data"]["short"], teams[conceding_team]["data"]["short"],
		score[scoring_team] - 1, score[conceding_team], minute_of(clock)), scoring_team, scorer,
		goal_extra)
	flash = 1.0
	for p in players:
		if p.team == scoring_team:
			p.celebrate = 2.6
	_flash(1.0)

	manager.on_event("goal", {"team": scoring_team})
	if scorer != null:
		_add_involvement(scorer, "goal", "Goal", scorer.pos)
	ball.assist_id = -1


func _assister_for(scorer: Variant, scoring_team: int) -> Variant:
	var helper = by_id.get(ball.assist_id, null)
	if helper == null or scorer == null:
		return null
	if helper.team != scoring_team or helper.id == scorer.id:
		return null
	if clock - ball.assist_time >= ASSIST_WINDOW:
		return null
	return helper


func _woodwork(goal_team: int, frame: String) -> bool:
	var shooting: int = 1 - goal_team
	var shooter = by_id.get(ball.last_touch_id, null)
	if ball.last_touch_team != shooting:
		return false
	stats[shooting]["woodwork"] += 1
	var at_left: bool = ball.pos.x <= 0.0


	ball.pos = Vector2((0.55 if at_left else L - 0.55), clampf(ball.pos.y, 1.0, W - 1.0))
	var into_play: float = 1.0 if at_left else -1.0
	if frame == "bar":
		ball.z = maxf(ball.z, GOAL_H * 0.5)
		ball.vz = -absf(ball.vz) * 0.45 - 1.2
		ball.vel = Vector2(-ball.vel.x * 0.45, ball.vel.y * 0.45)
	else:
		ball.z = minf(ball.z, 1.2)
		ball.vz = 0.5
		var across: float = 1.0 if ball.pos.y >= W * 0.5 else -1.0
		ball.vel = Vector2(into_play * absf(ball.vel.x) * 0.55, across * rng.randf_range(1.5, 4.0))
	ball.shot_team = -1
	ball.shot_saved = false
	ball.planned_goal = false
	ball.loose_t = 0.0
	if shooter != null:
		_add_involvement(shooter, "woodwork", "Off the %s" % frame, shooter.pos)
	_emit("woodwork", Commentary.woodwork(rng, shooter.name if shooter != null else "The shot", frame),
		shooting, shooter)
	_flash(0.6)
	return true

func _goal_line_out(defending_team: int) -> void:
	var last_team = ball.last_touch_team
	var y = clampf(ball.pos.y, 0.5, W - 0.5)
	var goal_x = 0.0 if defending_team == 0 else L
	if last_team == defending_team:

		var corner_y = 0.0 if y < W * 0.5 else W
		_start_restart("corner", 1 - defending_team, Vector2(goal_x, corner_y))
	else:
		_start_restart("goal_kick", defending_team, Vector2(goal_x, W * 0.5))

func _offside(p) -> void:
	if not p.offside_flag:
		return
	stats[p.team]["offsides"] += 1
	_emit("offside", Commentary.offside(rng, p.name), p.team, p)
	_add_involvement(p, "offside", "Caught offside", p.pos)
	for q in players:
		q.offside_flag = false
	var spot: Vector2 = p.pos
	_start_restart("free_kick", 1 - p.team, spot, 1.0)

func _update_possession(dt: float) -> void:
	if ball.owner_id >= 0:
		var p = by_id.get(ball.owner_id, null)
		if p != null:
			possession_team = p.team
			possession_loose = false
	elif ball.last_touch_team >= 0 and ball.vel.length() < 6.0:
		possession_team = ball.last_touch_team
		possession_loose = true
	stats[0]["possession"] += dt if possession_team == 0 else 0.0
	stats[1]["possession"] += dt if possession_team == 1 else 0.0


	var fade: float = MatchStats.decay(dt)
	momentum[0] = float(momentum[0]) * fade
	momentum[1] = float(momentum[1]) * fade

func _update_trails(dt: float) -> void:
	if not record_trails:
		return
	for p in players:
		p.trail_t += dt
		if p.trail_t >= 1.0:
			p.trail_t = 0.0
			p.trail.append(p.pos)
			if p.trail.size() > 6200:
				p.trail.pop_front()
