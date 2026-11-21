class_name MatchEngine
extends RefCounted

## A deterministic, full-Laws football match engine.
## State is fully snapshot-able so the presentation layer can rewind and replay.

signal event_fired(e: Dictionary)
signal ball_kicked(strength: float)

const L := 105.0
const W := 68.0
const GOAL_W := 7.32
const GOAL_H := 2.44
const BOX_D := 16.5
const BOX_W := 40.32
const SIX_D := 5.5
const SIX_W := 18.32
const PEN_D := 11.0
const CENTER := Vector2(52.5, 34.0)
const DT := 1.0 / 60.0

class Player:
	var id = 0
	var team = 0
	var name = ""
	var number = 0
	var role = ""
	var pos_label = ""
	var attr = {}
	var gk = {}
	var base = Vector2.ZERO            # normalized formation slot in attacking frame
	var pos = Vector2.ZERO
	var vel = Vector2.ZERO
	var facing = Vector2.RIGHT
	var target = Vector2.ZERO
	var speed_scale = 1.0
	var stamina = 1.0
	var z = 0.0
	var state = "idle"
	var action_t = 0.0
	var cooldown = 0.0
	var has_ball = false
	var yellow = 0
	var red = false
	var sent_off = false
	var is_gk = false
	var dive = Vector2.ZERO
	var dive_t = 0.0
	var jump_t = 0.0
	var celebrate = 0.0
	var offside_flag = false
	var mark_id = -1
	var run_until = 0.0
	var run_to = Vector2.ZERO
	var stats = {
		"passes": 0, "passes_ok": 0, "shots": 0, "on_target": 0, "goals": 0,
		"assists": 0, "tackles": 0, "interceptions": 0, "fouls": 0, "saves": 0,
		"touches": 0, "distance": 0.0, "rating": 6.0,
	}
	var involvements = []
	var trail = []
	var trail_t = 0.0
	var last_action = ""
	var active = true

class Ball:
	var pos = Vector2(52.5, 34.0)
	var vel = Vector2.ZERO
	var z = 0.0
	var vz = 0.0
	var spin = 0.0
	var owner_id = -1
	var last_touch_id = -1
	var last_touch_team = -1
	var last_kick_id = -1
	var assist_id = -1
	var assist_time = -10.0
	var shot_team = -1
	var shot_time = -10.0
	var last_touch_time = -10.0
	var shot_saved = false
	var loose_t = 0.0

var rng = RandomNumberGenerator.new()
var seed_value = 4242

var teams: Array = []
var players: Array = []
var by_id: Dictionary = {}
var ball = Ball.new()
var brain = null  # MatchAI

var clock = 0.0
var half = 1
var phase = "play"                 # play, restart, goal, half_time, full_time
var restart: Dictionary = {}
var restart_timer = 0.0
var added: Array = [0.0, 0.0]
var kickoff_team = 0
var possession_team = 0
var possession_loose = true
var score: Array = [0, 0]
var stats: Array = []
var events: Array = []
var ev_seq = 0
var sim_tick = 0
var goal_timer = 0.0
var last_goal: Dictionary = {}
var finished = false
var half_break_timer = 0.0
var momentum: Array = [0.0, 0.0]
var last_pass_time = 0.0
var flash = 0.0                   # presentation hint: 0..1
var stoppage_events = 0
var commentary_key = 0
var xt_gain = 0.0
var verbose := false
var shot_buckets := {}
var gk_debug := []

func _vlog(msg: String) -> void:
	if verbose:
		print("[%6.2f] %s" % [clock, msg])

func _init(seed_in: int = 4242) -> void:
	seed_value = seed_in
	rng.seed = seed_in
	teams = [
		{
			"id": "MUN", "data": TeamData.get_team("MUN"), "dir": 1, "score": 0,
			"subs_left": 5, "sub_minutes": [62, 71, 80], "subs_made": 0,
		},
		{
			"id": "MCI", "data": TeamData.get_team("MCI"), "dir": -1, "score": 0,
			"subs_left": 5, "sub_minutes": [58, 68, 78], "subs_made": 0,
		},
	]
	stats = [_blank_stats(), _blank_stats()]
	_build_squads()
	brain = MatchAI.new(self)
	setup_kickoff(0, false)

func _blank_stats() -> Dictionary:
	return {
		"possession": 0.0, "shots": 0, "on_target": 0, "goals": 0, "xg": 0.0,
		"passes": 0, "passes_ok": 0, "tackles": 0, "fouls": 0, "corners": 0,
		"offsides": 0, "saves": 0, "yellow": 0, "red": 0, "distance": 0.0,
		"big_chances": 0, "woodwork": 0,
	}

func _build_squads() -> void:
	players.clear()
	by_id.clear()
	for t in range(2):
		var data: Dictionary = teams[t]["data"]
		var i = 0
		for pd in data["starters"]:
			var p = _make_player(pd, t, t * 100 + i)
			players.append(p)
			by_id[p.id] = p
			i += 1

func _make_player(pd: Dictionary, t: int, id_in: int) -> Player:
	var p = Player.new()
	p.id = id_in
	p.team = t
	p.name = pd["name"]
	p.number = pd["number"]
	p.role = pd["role"]
	p.pos_label = pd["pos"]
	p.attr = {
		"ovr": pd["ovr"], "pac": pd["pac"], "sho": pd["sho"], "pas": pd["pas"],
		"dri": pd["dri"], "def": pd["def"], "phy": pd["phy"], "height": pd.get("height", 180),
	}
	p.gk = pd.get("gk", {"div": 30, "han": 30, "kic": 40, "ref": 30, "spd": 60})
	p.is_gk = p.role == "GK"
	p.base = TeamData.formation_slot(teams[t]["data"], p.role)
	p.target = Vector2.ZERO
	return p

# ---------------------------------------------------------------- geometry --

func attacking_dir(t: int) -> int:
	return teams[t]["dir"]

func own_goal_pos(t: int) -> Vector2:
	return Vector2(0.0 if teams[t]["dir"] == 1 else L, W * 0.5)

func target_goal_pos(t: int) -> Vector2:
	return Vector2(L if teams[t]["dir"] == 1 else 0.0, W * 0.5)

func to_world(t: int, norm: Vector2) -> Vector2:
	if teams[t]["dir"] == 1:
		return Vector2(norm.x * L, norm.y * W)
	return Vector2((1.0 - norm.x) * L, norm.y * W)

func to_norm(t: int, world: Vector2) -> Vector2:
	if teams[t]["dir"] == 1:
		return Vector2(world.x / L, world.y / W)
	return Vector2(1.0 - world.x / L, world.y / W)

