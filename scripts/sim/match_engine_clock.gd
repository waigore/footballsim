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
	var keep_trails := record_trails
	record_trails = false
	while phase != "full_time" and guard < FAST_FORWARD_TICKS:
		if phase == "half_time":
			begin_second_half()
		elif phase == "et_break":
			resume_after_break()
		tick()
		guard += 1
		if budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec:
			break
	record_trails = keep_trails
	return phase == "full_time"

