extends "res://scripts/sim/match_engine_clock.gd"


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
		"report_log": report_log.duplicate(true),
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
	appeared = players.duplicate()
	_touch_squad()
	stats = d["stats"].duplicate(true)
	events = d["events"].duplicate(true)
	ev_seq = d["ev_seq"]
	sim_tick = d["sim_tick"]
	goal_timer = d["goal_timer"]
	last_goal = d["last_goal"].duplicate(true)


	goal_sheet = d.get("goal_sheet", []).duplicate(true)


	var logged = d.get("report_log")
	if logged == null:
		logged = _log_from_events(d["events"])
	report_log = (logged as Array).duplicate(true)
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
