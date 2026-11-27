extends "res://scripts/sim/match_engine_bench.gd"


func _init(seed_in: int = 4242, home_id: String = "MUN", away_id: String = "MCI") -> void:
	seed_value = seed_in
	rng.seed = seed_in
	teams = [
		{
			"id": home_id, "data": TeamData.get_team(home_id), "dir": 1, "score": 0,
			"subs_left": SUB_LIMIT, "subs_made": 0, "windows_used": 0, "window_token": -1,
		},
		{
			"id": away_id, "data": TeamData.get_team(away_id), "dir": -1, "score": 0,
			"subs_left": SUB_LIMIT, "subs_made": 0, "windows_used": 0, "window_token": -1,
		},
	]
	Kits.assign(teams)
	stats = [_blank_stats(), _blank_stats()]
	home_team = 0
	_calibrate_finishing()
	_build_squads()
	manager = MatchManager.new(self)
	brain = MatchAI.new(self)
	setup_kickoff(0 if rng.randf() < 0.5 else 1, false)

func setup_kickoff(kicking_team: int, swap: bool) -> void:
	if swap:
		for t in range(2):
			teams[t]["dir"] *= -1
	kickoff_team = kicking_team
	possession_team = kicking_team
	possession_loose = false
	ball.pos = CENTER
	ball.vel = Vector2.ZERO
	ball.z = 0.0
	ball.vz = 0.0
	ball.spin = 0.0
	ball.owner_id = -1
	ball.last_touch_id = -1
	ball.last_touch_team = -1
	phase = "restart"
	restart = {"type": "kickoff", "team": kicking_team, "pos": CENTER, "timer": 1.6, "taker": -1}
	restart_timer = 1.6
	for p in players:
		p.pos = to_world(p.team, p.base)

		var own_half_x = L * 0.5
		if teams[p.team]["dir"] == 1:
			p.pos.x = minf(p.pos.x, own_half_x - 1.0)
		else:
			p.pos.x = maxf(p.pos.x, own_half_x + 1.0)
		p.vel = Vector2.ZERO
		p.target = p.pos
		p.facing = Vector2(teams[p.team]["dir"], 0)
		p.has_ball = false
		p.cooldown = 0.0
		p.state = "idle"
		p.offside_flag = false
		p.mark_id = -1

	for p in players:
		if p.team != kicking_team:
			var dc: float = p.pos.distance_to(CENTER)
			if dc < 9.15:
				var away: Vector2 = (p.pos - CENTER).normalized()
				if away.length() < 0.1:
					away = Vector2(-teams[p.team]["dir"], 0.0)
				p.pos = CENTER + away * 9.6

	var taker = _nearest_teammate_to(CENTER, kicking_team, true)
	if taker != null:
		taker.pos = CENTER + Vector2(-0.7 * teams[kicking_team]["dir"], 0.0)
		ball.owner_id = taker.id
		ball.last_touch_id = taker.id
		ball.last_touch_team = kicking_team
		taker.has_ball = true
	brain.on_kickoff()
	_emit("kickoff", CommentaryRestarts.kickoff(rng, teams[kicking_team]["data"]["name"]), kicking_team, taker)

func start() -> void:
	pass


func tick() -> void:
	if phase == "shootout":
		_tick_shootout(DT)
		return
	if phase == "full_time" or phase == "half_time" or phase == "et_break":
		return
	sim_tick += 1
	clock += DT
	flash = maxf(0.0, flash - DT * 2.0)
	_update_referee(DT)
	manager.tick(DT)

	if phase != "goal":
		_tick_clock_end()

		if (phase == "half_time" or phase == "full_time" or phase == "et_break"
				or phase == "shootout"):
			return

	if phase == "goal":
		goal_timer -= DT
		_ball_physics(DT, true)
		_move_players(DT)
		if goal_timer <= 0.0:
			setup_kickoff(last_goal.get("conceded_by", 0), false)
		return

	if phase == "restart":
		_update_restart(DT)
		_move_players(DT)
		_ball_physics(DT)
		_update_trails(DT)
		_tick_injuries(DT)
		return


	brain.update(DT)
	_move_players(DT)
	_ball_physics(DT)
	_ball_interactions(DT)
	_check_rules()
	_update_possession(DT)
	_update_trails(DT)
	_tick_substitutions()
	_tick_injuries(DT)

func _tick_clock_end() -> void:
	if half == 1:
		if added[0] <= 0.0 and clock >= 2700.0:
			added[0] = 20.0 + rng.randf_range(0.0, 50.0) + minf(100.0, stoppage_events * 4.0)
		if clock >= 2700.0 + added[0]:
			_end_first_half()
	elif half == 2:
		if clock >= 5400.0 + added[1]:
			_second_half_over()
	else:
		_tick_extra_time_period()