func attacking_x(t: int, world: Vector2) -> float:
	return world.x if teams[t]["dir"] == 1 else L - world.x

func in_penalty_box(pos: Vector2, defending_team: int) -> bool:
	if teams[defending_team]["dir"] == 1:
		return pos.x <= BOX_D and absf(pos.y - W * 0.5) <= BOX_W * 0.5
	return pos.x >= L - BOX_D and absf(pos.y - W * 0.5) <= BOX_W * 0.5

func is_attacking_third(t: int, pos: Vector2) -> bool:
	var ax = attacking_x(t, pos)
	return ax > L * 0.66

func get_player(id_in: int):
	return by_id.get(id_in, null)

func ball_owner():
	if ball.owner_id < 0:
		return null
	return by_id.get(ball.owner_id, null)

func teammates_of(p) -> Array:
	var out = []
	for q in players:
		if q.team == p.team and q.id != p.id and not q.sent_off:
			out.append(q)
	return out

func opponents_of(p) -> Array:
	var out = []
	for q in players:
		if q.team != p.team and not q.sent_off:
			out.append(q)
	return out

func nearest_opponent(pos: Vector2, t: int):
	var best = null
	var bd = 1e9
	for q in players:
		if q.team == t or q.sent_off:
			continue
		var d = pos.distance_squared_to(q.pos)
		if d < bd:
			bd = d
			best = q
	return best

func nearest_opponent_dist(pos: Vector2, t: int) -> float:
	var q = nearest_opponent(pos, t)
	if q == null:
		return 99.0
	return pos.distance_to(q.pos)

func pressure_on(p) -> float:
	var pressure = 0.0
	for q in players:
		if q.team == p.team or q.sent_off:
			continue
		var d = p.pos.distance_to(q.pos)
		if d < 6.0:
			pressure += (1.0 - d / 6.0)
	return clampf(pressure, 0.0, 2.5)

func opponent_goal_angle(p) -> float:
	# 0..1: how much of the goal mouth is visible from the player's position.
	var g = target_goal_pos(p.team)
	var to_goal = g - p.pos
	if to_goal.length() < 0.001:
		return 1.0
	var half_w = GOAL_W * 0.5
	var dx = absf(g.x - p.pos.x)
	var angles = absf(atan2(half_w, maxf(dx, 0.4)))
	return clampf(angles / 0.9, 0.0, 1.0)

# ---------------------------------------------------------------- lifecycle --

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
		# Keep both teams in their own halves for the kick-off.
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
	# Opponents must be outside the centre circle at kick-off.
	for p in players:
		if p.team != kicking_team:
			var dc: float = p.pos.distance_to(CENTER)
			if dc < 9.15:
				var away: Vector2 = (p.pos - CENTER).normalized()
				if away.length() < 0.1:
					away = Vector2(-teams[p.team]["dir"], 0.0)
				p.pos = CENTER + away * 9.6
	# Put the taker on the ball.
	var taker = _nearest_teammate_to(CENTER, kicking_team, true)
	if taker != null:
		taker.pos = CENTER + Vector2(-0.7 * teams[kicking_team]["dir"], 0.0)
		ball.owner_id = taker.id
		ball.last_touch_id = taker.id
		ball.last_touch_team = kicking_team
		taker.has_ball = true
	brain.on_kickoff()
	_emit("kickoff", "Kick-off. %s get us underway." % teams[kicking_team]["data"]["name"], kicking_team, taker)

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

func start() -> void:
	pass

# -------------------------------------------------------------------- tick --

func tick() -> void:
	if phase == "full_time" or phase == "half_time":
		return
	sim_tick += 1
	clock += DT
	flash = maxf(0.0, flash - DT * 2.0)

	if phase != "goal":
		_tick_clock_end()
		if phase == "half_time" or phase == "full_time":
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
		return

	# Open play.
	brain.update(DT)
	_move_players(DT)
	_ball_physics(DT)
	_ball_interactions(DT)
	_check_rules()
	_update_possession(DT)
	_update_trails(DT)
	_tick_substitutions()

func _tick_clock_end() -> void:
	if half == 1 and clock >= 2700.0 + added[0]:
		_end_first_half()
	elif half == 2 and clock >= 5400.0 + added[1]:
		_end_match()

func _end_first_half() -> void:
	phase = "half_time"
	half_break_timer = 4.0
	_emit("half_time", "Half-time at Old Trafford. %s %d-%d %s." % [teams[0]["data"]["short"], score[0], score[1], teams[1]["data"]["short"]], -1, null)
	blackout()

func blackout() -> void:
	pass

func begin_second_half() -> void:
	if phase != "half_time":
		return
	added[1] = 90.0 + rng.randf_range(0.0, 90.0) + minf(120.0, stoppage_events * 8.0)
	for t in range(2):
		for p in players:
			if p.team == t:
				p.stamina = minf(1.0, p.stamina + 0.06)
	half = 2
	phase = "restart"
	setup_kickoff(1 - kickoff_team, true)

func _end_match() -> void:
	phase = "full_time"
	finished = true
	var line = "Full time. %s %d-%d %s." % [teams[0]["data"]["short"], score[0], score[1], teams[1]["data"]["short"]]
	_emit("full_time", line, -1, null)

func elapsed_minutes() -> float:
	return clock / 60.0

func display_clock() -> String:
	if half == 1:
		if clock <= 2700.0:
			return "%02d:%02d" % [int(clock) / 60, int(clock) % 60]
		return "45:00 +%02d:%02d" % [int(clock - 2700.0) / 60, int(clock - 2700.0) % 60]
	if clock <= 5400.0:
		return "%02d:%02d" % [int(clock) / 60, int(clock) % 60]
	return "90:00 +%02d:%02d" % [int(clock - 5400.0) / 60, int(clock - 5400.0) % 60]

func minute_of(t: float) -> int:
	return clampi(int(ceil(t / 60.0)), 1, 120)

# ----------------------------------------------------------------- physics --

