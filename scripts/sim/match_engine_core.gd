extends RefCounted

## Match state, geometry and squad construction — the base of the MatchEngine
## chain. Each split file adds one layer: presentation, actions, play, rules,
## clock, then the restarts leaf in match_engine.gd.

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

## Dead-ball judgement. The taker only kicks once most of his side is roughly on
## its slot; how long he is willing to hold play up depends on how well he reads
## the game and on whether the clock is on his side.
const RESTART_READY_RADIUS := 8.5   # metres from a player's target that counts as set
const RESTART_SETTLED_SPEED := 3.0  # m/s; still sprinting = not set
const RESTART_WAIT_STEP := 0.3      # seconds per re-read while holding play up

## Referee movement: he runs the opposite side of the diagonal to the ball,
## a dozen metres behind it, and closes on the spot when play stops.
const REF_TRAIL := 12.0
const REF_SIDE := 6.5
const REF_JOG := 7.6
const REF_SPRINT := 8.8

## Share of shot blocks that are really an arm in the flight path.
const HANDBALL_P := 0.055

## IFAB substitution limits: five changes, three windows, half-time free.
const SUB_WINDOWS := 3
const SUB_LIMIT := 5

## Finishing calibration against the Poisson model: a shot converts with
## p = FINISH_EFFICIENCY · xG, so a match's goals track its expected goals (the
## model's λ) instead of the old keeper-steer hack.
const FINISH_EFFICIENCY := 1.0
## Positional xG is calibrated down to real-football levels.
const XG_SCALE := 0.70

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
	var injured = false
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
	var shot_xg = 0.0
	var last_touch_time = -10.0
	var shot_saved = false
	var planned_goal = false   # this on-target shot has already beaten the keeper
	var loose_t = 0.0

## The match official. Presentation only: laws are decided by the engine, but
## the referee has a body on the pitch, a position that follows play and a
## whistle that fires on restarts, cards and disciplinary calls.
class Official:
	var pos = Vector2(52.5, 24.0)
	var vel = Vector2.ZERO
	var facing = Vector2.RIGHT
	var whistle = 0.0          # presentation: seconds of whistle / arm-raise left
	var focus = Vector2.ZERO   # where play stopped (foul spot, kick-off spot)
	var focus_t = 0.0

var rng = RandomNumberGenerator.new()
var home_team := 0
var home_advantage := 0.05   # +5% composure/duels for the home side
var seed_value = 4242

var teams: Array = []
var players: Array = []
var by_id: Dictionary = {}
var ball = Ball.new()
var referee = Official.new()
var referee_name: String = TeamData.REFEREE
var brain = null  # MatchAI: the pitch
var manager = null  # MatchManager: the dugout
var live_style: Array = [{}, {}]  # effective tactics style per side, refreshed on change
var stoppage_seq := 0  # dead-ball counter; subs in the same stoppage share a window

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
var injury_timer := 45.0
var commentary_key = 0
var xt_gain = 0.0
var verbose := false
var shot_buckets := {}
var gk_debug := []

## Home advantage, expressed as a multiplier on technical execution.
## >1 means less error for the home side; <1 slightly more for the visitors.
func home_factor(p) -> float:
	if p.team == home_team:
		return 1.0 + home_advantage
	return 1.0 - home_advantage * 0.5

## Shirt colour the side is actually wearing in this match (kit selection may
## have sent the visitors to their change kit).
func kit_color(t: int) -> Color:
	var kit: Dictionary = teams[t].get("kit", {})
	if kit.has("shirt"):
		return kit["shirt"]
	return teams[t]["data"]["color"]

# ------------------------------------------------------------- tactics bridge --

## MatchAI reads the side's effective FM style from here instead of the static
## club style, so a manager change moves the whole pitch.
func style_of(t: int) -> Dictionary:
	return live_style[t]

## Role push after the manager's duty instruction (attack runs higher, defend
## holds deeper) is applied on top of the squad role.
func push_of(p) -> float:
	if manager == null:
		return Attrs.role_push(p.role)
	return Attrs.role_push(p.role) + manager.tactics_for(p.team).duty_offset(p.role)

func _blank_stats() -> Dictionary:
	return {
		"possession": 0.0, "shots": 0, "on_target": 0, "goals": 0, "xg": 0.0,
		"passes": 0, "passes_ok": 0, "tackles": 0, "fouls": 0, "corners": 0,
		"offsides": 0, "saves": 0, "yellow": 0, "red": 0, "distance": 0.0,
		"big_chances": 0, "woodwork": 0, "handballs": 0, "injuries": 0,
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

func _gk_of(t: int):
	for p in players:
		if p.team == t and p.is_gk and not p.sent_off:
			return p
	return null

## Name of the player whose effort has just been stopped, unless the ball was
## last kicked by the stopping side (deflections, blocks, keeper clearances).
func _last_kicker_name(not_team: int) -> String:
	var k = by_id.get(ball.last_kick_id, null)
	if k == null or k.team == not_team:
		return ""
	return k.name

func _shot_credit(gk) -> String:
	return _last_kicker_name(gk.team)
