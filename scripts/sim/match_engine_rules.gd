extends "res://scripts/sim/match_engine_play.gd"

## Laws of the game: goals, offside, out of play, substitutions.

func _check_rules() -> void:
	# Goal?
	if ball.pos.x <= 0.0 or ball.pos.x >= L:
		var at_left: bool = ball.pos.x <= 0.0
		var goal_team := -1
		for tt in range(2):
			if (teams[tt]["dir"] == 1) == at_left:
				goal_team = tt
		if goal_team < 0:
			return
		if absf(ball.pos.y - W * 0.5) <= GOAL_W * 0.5 and ball.z <= GOAL_H:
			# A carried ball on the line is not a shot: a keeper holding it stays in
			# play, anyone else carrying it in scores (own goal when defending).
			if ball.owner_id >= 0:
				var carrier = by_id.get(ball.owner_id, null)
				if carrier != null and carrier.is_gk and carrier.team == goal_team:
					ball.pos.x = 0.45 if at_left else L - 0.45
					return
				_score_goal(goal_team)
				return
			var was_shot: bool = ball.shot_team >= 0 and not ball.shot_saved
			var gk = _gk_of(goal_team)
			if gk != null:
				var gpos: Vector2 = Vector2(own_goal_pos(goal_team).x, ball.pos.y)
				var gd: float = gk.pos.distance_to(gpos)
				var reach: float = Attrs.gk_dive_reach(gk) + 1.05
				gk_debug.append("GOALCHECK gkdist=%.1f reach=%.1f z=%.1f speed=%.1f" % [gd, reach, ball.z, ball.vel.length()])
				if gd < reach + 3.2:
					var save_p: float = 0.91 + (reach - gd) * 0.06 + (Attrs.gk_handling(gk) - 0.8) * 0.25 - ball.vel.length() * 0.003
					save_p = clampf(save_p, 0.18, 0.985)
					if rng.randf() < save_p:
						# A goal-line save.
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
				# A keeper touching it over his own line is a save that stayed out of reach: corner.
				_start_restart("corner", 1 - goal_team, Vector2(own_goal_pos(goal_team).x, 0.0 if ball.pos.y < W * 0.5 else W))
				return
			_score_goal(goal_team)
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
		var assister = by_id.get(ball.assist_id, null)
		if assister != null and assister.team == scoring_team and assister.id != scorer.id and clock - ball.assist_time < 16.0:
			assister.stats["assists"] += 1
			_add_involvement(assister, "assist", "Assist for %s" % scorer_name, assister.pos)
	last_goal = {
		"team": scoring_team, "conceded_by": conceding_team,
		"scorer": scorer_name, "minute": minute_of(clock), "own_goal": own_goal,
		"assist": by_id.get(ball.assist_id, null).name if by_id.get(ball.assist_id, null) != null and not own_goal else "",
	}
	phase = "goal"
	goal_timer = 3.4
	ball.owner_id = -1
	ball.vel *= 0.2
	ball.vz = 0.0
	ball.z = 0.0
	ball.shot_team = -1
	stoppage_events += 1
	_emit("goal", Commentary.goal(rng, scorer.name if scorer != null else "Unknown",
		str(last_goal.get("assist", "")), own_goal,
		teams[scoring_team]["data"]["short"], teams[conceding_team]["data"]["short"],
		score[scoring_team] - 1, score[conceding_team], minute_of(clock)), scoring_team, scorer, {"xg": 0.0})
	flash = 1.0
	for p in players:
		if p.team == scoring_team:
			p.celebrate = 2.6
	_flash(1.0)
	if scorer != null:
		_add_involvement(scorer, "goal", "Goal", scorer.pos)
	ball.assist_id = -1

func _goal_line_out(defending_team: int) -> void:
	var last_team = ball.last_touch_team
	var y = clampf(ball.pos.y, 0.5, W - 0.5)
	var goal_x = 0.0 if defending_team == 0 else L
	if last_team == defending_team:
		# corner to the attacking team
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

func _update_trails(dt: float) -> void:
	for p in players:
		p.trail_t += dt
		if p.trail_t >= 1.0:
			p.trail_t = 0.0
			p.trail.append(p.pos)
			if p.trail.size() > 6200:
				p.trail.pop_front()

func _tick_substitutions() -> void:
	if half < 2:
		return
	for t in range(2):
		if teams[t]["subs_left"] <= 0:
			continue
		# A team must always have a keeper: replace a sent-off one first.
		if _gk_of(t) == null and not _bench_keeper(t).is_empty():
			_make_substitution(t, true)
			continue
		var mins: Array = teams[t]["sub_minutes"]
		var made: int = teams[t]["subs_made"]
		if made < mins.size() and clock / 60.0 >= float(mins[made]):
			_make_substitution(t, false)