func _move_players(dt: float) -> void:
	for p in players:
		if p.sent_off:
			continue
		if p.cooldown > 0.0:
			p.cooldown = maxf(0.0, p.cooldown - dt)
		if p.action_t > 0.0:
			p.action_t = maxf(0.0, p.action_t - dt)
		if p.jump_t > 0.0:
			p.jump_t = maxf(0.0, p.jump_t - dt)
			p.z = sin((1.0 - p.jump_t / 0.45) * PI) * 0.55 if p.jump_t > 0.0 else 0.0
		else:
			p.z = 0.0
		if p.dive_t > 0.0:
			p.dive_t = maxf(0.0, p.dive_t - dt)
			if p.dive_t <= 0.0:
				p.dive = Vector2.ZERO
		if p.celebrate > 0.0:
			p.celebrate = maxf(0.0, p.celebrate - dt)
			continue

		var to = p.target - p.pos
		var d = to.length()
		var base_speed = Attrs.max_speed(p)
		var fat = 0.70 + 0.30 * p.stamina
		var spd_cap = base_speed * fat * p.speed_scale
		var acc = Attrs.accel(p) * fat
		if ball.owner_id == p.id:
			spd_cap = Attrs.dribble_speed(p) * fat * p.speed_scale
			acc *= 0.86
		elif p.is_gk:
			spd_cap = minf(spd_cap, 5.6 + float(p.gk["spd"]) * 0.022)
		var desired_speed: float = spd_cap
		if d < 3.0:
			desired_speed = minf(spd_cap, d * 2.4)
		var desired_vel = Vector2.ZERO
		if d > 0.02:
			desired_vel = to / d * desired_speed
		# separation from other bodies
		if p.state != "tackle" or true:
			desired_vel += _separation(p) * 1.4
		var dv = desired_vel - p.vel
		var max_dv = acc * dt
		if dv.length() > max_dv:
			dv = dv.normalized() * max_dv
		p.vel += dv
		# clamp overspeed caused by separation pushes
		if p.vel.length() > spd_cap * 1.25:
			p.vel = p.vel.normalized() * spd_cap * 1.25
		p.pos += p.vel * dt
		var moved = p.vel.length() * dt
		p.stats["distance"] += moved
		if p.vel.length() > 0.3:
			p.facing = p.vel.normalized()
		p.stamina = maxf(0.25, p.stamina - Attrs.stamina_drain(p, p.vel.length(), dt))
		# keep bodies loosely on the field
		p.pos.x = clampf(p.pos.x, -3.0, L + 3.0)
		p.pos.y = clampf(p.pos.y, -3.0, W + 3.0)
		if p.has_ball and ball.owner_id != p.id:
			p.has_ball = false

func _separation(p) -> Vector2:
	var push = Vector2.ZERO
	for q in players:
		if q.id == p.id or q.sent_off:
			continue
		var dp = p.pos - q.pos
		var d2 = dp.length_squared()
		if d2 < 1.7 * 1.7 and d2 > 0.0001:
			var d = sqrt(d2)
			var w = (1.7 - d) / 1.7
			push += dp / d * w * 0.55
	return push

func _ball_physics(dt: float, goal_mode: bool = false) -> void:
	if ball.owner_id >= 0:
		var p = by_id.get(ball.owner_id, null)
		if p == null:
			ball.owner_id = -1
		else:
			# Dribble: the ball lives just ahead of the carrier's feet.
			var lead = 0.55 + 0.18 * sin(clock * 9.0 + p.id)
			var ahead = p.facing * lead + p.vel * 0.045
			var target = p.pos + ahead
			ball.pos = ball.pos.lerp(target, clampf(dt * 16.0, 0.0, 1.0))
			ball.vel = p.vel
			ball.z = 0.0
			ball.vz = 0.0
			return
	if ball.z > 0.001 or ball.vz > 0.0:
		ball.vz -= 9.81 * dt
		ball.z += ball.vz * dt
		# magnus / swerve
		if absf(ball.spin) > 0.01:
			var perp = Vector2(-ball.vel.y, ball.vel.x).normalized()
			ball.vel += perp * ball.spin * 0.35 * dt
		ball.vel *= (1.0 - 0.055 * dt)
		if ball.z <= 0.0:
			ball.z = 0.0
			if ball.vz < -0.6:
				ball.vz = -ball.vz * 0.48
				ball.vel *= 0.88
				ball.pos += ball.vel * dt
			else:
				ball.vz = 0.0
	else:
		var sp = ball.vel.length()
		if sp > 0.01:
			var dec = 0.95 + 0.055 * sp
			var ns = maxf(0.0, sp - dec * dt)
			ball.vel = ball.vel.normalized() * ns
		else:
			ball.vel = Vector2.ZERO
		ball.spin *= (1.0 - 2.2 * dt)
	if not goal_mode:
		ball.pos += ball.vel * dt
	else:
		ball.pos += ball.vel * dt * 0.55

