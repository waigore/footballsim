extends "res://scripts/sim/match_engine_play.gd"

## Laws of the game: goals, offside, out of play, substitutions.

## Every goal this match has scored, in order: `team` (the side credited),
## `minute`, `scorer` and `own_goal`. The goal path writes it, so the whistle
## card can list the goals without re-reading `events`, which drops its oldest
## entries once a match gets busy (DR-20261125-04).
var goal_sheet: Array = []

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
				if carrier != null and carrier.team != goal_team:
					# Walk-in: a clear chance worth 0.85 xG, so expected goals
					# account for every goal the engine can score.
					stats[carrier.team]["xg"] += 0.85
					stats[carrier.team]["shots"] += 1
					stats[carrier.team]["on_target"] += 1
				_score_goal(goal_team)
				return
			var was_shot: bool = ball.shot_team >= 0 and not ball.shot_saved
			var gk = _gk_of(goal_team)
			if gk != null:
				var gpos: Vector2 = Vector2(own_goal_pos(goal_team).x, ball.pos.y)
				var gd: float = gk.pos.distance_to(gpos)
				var reach: float = Attrs.gk_dive_reach(gk) + 1.05
				gk_debug.append("GOALCHECK gkdist=%.1f reach=%.1f z=%.1f speed=%.1f" % [gd, reach, ball.z, ball.vel.length()])
				var save_p: float = 0.91 + (reach - gd) * 0.06 + (Attrs.gk_handling(gk) - 0.8) * 0.25 - ball.vel.length() * 0.003
				save_p = clampf(save_p, 0.18, 0.985)
				# A chance the finishing roll priced out is kept out here, so a
				# match's goals stay equal to its expected goals; a converted
				# chance still cannot be vetoed at the line.
				var kept_out: bool = ball.planned_save
				if not kept_out and gd < reach + 3.2:
					kept_out = rng.randf() < save_p
				if kept_out and not ball.planned_goal:
					# A goal-line save.
					var push: Vector2 = Vector2(teams[goal_team]["dir"], rng.randf_range(-1.0, 1.0)).normalized()
					ball.pos = Vector2(0.7 if own_goal_pos(goal_team).x < 1.0 else L - 0.7, clampf(ball.pos.y, 1.0, W - 1.0))
					ball.vel = push * rng.randf_range(7.0, 13.0)
					ball.z = 0.3
					ball.vz = 1.8
					ball.shot_team = -1
					ball.shot_saved = true
					ball.planned_save = false
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
		# The frame: a ball that beats the keeper but strikes a post or the bar
		# comes back into play. A chance the finishing roll priced as a goal is
		# never denied here — the frame is a read of where the shot went, not a
		# second dice on whether it goes in.
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
	goal_sheet.append({
		"team": scoring_team, "minute": minute_of(clock),
		"scorer": scorer.name if scorer != null else "Unknown",
		"own_goal": own_goal,
	})
	phase = "goal"
	goal_timer = 3.4
	ball.planned_goal = false
	ball.planned_save = false
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
	# Both benches react: the side that conceded is the one under pressure.
	manager.on_event("goal", {"team": scoring_team})
	if scorer != null:
		_add_involvement(scorer, "goal", "Goal", scorer.pos)
	ball.assist_id = -1

## A ball off the frame: the shooting side is credited with the woodwork, the
## ball rebounds into play and the match carries on. Not a goal, not a save, and
## no restart — a post is the one miss that stays live.
func _woodwork(goal_team: int, frame: String) -> bool:
	var shooting: int = 1 - goal_team
	var shooter = by_id.get(ball.last_touch_id, null)
	if ball.last_touch_team != shooting:
		return false
	stats[shooting]["woodwork"] += 1
	var at_left: bool = ball.pos.x <= 0.0
	# Put the ball back in play on the field side of the line, then send it away
	# from the goal: into the field and, for a post, across the face of goal.
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
	ball.planned_save = false
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
	# Momentum fades as play goes on: what a side did five minutes ago matters
	# less than what it is doing now (DR-20261125-01).
	var fade: float = MatchStats.decay(dt)
	momentum[0] = float(momentum[0]) * fade
	momentum[1] = float(momentum[1]) * fade