func _end_first_half() -> void:
	phase = "half_time"
	half_break_timer = 4.0
	_emit("half_time", CommentaryRestarts.half_time(rng, teams[0]["data"]["short"], score[0], teams[1]["data"]["short"], score[1]), -1, null)

	manager.on_half_time()
	blackout()

func blackout() -> void:
	pass

func begin_second_half() -> void:
	if phase != "half_time":
		return
	added[1] = 90.0 + rng.randf_range(0.0, 90.0) + minf(120.0, stoppage_events * 8.0)

	stoppage_events = 0
	injury_timer = 45.0
	for t in range(2):
		for p in players:
			if p.team == t:
				p.stamina = minf(1.0, p.stamina + 0.06)
	half = 2
	phase = "restart"
	setup_kickoff(1 - kickoff_team, true)
	manager.on_second_half()

func _end_match() -> void:
	phase = "full_time"
	finished = true
	if winner < 0 and int(score[0]) != int(score[1]):
		winner = 0 if int(score[0]) > int(score[1]) else 1


	for p in players:
		p.stats["rating"] = PLSimStats.rating(p.stats)
	var line: String = _full_time_text()
	_emit("full_time", line, -1, null)


func _full_time_text() -> String:
	return CommentaryRestarts.full_time(rng, teams[0]["data"]["short"], score[0],
		teams[1]["data"]["short"], score[1])


func _second_half_over() -> void:
	_end_match()

func _tick_extra_time_period() -> void:
	pass

func _tick_shootout(_dt: float) -> void:
	pass


func resume_after_break() -> void:
	pass


func run_to_full_time(budget_usec: int = -1) -> bool:
	var started := Time.get_ticks_usec()
	var guard := 0
	while phase != "full_time" and guard < FAST_FORWARD_TICKS:
		if phase == "half_time":
			begin_second_half()
		elif phase == "et_break":
			resume_after_break()
		tick()
		guard += 1
		if budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec:
			break
	return phase == "full_time"

func to_dict() -> Dictionary:
	var ps = []
	for p in players:
		ps.append({
			"id": p.id, "key": p.key, "team": p.team, "name": p.name, "number": p.number, "role": p.role,
			"pos_label": p.pos_label, "attr": p.attr, "gk": p.gk, "base": p.base,
			"pos": p.pos, "vel": p.vel, "facing": p.facing, "target": p.target,
			"stamina": p.stamina, "state": p.state, "has_ball": p.has_ball,
			"yellow": p.yellow, "red": p.red, "sent_off": p.sent_off, "is_gk": p.is_gk,
			"injured": p.injured,
			"stats": p.stats.duplicate(true), "offside_flag": p.offside_flag,
			"mark_id": p.mark_id, "cooldown": p.cooldown, "speed_scale": p.speed_scale,
			"celebrate": p.celebrate,
			"involvements": p.involvements.duplicate(true),
		})
	return {
		"clock": clock, "half": half, "phase": phase, "restart": restart.duplicate(true),
		"restart_timer": restart_timer, "added": added.duplicate(), "score": score.duplicate(),
		"possession_team": possession_team, "possession_loose": possession_loose,
		"ball": {"pos": ball.pos, "vel": ball.vel, "z": ball.z, "vz": ball.vz, "spin": ball.spin,
			"owner_id": ball.owner_id, "last_touch_id": ball.last_touch_id,
			"last_touch_team": ball.last_touch_team, "last_kick_id": ball.last_kick_id,
			"assist_id": ball.assist_id, "assist_time": ball.assist_time,
			"shot_team": ball.shot_team, "shot_time": ball.shot_time, "shot_saved": ball.shot_saved,
			"planned_goal": ball.planned_goal, "loose_t": ball.loose_t,
			"shot_xg": ball.shot_xg},
		"players": ps, "stats": stats.duplicate(true), "events": events.duplicate(true),
		"referee": {"pos": referee.pos, "vel": referee.vel, "whistle": referee.whistle,
			"focus": referee.focus, "focus_t": referee.focus_t},
		"ev_seq": ev_seq, "sim_tick": sim_tick, "goal_timer": goal_timer,
		"last_goal": last_goal.duplicate(true), "goal_sheet": goal_sheet.duplicate(true),
		"rng": rng.state, "dirs": [teams[0]["dir"], teams[1]["dir"]],
		"subs": [teams[0]["subs_made"], teams[1]["subs_made"]],
		"subs_left": [teams[0]["subs_left"], teams[1]["subs_left"]], "finished": finished,
		"stoppage_events": stoppage_events, "kickoff_team": kickoff_team,
		"injury_timer": injury_timer,
		"windows": [teams[0]["windows_used"], teams[1]["windows_used"]],
		"window_token": [teams[0]["window_token"], teams[1]["window_token"]],
		"stoppage_seq": stoppage_seq, "manager": manager.to_dict(),
	}