func _ball_interactions(dt: float) -> void:
	# Owner keeps control only while the ball is at their feet.
	if ball.owner_id >= 0:
		var own = by_id.get(ball.owner_id, null)
		if own == null or own.pos.distance_to(ball.pos) > 2.4:
			ball.owner_id = -1
		else:
			ball.loose_t = 0.0
			# Opponents can challenge the carrier.
			for q in players:
				if q.team == own.team or q.sent_off or q.is_gk or q.cooldown > 0.0:
					continue
				if q.pos.distance_to(own.pos) < 1.85:
					_attempt_tackle(q, own)
					if ball.owner_id < 0:
						break
			if ball.owner_id >= 0:
				_after_owner_checks()
				return
	else:
		ball.loose_t += dt
	for p in players:
		if p.sent_off or p.cooldown > 0.0:
			continue
		if p.is_gk:
			continue
		var dx = p.pos.x - ball.pos.x
		if absf(dx) > 2.2:
			continue
		var d = p.pos.distance_to(ball.pos)
		var cr = Attrs.control_radius(p)
		if d <= cr and ball.z < 2.1:
			if ball.owner_id >= 0:
				continue
			_try_control(p, d)
	# Goalkeepers handle the ball with their hands.
	var def_team := 0
	for t in range(2):
		if (teams[t]["dir"] == 1) == (ball.pos.x < L * 0.5):
			def_team = t
	var kgk = _gk_of(def_team)
	if kgk != null and not kgk.sent_off and kgk.cooldown <= 0.0:
		var gdx = absf(kgk.pos.x - ball.pos.x)
		if gdx < 2.4:
			var d = kgk.pos.distance_to(ball.pos)
			var reach = 1.75 if ball.z < 2.6 else 1.2
			if d < reach:
				_gk_claim(kgk, d)
	# Desperate blocks: defenders in the shot lane can throw a body in the way.
	if ball.shot_team >= 0 and ball.z < 1.9 and clock - ball.shot_time < 0.9:
		for q in players:
			if q.team == ball.shot_team or q.sent_off or q.is_gk or q.cooldown > 0.0:
				continue
			if q.pos.distance_to(ball.pos) < 1.75:
				var defl: Vector2 = ball.vel.rotated(rng.randf_range(-0.9, 0.9)) * rng.randf_range(0.25, 0.5)
				if q.pos.distance_to(own_goal_pos(q.team)) < 22.0 and defl.dot(own_goal_pos(q.team) - q.pos) > 0.0:
					defl = Vector2(teams[q.team]["dir"], rng.randf_range(-1.0, 1.0)).normalized() * defl.length()
				ball.vel = defl
				ball.vz = rng.randf_range(0.5, 2.0)
				ball.z = maxf(ball.z, 0.3)
				ball.shot_team = -1
				ball.last_touch_id = q.id
				ball.last_touch_team = q.team
				q.cooldown = 0.5
				_emit("block", "%s blocks it!" % q.name, q.team, q)
				_flash(0.35)
				break
	# A loose ball in a crowd eventually squirts clear.
	if ball.owner_id < 0 and ball.loose_t > 1.2:
		var crowd = 0
		for p in players:
			if not p.sent_off and p.pos.distance_to(ball.pos) < 2.6:
				crowd += 1
		if crowd >= 3:
			ball.loose_t = 0.0
			var dir_out := Vector2.from_angle(rng.randf_range(0.0, TAU))
			if ball.pos.x < 12.0:
				dir_out = Vector2(1.0, rng.randf_range(-0.8, 0.8)).normalized()
			elif ball.pos.x > L - 12.0:
				dir_out = Vector2(-1.0, rng.randf_range(-0.8, 0.8)).normalized()
			ball.vel = dir_out * rng.randf_range(5.0, 9.0)
			ball.vz = rng.randf_range(0.5, 2.5)
			ball.z = 0.3
			for p in players:
				if not p.sent_off and p.pos.distance_to(ball.pos) < 2.0:
					p.cooldown = maxf(p.cooldown, 0.3)
	# Aerial duels: headers when the ball is up around head height.
	if ball.z > 0.9 and ball.z < 3.1 and ball.owner_id < 0:
		var winner = null
		var wscore = -1.0
		for p in players:
			if p.sent_off or p.cooldown > 0.0:
				continue
			var d = p.pos.distance_to(ball.pos)
			if d < 1.35:
				var a = Attrs.aerial(p)
				if a > wscore:
					wscore = a
					winner = p
		if winner != null:
			_header(winner)

func _after_owner_checks() -> void:
	pass

func _attempt_tackle(d, carrier) -> void:
	d.cooldown = 0.52
	d.state = "tackle"
	d.action_t = 0.25
	var dist = d.pos.distance_to(carrier.pos)
	var def: float = d.attr["def"] / 100.0
	var dri: float = carrier.attr["dri"] / 100.0
	var rel: Vector2 = carrier.pos - d.pos
	var align: float = clampf(d.facing.dot(rel.normalized()) if rel.length() > 0.01 else 0.0, -1.0, 1.0)
	var speed_adv: float = clampf((carrier.vel.length() - d.vel.length()) / 8.0, -1.0, 1.0)
	var chance: float = 0.10 + def * 0.50 - dri * 0.30 + (1.0 - dist / 1.9) * 0.22 + align * 0.10 - maxf(0.0, speed_adv) * 0.14
	chance = clampf(chance, 0.04, 0.60)
	if rng.randf() < chance:
		d.stats["tackles"] += 1
		stats[d.team]["tackles"] += 1
		carrier.has_ball = false
		carrier.cooldown = 0.45
		ball.owner_id = -1
		ball.last_touch_id = d.id
		ball.last_touch_team = d.team
		ball.shot_team = -1
		ball.assist_id = -1
		ball.pos = carrier.pos + (d.pos - carrier.pos).normalized() * 0.35
		var away_dir := Vector2(teams[d.team]["dir"], rng.randf_range(-0.75, 0.75)).normalized()
		ball.vel = away_dir * rng.randf_range(2.0, 4.5)
		ball.z = 0.0
		ball.vz = 0.0
		possession_team = d.team
		possession_loose = true
		_add_involvement(d, "tackle", "Tackle won", d.pos)
		_flash(0.25)
	else:
		var foul_p: float = 0.0055 + (1.0 - def) * 0.007
		if d.pos.distance_to(e_own_goal_pos_safe(carrier.team)) < 30.0:
			foul_p += 0.02
		if in_penalty_box(carrier.pos, d.team):
			foul_p *= 0.40
		if rng.randf() < foul_p:
			_award_foul(d, carrier)

func e_own_goal_pos_safe(t: int) -> Vector2:
	return own_goal_pos(t)

func _award_foul(fouler, victim) -> void:
	var box = in_penalty_box(victim.pos, fouler.team)
	stats[fouler.team]["fouls"] += 1
	fouler.stats["fouls"] += 1
	# Card decision.
	var dogso = false
	var ax = attacking_x(victim.team, victim.pos)
	if ax > L * 0.62 and not box:
		var defenders_behind = 0
		for q in players:
			if q.team == fouler.team and not q.sent_off and not q.is_gk:
				if attacking_x(victim.team, q.pos) < ax:
					defenders_behind += 1
		dogso = defenders_behind <= 1
	var card = ""
	var r = rng.randf()
	if dogso and r < 0.10:
		card = "red"
	elif r < 0.11:
		card = "yellow"
	if card == "yellow":
		fouler.yellow += 1
		stats[fouler.team]["yellow"] += 1
		if fouler.yellow >= 2:
			card = "red_second"
	elif card == "red":
		stats[fouler.team]["red"] += 1
	if card != "":
		_send_off_or_book(fouler, card)
	var spot = victim.pos
	if box:
		spot = Vector2(PEN_D if fouler.team == 1 else L - PEN_D, W * 0.5)
		_emit("foul", "PENALTY! %s brings down %s." % [fouler.name, victim.name], victim.team, victim)
		_start_restart("penalty", victim.team, spot, 3.6)
	else:
		_emit("foul", "Foul by %s on %s. Free kick." % [fouler.name, victim.name], victim.team, victim)
		_start_restart("free_kick", victim.team, spot, 2.6)
	_flash(0.4)

func _send_off_or_book(p, card: String) -> void:
	if card == "yellow":
		_emit("card", "Yellow card — %s." % p.name, p.team, p)
	elif card == "red_second":
		p.red = true
		p.sent_off = true
		_emit("card", "Second yellow — %s is off!" % p.name, p.team, p)
		stats[p.team]["red"] += 1
		_remove_body(p)
	else:
		p.red = true
		p.sent_off = true
		_emit("card", "RED CARD! %s is sent off." % p.name, p.team, p)
		_remove_body(p)
	stoppage_events += 1