func _update_trails(dt: float) -> void:
	for p in players:
		p.trail_t += dt
		if p.trail_t >= 1.0:
			p.trail_t = 0.0
			p.trail.append(p.pos)
			if p.trail.size() > 6200:
				p.trail.pop_front()

func _tick_substitutions() -> void:
	# Managers choose changes at stoppages and half-time (MatchManager). The
	# only automatic change left is the emergency goalkeeper: a side must
	# always have a keeper.
	for t in range(2):
		if int(teams[t]["subs_left"]) <= 0:
			continue
		if _gk_of(t) == null and not _bench_keeper(t).is_empty():
			_make_substitution(t, true)

## Is a change legal right now? Five changes in three windows; half-time is a
## free window, and a second change in the same stoppage shares its window.
func sub_window_available(t: int, at_half_time: bool = false) -> bool:
	if int(teams[t]["subs_left"]) <= 0:
		return false
	if at_half_time or phase == "half_time":
		return true
	return int(teams[t]["windows_used"]) < SUB_WINDOWS

func _use_sub_window(t: int, at_half_time: bool) -> bool:
	if at_half_time or phase == "half_time":
		return true
	if not sub_window_available(t, false):
		return false
	if int(teams[t]["window_token"]) != stoppage_seq:
		teams[t]["windows_used"] = int(teams[t]["windows_used"]) + 1
		teams[t]["window_token"] = stoppage_seq
	return true

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
	if role == "RCB" or role == "LCB":
		return "CB"
	if role == "RDM" or role == "LDM":
		return "CDM"
	if role == "RWB" or role == "LWB":
		return "RB"
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
	if worst == null:
		return false
	return _bring_on(t, worst, true, false, {"reason": "emergency_keeper"})

## Replace one player with the best available bench body. Charges one of the
## five changes and, outside half-time, one of the three windows. The
## emergency-keeper change is exempt from the window count so a side is never
## left without a keeper.
func _bring_on(t: int, off, for_gk: bool = false, at_half_time: bool = false, meta: Dictionary = {}) -> bool:
	if off == null or int(teams[t]["subs_left"]) <= 0:
		return false
	if not for_gk and not _use_sub_window(t, at_half_time):
		return false
	var candidate: Dictionary = _pick_bench(t, off.role, for_gk or off.is_gk)
	if candidate.is_empty():
		return false
	var np = _make_player(candidate, t, 200 + t * 40 + int(teams[t]["subs_made"]))
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
	_touch_squad()
	if ball.owner_id == off.id:
		ball.owner_id = np.id
		ball.last_touch_id = np.id
	teams[t]["subs_made"] = int(teams[t]["subs_made"]) + 1
	teams[t]["subs_left"] = int(teams[t]["subs_left"]) - 1
	var info := {"window": int(teams[t]["windows_used"]), "at_half_time": at_half_time}
	for k in meta.keys():
		info[k] = meta[k]
	_emit("substitution", Commentary.substitution(rng, teams[t]["data"]["short"], np.name, off.name,
		str(meta.get("manager", ""))), t, np, info)
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
	# The manager picks the replacement; without a legal change the side plays
	# on a man short.
	if manager != null and manager.replace_injured(p):
		return
	_emit("injury", Commentary.injury(rng, p.name, false), t, p)
	_send_off_injured(p)

func _send_off_injured(p) -> void:
	p.sent_off = true
	_touch_squad()
	p.vel = Vector2.ZERO
	p.has_ball = false
	if ball.owner_id == p.id:
		ball.owner_id = -1
	p.mark_id = -1
	_add_involvement(p, "injury", "Injured — off", p.pos)