func _bench_keeper(t: int) -> Dictionary:
	var on_field := {}
	for p in players:
		if p.team == t:
			on_field[p.name] = true
	for b in teams[t]["data"]["bench"]:
		if b["role"] == "GK" and not on_field.has(b["name"]):
			return b
	return {}

func _most_tired_outfield(t: int):
	var worst = null
	var worst_score = 1e9
	for p in players:
		if p.team != t or p.is_gk or p.sent_off or p.celebrate > 0.0:
			continue
		var sc: float = p.stamina * 100.0 - (p.pos.distance_to(to_world(t, p.base)) * 0.05)
		if sc < worst_score:
			worst_score = sc
			worst = p
	return worst

func _role_family(role: String) -> String:
	# Formation slots use sided labels; bench entries use the generic position.
	match role:
		"RCB", "LCB": return "CB"
		"RDM", "LDM": return "CDM"
		"RWB", "LWB": return "RB"
	return role

func _pick_bench(t: int, want_role: String, for_gk: bool) -> Dictionary:
	var on_field := {}
	for p in players:
		if p.team == t:
			on_field[p.name] = true
	var fallback := {}
	var want: String = _role_family(want_role)
	for b in teams[t]["data"]["bench"]:
		if on_field.has(b["name"]):
			continue
		# Keepers only come on for a keeper; outfield subs never take the gloves.
		if (b["role"] == "GK") != for_gk:
			continue
		if _role_family(b["role"]) == want:
			return b
		if fallback.is_empty():
			fallback = b
	return fallback

func _make_substitution(t: int, for_gk: bool = false) -> bool:
	var worst = null
	if for_gk:
		for p in players:
			if p.team == t and p.is_gk and p.sent_off:
				worst = p
				break
	else:
		worst = _most_tired_outfield(t)
	if worst == null:
		# No eligible body: bank the scheduled sub so we don't retry every tick.
		if not for_gk:
			teams[t]["subs_made"] += 1
		return false
	return _bring_on(t, worst, for_gk)

## Replace one player with the best available bench body. Used by the scheduled
## changes and by injuries, which cannot wait for the substitution window.
func _bring_on(t: int, off, for_gk: bool = false) -> bool:
	var candidate: Dictionary = _pick_bench(t, off.role, for_gk or off.is_gk)
	if candidate.is_empty() or teams[t]["subs_left"] <= 0:
		if not for_gk:
			teams[t]["subs_made"] += 1
		return false
	var np = _make_player(candidate, t, 200 + t * 40 + teams[t]["subs_made"])
	# The substitute fills the slot of the player he replaces, not his own.
	np.role = off.role
	np.is_gk = off.is_gk
	np.base = off.base
	np.pos = off.pos
	np.target = off.target
	np.stamina = 1.0
	var idx = players.find(off)
	players[idx] = np
	by_id.erase(off.id)
	by_id[np.id] = np
	if ball.owner_id == off.id:
		ball.owner_id = np.id
		ball.last_touch_id = np.id
	teams[t]["subs_made"] += 1
	teams[t]["subs_left"] -= 1
	_emit("substitution", Commentary.substitution(rng, teams[t]["data"]["short"], np.name, off.name), t, np)
	_add_involvement(np, "sub", "On for %s" % off.name, np.pos)
	return true

# --------------------------------------------------------------- injuries ---

## Tired bodies break down: one roll every 45s of play picks a side, and that
## side's most fatigued outfield player may pull up. A knock costs a change; a
## side with no changes left plays on a man short.
func _tick_injuries(dt: float) -> void:
	injury_timer -= dt
	if injury_timer > 0.0:
		return
	injury_timer = 45.0
	for t in range(2):
		if rng.randf() >= 0.006:
			continue
		var cand = _most_tired_outfield(t)
		if cand == null:
			continue
		# Cramp or a knock: the same tired legs make the serious ones likelier.
		if rng.randf() < 0.25 + (1.0 - cand.stamina) * 0.55:
			_injure(cand)

func _injure(p) -> void:
	if p == null or p.sent_off or p.injured:
		return
	p.injured = true
	var t: int = p.team
	stats[t]["injuries"] += 1
	p.stats["injuries"] = int(p.stats.get("injuries", 0)) + 1
	_flash(0.5)
	if teams[t]["subs_left"] > 0 and not _pick_bench(t, p.role, p.is_gk).is_empty():
		_emit("injury", Commentary.injury(rng, p.name, true), t, p)
		_bring_on(t, p)
		return
	_emit("injury", Commentary.injury(rng, p.name, false), t, p)
	_send_off_injured(p)

func _send_off_injured(p) -> void:
	p.sent_off = true
	p.vel = Vector2.ZERO
	p.has_ball = false
	if ball.owner_id == p.id:
		ball.owner_id = -1
	p.mark_id = -1
	_add_involvement(p, "injury", "Injured — off", p.pos)

# --------------------------------------------------------------- snapshots --