func _remove_body(p) -> void:
	p.vel = Vector2.ZERO
	p.has_ball = false
	if ball.owner_id == p.id:
		ball.owner_id = -1
	p.mark_id = -1
	_add_involvement(p, "card", "Sent off", p.pos)


func _try_control(p, d: float) -> void:
	var speed = ball.vel.length()
	var q = Attrs.first_touch_quality(p)
	var pressure = pressure_on(p)
	var chance := clampf(0.80 + q * 0.26 - speed * 0.006 - pressure * 0.09, 0.42, 0.99)
	if p.offside_flag:
		_offside(p)
		return
	if rng.randf() > chance:
		if verbose:
			_vlog("MISCONTROL %s (speed %.1f chance %.2f)" % [p.name, speed, chance])
		# heavy touch: ball squirts away
		var ang = rng.randf_range(-1.2, 1.2)
		ball.vel = (p.facing.rotated(ang) * rng.randf_range(2.0, 5.0))
		ball.last_touch_id = p.id
		ball.last_touch_team = p.team
		p.cooldown = 0.25
		return
	_claim_ball(p)
	if speed > 11.0 and p.team == possession_team:
		p.stats["touches"] += 1

func _claim_ball(p) -> void:
	# Pass completion for the passer.
	if ball.assist_id >= 0 and ball.last_touch_team == p.team and p.id != ball.assist_id:
		var passer = by_id.get(ball.assist_id, null)
		if passer != null:
			passer.stats["passes_ok"] += 1
			stats[p.team]["passes_ok"] += 1
	# An opponent taking the ball ends the assist window.
	if p.team != ball.last_touch_team:
		ball.assist_id = -1
		ball.shot_team = -1
	ball.owner_id = p.id
	ball.pos = p.pos + p.facing * 0.45
	ball.pos.x = clampf(ball.pos.x, 0.35, L - 0.35)
	ball.pos.y = clampf(ball.pos.y, 0.35, W - 0.35)
	ball.vel = Vector2.ZERO
	ball.z = 0.0
	ball.vz = 0.0
	ball.spin = 0.0
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	p.has_ball = true
	p.action_t = maxf(p.action_t, 0.14)
	p.stats["touches"] += 1
	if verbose:
		_vlog("CLAIM %s at (%.1f,%.1f)" % [p.name, p.pos.x, p.pos.y])
	if possession_team != p.team:
		possession_team = p.team
		possession_loose = false
	for q in players:
		if q.team != p.team:
			q.offside_flag = false
	if p.mark_id >= 0:
		p.mark_id = -1

func _gk_claim(gk, d: float) -> void:
	var speed = ball.vel.length()
	var handle = Attrs.gk_handling(gk)
	var catch_chance = clampf(0.55 + handle * 0.5 - speed * 0.018, 0.25, 0.98)
	var was_shot: bool = ball.shot_team == 1 - gk.team and clock - ball.shot_time < 4.0 and not ball.shot_saved
	gk.cooldown = 0.4
	if rng.randf() < catch_chance:
		ball.owner_id = gk.id
		ball.pos = gk.pos + Vector2(teams[gk.team]["dir"], 0.0) * 0.35
		ball.pos.x = clampf(ball.pos.x, 0.45, L - 0.45)
		ball.pos.y = clampf(ball.pos.y, 0.45, W - 0.45)
		gk.facing = Vector2(teams[gk.team]["dir"], 0.0)
		ball.vel = Vector2.ZERO
		ball.z = 0.0
		ball.vz = 0.0
		ball.last_touch_id = gk.id
		ball.last_touch_team = gk.team
		ball.shot_team = -1
		ball.assist_id = -1
		gk.has_ball = true
		ball.last_touch_time = clock
		if was_shot:
			ball.shot_saved = true
			gk.stats["saves"] += 1
			stats[gk.team]["saves"] += 1
			_emit("save", "Saved! %s holds it." % gk.name, gk.team, gk)
			_flash(0.8)
		gk.action_t = 0.8
		gk.state = "gk_hold"
	else:
		# parry
		var away = (ball.pos - gk.pos).normalized()
		var goal_ward = own_goal_pos(gk.team) - gk.pos
		if away.length() < 0.1 or away.dot(goal_ward.normalized()) > 0.1:
			away = Vector2(teams[gk.team]["dir"], rng.randf_range(-0.9, 0.9)).normalized()
		ball.vel = away.rotated(rng.randf_range(-0.5, 0.5)) * rng.randf_range(6.0, 11.0)
		ball.vz = 1.6
		ball.z = 0.2
		ball.owner_id = -1
		ball.shot_team = -1
		if was_shot:
			ball.shot_saved = true
			gk.stats["saves"] += 1
			stats[gk.team]["saves"] += 1
			_emit("save", "Saved! %s parries it away." % gk.name, gk.team, gk)
			_flash(0.8)

func _header(p) -> void:
	var to_goal = target_goal_pos(p.team) - p.pos
	var dir: Vector2 = to_goal.normalized()
	var attacking = false
	if ball.last_touch_team == p.team or ball.last_touch_team == -1:
		attacking = true
	p.jump_t = 0.45
	p.cooldown = 0.7
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	if p.team == possession_team or attacking:
		# Header at goal if facing it, otherwise cushion to a teammate.
		if to_goal.length() < 18.0 and absf(to_goal.x) > absf(to_goal.y) * 0.3:
			var aim = Vector2(to_goal.x, clampf(to_goal.y, -2.6, 2.6))
			ball.vel = aim.normalized() * rng.randf_range(9.0, 15.0)
			ball.vz = 1.2
			ball.z = maxf(ball.z, 1.7)
			_emit("header", "%s rises to head it goalwards." % p.name, p.team, p)
			_stats_shot(p, 0.18, "header")
		else:
			var mate = _best_outlet(p)
			var tp: Vector2 = mate.pos if mate != null else p.pos + Vector2(teams[p.team]["dir"] * 8.0, 0.0)
			ball.vel = (tp - ball.pos).normalized() * 9.0
			ball.vz = 1.0
	else:
		# Defensive clearance
		var away = Vector2(teams[p.team]["dir"] * 24.0, rng.randf_range(-14.0, 14.0))
		ball.vel = away.normalized() * rng.randf_range(10.0, 16.0)
		ball.vz = 5.5
		ball.z = maxf(ball.z, 1.8)
		_emit("clearance", "%s heads it clear." % p.name, p.team, p)
		ball_kicked.emit(0.5)