func from_dict(d: Dictionary) -> void:
	clock = d["clock"]
	half = d["half"]
	phase = d["phase"]
	restart = d["restart"].duplicate(true)
	restart_timer = d["restart_timer"]
	added = d["added"].duplicate()

	while added.size() < 4:
		added.append(0.0)
	score = d["score"].duplicate()
	teams[0]["score"] = score[0]
	teams[1]["score"] = score[1]
	possession_team = d["possession_team"]
	possession_loose = d["possession_loose"]
	var b: Dictionary = d["ball"]
	ball.pos = b["pos"]
	ball.vel = b["vel"]
	ball.z = b["z"]
	ball.vz = b["vz"]
	ball.spin = b["spin"]
	ball.owner_id = b["owner_id"]
	ball.last_touch_id = b["last_touch_id"]
	ball.last_touch_team = b["last_touch_team"]
	ball.last_kick_id = b["last_kick_id"]
	ball.assist_id = b.get("assist_id", -1)
	ball.assist_time = b.get("assist_time", -10.0)
	ball.shot_team = b.get("shot_team", -1)
	ball.shot_time = b.get("shot_time", -10.0)
	ball.shot_saved = b.get("shot_saved", false)
	ball.planned_goal = bool(b.get("planned_goal", false))
	ball.shot_xg = b.get("shot_xg", 0.0)
	ball.loose_t = b.get("loose_t", 0.0)
	var r: Dictionary = d.get("referee", {})
	if not r.is_empty():
		referee.pos = r["pos"]
		referee.vel = r["vel"]
		referee.whistle = r["whistle"]
		referee.focus = r["focus"]
		referee.focus_t = r["focus_t"]
	var old_trails := {}
	for q in players:
		old_trails[q.id] = q.trail
	players.clear()
	by_id.clear()
	for pd in d["players"]:
		var p = Player.new()
		p.id = pd["id"]
		p.key = str(pd.get("key", ""))
		p.team = pd["team"]
		p.name = pd["name"]
		p.number = pd["number"]
		p.role = pd["role"]
		p.pos_label = pd["pos_label"]
		p.attr = pd["attr"].duplicate(true)
		p.gk = pd["gk"].duplicate(true)
		p.base = pd["base"]
		p.pos = pd["pos"]
		p.vel = pd["vel"]
		p.facing = pd["facing"]
		p.target = pd["target"]
		p.stamina = pd["stamina"]
		p.state = pd["state"]
		p.has_ball = pd["has_ball"]
		p.yellow = pd["yellow"]
		p.red = pd["red"]
		p.sent_off = pd["sent_off"]
		p.is_gk = pd["is_gk"]
		p.injured = bool(pd.get("injured", false))
		p.stats = pd["stats"].duplicate(true)
		p.offside_flag = pd["offside_flag"]
		p.mark_id = pd["mark_id"]
		p.cooldown = pd["cooldown"]
		p.speed_scale = pd["speed_scale"]
		p.celebrate = pd["celebrate"]
		if old_trails.has(p.id) and old_trails[p.id] is Array:
			var tr: Array = old_trails[p.id]
			if tr.size() > 9:
				tr = tr.slice(0, tr.size() - 9)
			p.trail = tr
		p.involvements = pd["involvements"].duplicate(true)
		_fill_attr_cache(p)
		players.append(p)
		by_id[p.id] = p
	_touch_squad()
	stats = d["stats"].duplicate(true)
	events = d["events"].duplicate(true)
	ev_seq = d["ev_seq"]
	sim_tick = d["sim_tick"]
	goal_timer = d["goal_timer"]
	last_goal = d["last_goal"].duplicate(true)


	goal_sheet = d.get("goal_sheet", []).duplicate(true)
	rng.state = d["rng"]
	teams[0]["dir"] = d["dirs"][0]
	teams[1]["dir"] = d["dirs"][1]
	teams[0]["subs_made"] = d["subs"][0]
	teams[1]["subs_made"] = d["subs"][1]
	var sl: Array = d.get("subs_left", [5, 5])
	teams[0]["subs_left"] = sl[0]
	teams[1]["subs_left"] = sl[1]
	finished = d["finished"]
	stoppage_events = d["stoppage_events"]
	injury_timer = float(d.get("injury_timer", 45.0))
	kickoff_team = d["kickoff_team"]
	var win: Array = d.get("windows", [0, 0])
	var tok: Array = d.get("window_token", [-1, -1])
	for t in range(2):
		teams[t]["windows_used"] = int(win[t])
		teams[t]["window_token"] = int(tok[t])
	stoppage_seq = int(d.get("stoppage_seq", 0))
	var md: Dictionary = d.get("manager", {})
	if manager != null and not md.is_empty():
		manager.from_dict(md)
	if brain != null:
		brain.on_restore()


