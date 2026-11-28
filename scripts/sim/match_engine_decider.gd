extends "res://scripts/sim/match_engine_snapshot.gd"


const ET_FIRST_END := 6300.0
const ET_SECOND_END := 7200.0

const SHOOTOUT_START := 2.4
const SHOOTOUT_GAP := 3.0

const SHOOTOUT_ROUND := 5


var shootout: Array = []

var shootout_score: Array = [0, 0]
var shootout_timer := 0.0

var shootout_ids: Array = [[], []]
var shootout_done := false


func _second_half_over() -> void:
	if requires_winner and int(score[0]) == int(score[1]):
		phase = "et_break"
		half_break_timer = 3.0
		_emit("extra_time", CommentaryExtraTime.extra_time(rng, _short(0), _short(1)), -1, null)
		blackout()
		return
	_end_match()

func resume_after_break() -> void:
	if phase != "et_break":
		return
	if half == 2:
		_begin_extra_time()
	elif half == 3:
		_begin_extra_time_second()

func _begin_extra_time() -> void:
	added[2] = 20.0 + rng.randf_range(0.0, 40.0)
	for p in players:
		p.stamina = minf(1.0, p.stamina + 0.03)
	half = 3
	phase = "restart"
	setup_kickoff(1 - kickoff_team, true)
	_emit("extra_time_start", CommentaryExtraTime.extra_time_start(rng, _short(0), _short(1)), -1, null)

func _begin_extra_time_second() -> void:
	added[3] = 15.0 + rng.randf_range(0.0, 35.0)
	stoppage_events = 0
	injury_timer = 30.0
	half = 4
	phase = "restart"
	setup_kickoff(1 - kickoff_team, true)
	_emit("extra_time_second", CommentaryExtraTime.extra_time_second(rng, _short(0), _short(1)), -1, null)

func _tick_extra_time_period() -> void:
	if half == 3:
		if clock >= ET_FIRST_END + float(added[2]):
			phase = "et_break"
			half_break_timer = 3.0
			_emit("extra_time_break", CommentaryExtraTime.extra_time_break(), -1, null)
			blackout()
		return
	if half == 4 and clock >= ET_SECOND_END + float(added[3]):
		if int(score[0]) == int(score[1]):
			_begin_shootout()
		else:
			_end_match()


func _begin_shootout() -> void:
	phase = "shootout"
	shootout_timer = SHOOTOUT_START
	shootout = []
	shootout_score = [0, 0]
	shootout_done = false
	_build_shootout_order()
	_emit("shootout_start", CommentaryExtraTime.shootout_start(rng, _short(0)), -1, null)

func _tick_shootout(dt: float) -> void:
	if shootout_done:
		return
	shootout_timer -= dt
	if shootout_timer > 0.0:
		return
	shootout_timer = SHOOTOUT_GAP
	_take_shootout_kick()


func _build_shootout_order() -> void:
	for t in range(2):
		var pool: Array = []
		for p in players:
			if p.team == t and not p.sent_off and not p.is_gk:
				pool.append(p)

		var n: int = pool.size()
		for i in range(n):
			var top: int = i
			for j in range(i + 1, n):
				if _pen_score(pool[j]) > _pen_score(pool[top]):
					top = j
			if top != i:
				var held = pool[i]
				pool[i] = pool[top]
				pool[top] = held
		var ids: Array = []
		for p in pool:
			ids.append(p.id)
		shootout_ids[t] = ids

static func _pen_score(p) -> float:
	return float(p.attr["sho"]) * 1.4 + float(p.attr["ovr"])

func _take_shootout_kick() -> void:
	var t: int = shootout.size() % 2
	var p = _shootout_taker(t)
	var conversion := 0.74
	var who := ""
	if p != null:
		conversion = clampf(0.74 + float(p.attr["sho"]) * 0.0016, 0.55, 0.94)
		who = str(p.name)
	var scored: bool = rng.randf() <= conversion
	if scored:
		shootout_score[t] = int(shootout_score[t]) + 1
	shootout.append({
		"team": t, "player": who, "player_id": p.id if p != null else -1,
		"scored": scored, "pens": shootout_score.duplicate(),
	})
	var kind := "penalty_scored" if scored else "penalty_missed"
	_emit(kind, CommentaryExtraTime.shootout_kick(rng, who, scored), t, p)
	if _shootout_decided():
		_finish_shootout()

func _shootout_taker(t: int):
	var ids: Array = shootout_ids[t] if t < shootout_ids.size() else []
	if not ids.is_empty():
		var index: int = _shootout_kicks_for(t)
		var p = by_id.get(int(ids[index % ids.size()]), null)
		if p != null and not p.sent_off:
			return p
	var best = null
	var bs := -1.0
	for q in players:
		if q.team == t and not q.sent_off and not q.is_gk:
			if _pen_score(q) > bs:
				bs = _pen_score(q)
				best = q
	if best == null:
		best = _gk_of(t)
	return best

func _shootout_kicks_for(t: int) -> int:
	var n := 0
	for k in shootout:
		if int(k.get("team", -1)) == t:
			n += 1
	return n


func _shootout_decided() -> bool:
	var a: int = int(shootout_score[0])
	var b: int = int(shootout_score[1])
	var ta: int = _shootout_kicks_for(0)
	var tb: int = _shootout_kicks_for(1)
	if ta < SHOOTOUT_ROUND or tb < SHOOTOUT_ROUND:
		if a > b + (SHOOTOUT_ROUND - tb):
			return true
		if b > a + (SHOOTOUT_ROUND - ta):
			return true
		return false
	return ta == tb and a != b

func _finish_shootout() -> void:
	shootout_done = true
	winner = 0 if int(shootout_score[0]) > int(shootout_score[1]) else 1
	var line: String = CommentaryExtraTime.shootout_end(_short(winner),
		int(shootout_score[winner]), int(shootout_score[1 - winner]))
	_emit("shootout_end", line, winner, null)
	_end_match()

func _full_time_text() -> String:
	if not shootout.is_empty():
		return CommentaryExtraTime.full_time_pens(rng, _short(0), int(score[0]),
			_short(1), int(score[1]), int(shootout_score[0]), int(shootout_score[1]))
	return super()


func _short(t: int) -> String:
	return str(teams[t]["data"]["short"])

func to_dict() -> Dictionary:
	var d: Dictionary = super()
	d["requires_winner"] = requires_winner
	d["winner"] = winner
	d["shootout"] = shootout.duplicate(true)
	d["shootout_score"] = shootout_score.duplicate()
	d["shootout_timer"] = shootout_timer
	d["shootout_ids"] = shootout_ids.duplicate(true)
	d["shootout_done"] = shootout_done
	return d

func from_dict(d: Dictionary) -> void:
	super(d)
	requires_winner = bool(d.get("requires_winner", false))
	winner = int(d.get("winner", -1))
	shootout = d.get("shootout", []).duplicate(true)
	shootout_score = d.get("shootout_score", [0, 0]).duplicate()
	shootout_timer = float(d.get("shootout_timer", 0.0))
	shootout_ids = d.get("shootout_ids", [[], []]).duplicate(true)
	shootout_done = bool(d.get("shootout_done", false))