func _best_outlet(p):
	var best = null
	var bs = -1e9
	for q in teammates_of(p):
		if q.is_gk:
			continue
		var d: float = p.pos.distance_to(q.pos)
		var adv: float = attacking_x(p.team, q.pos) - attacking_x(p.team, p.pos)
		var s = -absf(d - 14.0) * 0.2 + adv * 0.08 + rng.randf_range(0.0, 2.0)
		if s > bs:
			bs = s
			best = q
	return best

# ----------------------------------------------------------------- actions --

func pass_ball(p, target_point: Vector2, lofted: bool = false, receiver = null, kind: String = "pass") -> void:
	if p == null:
		return
	var dist: float = p.pos.distance_to(target_point)
	var pressure = pressure_on(p)
	var sigma = Attrs.pass_sigma_deg(p, dist, pressure)
	var aim = target_point
	if lofted:
		var land_sigma: float = dist * tan(deg_to_rad(sigma)) * 0.8
		aim += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * land_sigma
		var apex = clampf(dist * 0.16, 3.0, 9.0)
		ball.vz = sqrt(2.0 * 9.81 * apex)
		var flight = 2.0 * ball.vz / 9.81
		var horiz: float = p.pos.distance_to(aim) / maxf(flight, 0.25)
		horiz = clampf(horiz, 6.0, 26.0)
		ball.vel = (aim - p.pos).normalized() * horiz
		ball.z = 0.25
		ball.spin = rng.randf_range(-0.8, 0.8)
	else:
		var ang_err = deg_to_rad(rng.randf_range(-sigma, sigma))
		var dir: Vector2 = (aim - p.pos).normalized().rotated(ang_err)
		var sp: float = Attrs.pass_speed_for(p, dist) * (1.0 + rng.randf_range(-0.06, 0.06))
		ball.vel = dir * sp
		ball.z = 0.0
		ball.vz = 0.0
		ball.spin = rng.randf_range(-0.3, 0.3)
	ball.owner_id = -1
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	ball.last_touch_time = clock
	ball.last_kick_id = p.id
	ball.assist_id = p.id
	ball.assist_time = clock
	ball.shot_team = -1
	p.has_ball = false
	p.cooldown = 0.22
	p.state = "pass"
	p.stats["passes"] += 1
	stats[p.team]["passes"] += 1
	possession_team = p.team
	_mark_offside_at_pass(p)
	# Tell the intended receiver to attack the ball.
	if receiver == null:
		receiver = _nearest_teammate_to(aim, p.team, false, p.id)
	if receiver != null:
		receiver.run_to = aim
		receiver.run_until = clock + 2.6
	if verbose:
		_vlog("PASS %s -> %s aim=(%.1f,%.1f) dist=%.1f loft=%s kind=%s" % [p.name, receiver.name if receiver != null else "-", aim.x, aim.y, dist, str(lofted), kind])
	if kind == "cross":
		_add_involvement(p, "cross", "Cross into the box", p.pos)
		_emit("cross", "%s whips a cross into the box." % p.name, p.team, p)
	elif kind == "through":
		_add_involvement(p, "pass", "Through ball", p.pos)
	else:
		_add_involvement(p, "pass", "Pass %dm" % int(dist), p.pos)

func shoot_ball(p, aim_y: float, aim_z: float, power: float = 1.0, kind: String = "shot") -> void:
	var goal: Vector2 = target_goal_pos(p.team)
	var dist: float = p.pos.distance_to(goal)
	var pressure = pressure_on(p)
	var sigma = Attrs.shot_sigma_deg(p, dist, pressure)
	if kind == "penalty":
		sigma *= 0.30
		# Finishing model: keepers stop most efforts; only the best chances beat them.
	var gkk = _gk_of(1 - p.team)
	var xg_est: float = expected_goals(p.pos, aim_y, p.team)
	var p_goal: float = clampf(0.05 + xg_est * 0.80, 0.035, 0.42)
	if gkk != null and rng.randf() > p_goal and kind != "penalty":
		aim_y = clampf(gkk.pos.y - goal.y + rng.randf_range(-0.85, 0.85), -3.25, 3.25)
	var aim = Vector2(goal.x, goal.y + aim_y)
	var ang = atan2(aim.y - p.pos.y, aim.x - p.pos.x) + deg_to_rad(rng.randf_range(-sigma, sigma))
	var speed = Attrs.shot_speed(p, power) * rng.randf_range(0.94, 1.06)
	var dir = Vector2(cos(ang), sin(ang))
	var flight = maxf(0.12, dist / maxf(speed, 1.0))
	var zt = clampf(aim_z + rng.randf_range(-0.35, 0.35), 0.12, 2.6)
	ball.vz = (zt - 0.11) / flight + 0.5 * 9.81 * flight
	ball.vz = clampf(ball.vz, -1.0, 9.0)
	ball.vel = dir * speed
	ball.z = 0.11
	ball.spin = rng.randf_range(-1.6, 1.6)
	ball.owner_id = -1
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	ball.last_kick_id = p.id
	ball.shot_team = p.team
	ball.shot_time = clock
	ball.shot_saved = false
	ball.assist_id = -1
	# Record whether this one was on target (projected to the goal plane).
	var tg: float = (goal.x - p.pos.x) / maxf(absf(dir.x * speed), 0.1) * signf(goal.x - p.pos.x)
	if tg > 0.0:
		var y_at: float = p.pos.y + dir.y * speed * tg
		var z_at: float = 0.11 + ball.vz * tg - 4.905 * tg * tg
		if absf(y_at - goal.y) < GOAL_W * 0.5 and z_at < GOAL_H and z_at > -0.1:
			p.stats["on_target"] += 1
			stats[p.team]["on_target"] += 1
	p.has_ball = false
	p.cooldown = 0.45
	p.state = "shoot"
	p.action_t = 0.4
	var xg = expected_goals(p.pos, aim_y, p.team)
	shot_buckets[int(dist / 5)] = shot_buckets.get(int(dist / 5), 0) + 1
	_stats_shot(p, xg, kind)
	_add_involvement(p, "shot", "Shot (%.2f xG)" % xg, p.pos)
	stats[p.team]["xg"] += xg
	if xg > 0.28:
		stats[p.team]["big_chances"] += 1
	_emit("shot", "%s lets fly from %s!" % [p.name, _range_word(dist)], p.team, p, {"xg": xg})
	var near_def := 0
	var min_def := 99.0
	var goal_side_def := 0
	var gpos: Vector2 = target_goal_pos(p.team)
	for q in players:
		if q.team == p.team or q.sent_off or q.is_gk:
			continue
		var dd: float = q.pos.distance_to(p.pos)
		if dd < 8.0:
			near_def += 1
		min_def = minf(min_def, dd)
		if q.pos.distance_to(gpos) < p.pos.distance_to(gpos) - 0.5:
			goal_side_def += 1
	var _gkdbg = _gk_of(1 - p.team)
	ball_kicked.emit(1.0)
	if verbose:
		_vlog("SHOT %s dist=%.1f role=%s near_def=%d mindef=%.1f goalside=%d gkdist_goal=%.1f press=%.2f" % [p.name, dist, p.role, near_def, min_def, goal_side_def, _gkdbg.pos.distance_to(gpos) if _gkdbg else -1, pressure])
	_flash(0.7)
	brain.on_shot(p)

func _stats_shot(p, xg: float, kind: String) -> void:
	p.stats["shots"] += 1
	stats[p.team]["shots"] += 1

func expected_goals(pos: Vector2, aim_y: float, team: int) -> float:
	var goal: Vector2 = target_goal_pos(team)
	var d: float = pos.distance_to(goal)
	var ang: float = opponent_goal_angle_for(pos, goal)
	var xg: float = exp(-0.125 * d) * (0.22 + ang * 0.55)
	xg *= 1.0 - clampf((absf(aim_y) - 1.0) * 0.06, 0.0, 0.25)
	return clampf(xg, 0.008, 0.86)

func opponent_goal_angle_for(pos: Vector2, goal: Vector2) -> float:
	var dx = absf(goal.x - pos.x)
	var half = GOAL_W * 0.5
	return clampf(atan2(half, maxf(dx, 0.4)) / 0.9, 0.0, 1.0)

func clear_ball(p, point: Vector2) -> void:
	var dist: float = p.pos.distance_to(point)
	ball.vz = sqrt(2.0 * 9.81 * clampf(dist * 0.22, 4.0, 11.0))
	var flight = 2.0 * ball.vz / 9.81
	ball.vel = (point - p.pos).normalized() * clampf(dist / maxf(flight, 0.2), 8.0, 28.0)
	ball.z = 0.2
	ball.owner_id = -1
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	p.has_ball = false
	p.cooldown = 0.35
	p.state = "clear"
	_emit("clearance", "%s hoofs it clear." % p.name, p.team, p)
	_add_involvement(p, "clearance", "Clearance", p.pos)
	ball_kicked.emit(0.7)

# ------------------------------------------------------------------- rules --

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
			var gk = _gk_of(goal_team)
			if gk != null:
				var gpos: Vector2 = Vector2(own_goal_pos(goal_team).x, ball.pos.y)
				var gd: float = gk.pos.distance_to(gpos)
				var reach: float = Attrs.gk_dive_reach(gk) + 1.05
				gk_debug.append("GOALCHECK gkdist=%.1f reach=%.1f z=%.1f speed=%.1f" % [gd, reach, ball.z, ball.vel.length()])
				if gd < reach + 1.5:
					var save_p: float = 0.86 + (reach - gd) * 0.10 + (Attrs.gk_handling(gk) - 0.8) * 0.30 - ball.vel.length() * 0.004
					save_p = clampf(save_p, 0.08, 0.95)
					if rng.randf() < save_p:
						# A goal-line save.
						var push: Vector2 = Vector2(teams[goal_team]["dir"], rng.randf_range(-1.0, 1.0)).normalized()
						ball.pos = Vector2(0.7 if own_goal_pos(goal_team).x < 1.0 else L - 0.7, clampf(ball.pos.y, 1.0, W - 1.0))
						ball.vel = push * rng.randf_range(7.0, 13.0)
						ball.z = 0.3
						ball.vz = 1.8
						ball.shot_team = -1
						ball.shot_saved = true
						gk.stats["saves"] += 1
						stats[goal_team]["saves"] += 1
						gk.cooldown = 0.5
						_emit("save", "Huge save! %s keeps it out." % gk.name, goal_team, gk)
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
	_emit("goal", "GOAL! %s %d-%d %s. %s, %d'." % [
		teams[0]["data"]["short"], score[0], score[1], teams[1]["data"]["short"],
		scorer_name, minute_of(clock), ], scoring_team, scorer, {"xg": 0.0})
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

func _mark_offside_at_pass(p) -> void:
	if phase != "play":
		return
	var t: int = p.team
	var ax_ball: float = attacking_x(t, ball.pos)
	var defenders = []
	for q in players:
		if q.team == t or q.sent_off:
			continue
		defenders.append(attacking_x(t, q.pos))
	defenders.sort()
	defenders.reverse()
	if defenders.size() < 2:
		return
	var line: float = defenders[1]
	for q in players:
		if q.team != t or q.id == p.id or q.sent_off or q.is_gk:
			continue
		var ax = attacking_x(t, q.pos)
		q.offside_flag = (ax > ax_ball + 0.15 and ax > L * 0.5 and ax > line + 0.12)
		if q.offside_flag:
			q.run_until = 0.0

func _offside(p) -> void:
	if not p.offside_flag:
		return
	stats[p.team]["offsides"] += 1
	_emit("offside", "Offside against %s." % p.name, p.team, p)
	_add_involvement(p, "offside", "Caught offside", p.pos)
	for q in players:
		q.offside_flag = false
	var spot: Vector2 = p.pos
	_start_restart("free_kick", 1 - p.team, spot, 1.0)

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
	ball.owner_id = -1
	ball.vel = Vector2.ZERO
	ball.vz = 0.0
	ball.z = 0.0
	ball.spin = 0.0
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
	restart = {"type": kind, "team": team, "pos": pos, "timer": d, "taker": taker.id if taker != null else -1}
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
	_vlog("RESTART %s team %s at (%.1f,%.1f)" % [kind, teams[team]["id"], pos.x, pos.y])
	_emit(kind, _restart_text(kind, team, taker), team, taker)

func _restart_text(kind: String, team: int, taker) -> String:
	var who: String = taker.name if taker != null else teams[team]["data"]["short"]
	match kind:
		"throw_in": return "Throw-in, %s." % teams[team]["data"]["short"]
		"corner": return "Corner kick to %s." % teams[team]["data"]["short"]
		"goal_kick": return "Goal kick, %s." % who
		"free_kick": return "Free kick to %s." % teams[team]["data"]["short"]
		"penalty": return "PENALTY to %s!" % teams[team]["data"]["short"]
	return "Restart."

func _gk_of(t: int):
	for p in players:
		if p.team == t and p.is_gk and not p.sent_off:
			return p
	return null

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
			var style: float = teams[team]["data"]["style"]["possession"]
			if style > 0.58:
				var mate = _best_short_outlet(team, taker)
				if mate != null:
					pass_ball(taker, mate.pos, false, mate)
				else:
					_clear_long(taker, team)
			else:
				_clear_long(taker, team)
		"corner":
			var target = Vector2(L - 7.5 if restart["pos"].x > L * 0.5 else 7.5, W * 0.5 + rng.randf_range(-4.0, 4.0))
			pass_ball(taker, target, true, null, "cross")
			stats[team]["crosses"] = stats[team].get("crosses", 0) + 1
		"free_kick":
			var goal: Vector2 = target_goal_pos(team)
			var d: float = taker.pos.distance_to(goal)
			if d < 27.0 and opponent_goal_angle(taker) > 0.16 and rng.randf() < 0.45:
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
	if rng.randf() > conversion:
		aim_y = side * rng.randf_range(3.7, 4.6)
	shoot_ball(taker, aim_y, aim_z, 0.92, "penalty")
	ball.pos = restart["pos"]
	phase = "play"
	_emit("penalty_taken", "%s steps up..." % taker.name, team, taker)

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
		var mins: Array = teams[t]["sub_minutes"]
		var made: int = teams[t]["subs_made"]
		if made < mins.size() and clock / 60.0 >= float(mins[made]):
			_make_substitution(t)

func _make_substitution(t: int) -> void:
	var bench: Array = teams[t]["data"]["bench"].duplicate(true)
	var on_field_ids = {}
	for p in players:
		if p.team == t:
			on_field_ids[p.name] = true
	var candidate = {}
	for b in bench:
		if not on_field_ids.has(b["name"]):
			candidate = b
			break
	if candidate.is_empty():
		teams[t]["subs_made"] += 1
		return
	# Replace the most tired outfield player.
	var worst = null
	var worst_score = 1e9
	for p in players:
		if p.team != t or p.is_gk or p.sent_off or p.celebrate > 0.0:
			continue
		var sc: float = p.stamina * 100.0 - (p.pos.distance_to(to_world(t, p.base)) * 0.05)
		if sc < worst_score:
			worst_score = sc
			worst = p
	if worst == null:
		teams[t]["subs_made"] += 1
		return
	var np = _make_player(candidate, t, 200 + t * 40 + teams[t]["subs_made"])
	np.pos = worst.pos
	np.target = worst.target
	np.stamina = 1.0
	var idx = players.find(worst)
	players[idx] = np
	by_id.erase(worst.id)
	by_id[np.id] = np
	if ball.owner_id == worst.id:
		ball.owner_id = np.id
		ball.last_touch_id = np.id
	teams[t]["subs_made"] += 1
	_emit("substitution", "Substitution, %s: %s replaces %s." % [teams[t]["data"]["short"], np.name, worst.name], t, np)
	_add_involvement(np, "sub", "On for %s" % worst.name, np.pos)

# --------------------------------------------------------------- snapshots --

func to_dict() -> Dictionary:
	var ps = []
	for p in players:
		ps.append({
			"id": p.id, "team": p.team, "name": p.name, "number": p.number, "role": p.role,
			"pos_label": p.pos_label, "attr": p.attr, "gk": p.gk, "base": p.base,
			"pos": p.pos, "vel": p.vel, "facing": p.facing, "target": p.target,
			"stamina": p.stamina, "state": p.state, "has_ball": p.has_ball,
			"yellow": p.yellow, "red": p.red, "sent_off": p.sent_off, "is_gk": p.is_gk,
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
			"shot_team": ball.shot_team, "shot_time": ball.shot_time, "shot_saved": ball.shot_saved, "loose_t": ball.loose_t},
		"players": ps, "stats": stats.duplicate(true), "events": events.duplicate(true),
		"ev_seq": ev_seq, "sim_tick": sim_tick, "goal_timer": goal_timer,
		"last_goal": last_goal.duplicate(true), "rng": rng.state, "dirs": [teams[0]["dir"], teams[1]["dir"]],
		"subs": [teams[0]["subs_made"], teams[1]["subs_made"]], "finished": finished,
		"stoppage_events": stoppage_events, "kickoff_team": kickoff_team,
	}

func from_dict(d: Dictionary) -> void:
	clock = d["clock"]
	half = d["half"]
	phase = d["phase"]
	restart = d["restart"].duplicate(true)
	restart_timer = d["restart_timer"]
	added = d["added"].duplicate()
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
	ball.loose_t = b.get("loose_t", 0.0)
	var old_trails := {}
	for q in players:
		old_trails[q.id] = q.trail
	players.clear()
	by_id.clear()
	for pd in d["players"]:
		var p = Player.new()
		p.id = pd["id"]
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
		players.append(p)
		by_id[p.id] = p
	stats = d["stats"].duplicate(true)
	events = d["events"].duplicate(true)
	ev_seq = d["ev_seq"]
	sim_tick = d["sim_tick"]
	goal_timer = d["goal_timer"]
	last_goal = d["last_goal"].duplicate(true)
	rng.state = d["rng"]
	teams[0]["dir"] = d["dirs"][0]
	teams[1]["dir"] = d["dirs"][1]
	teams[0]["subs_made"] = d["subs"][0]
	teams[1]["subs_made"] = d["subs"][1]
	finished = d["finished"]
	stoppage_events = d["stoppage_events"]
	kickoff_team = d["kickoff_team"]
	if brain != null:
		brain.on_restore()

# ------------------------------------------------------------------- misc ---

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
	event_fired.emit(e)

func _add_involvement(p, kind: String, text: String, pos: Vector2) -> void:
	if p == null:
		return
	p.involvements.append({"t": clock, "minute": minute_of(clock), "type": kind, "text": text, "pos": pos})

func _flash(v: float) -> void:
	flash = maxf(flash, v)

func _range_word(d: float) -> String:
	if d < 12.0:
		return "inside the box"
	if d < 22.0:
		return "the edge of the area"
	if d < 30.0:
		return "25 yards"
	return "distance"

func possession_pct() -> Vector2:
	var tot: float = stats[0]["possession"] + stats[1]["possession"]
	if tot < 0.01:
		return Vector2(50, 50)
	var a: float = float(stats[0]["possession"]) / tot * 100.0
	return Vector2(snappedf(a, 0.1), snappedf(100.0 - a, 0.1))

func summary() -> Dictionary:
	return {
		"score": score.duplicate(), "half": half, "clock": display_clock(),
		"possession": possession_pct(), "stats": stats.duplicate(true),
		"events": events.size(), "phase": phase,
	}
