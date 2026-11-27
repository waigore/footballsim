extends "res://scripts/sim/match_engine_rules.gd"


func _tick_substitutions() -> void:


	for t in range(2):
		if int(teams[t]["subs_left"]) <= 0:
			continue
		if _gk_of(t) == null and not _bench_keeper(t).is_empty():
			_make_substitution(t, true)


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


func _bring_on(t: int, off, for_gk: bool = false, at_half_time: bool = false, meta: Dictionary = {}) -> bool:
	if off == null or int(teams[t]["subs_left"]) <= 0:
		return false
	if not for_gk and not _use_sub_window(t, at_half_time):
		return false
	var candidate: Dictionary = _pick_bench(t, off.role, for_gk or off.is_gk)
	if candidate.is_empty():
		return false
	var np = _make_player(candidate, t, 200 + t * 40 + int(teams[t]["subs_made"]))

	np.role = off.role
	np.is_gk = off.is_gk
	np.base = off.base
	np.pos = off.pos
	np.target = off.target
	np.stamina = 1.0
	var idx = players.find(off)
	players[idx] = np
	appeared.append(np)
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
	_emit("substitution", CommentaryBench.substitution(rng, teams[t]["data"]["short"], np.name, off.name,
		str(meta.get("manager", ""))), t, np, info)
	_add_involvement(np, "sub", "On for %s" % off.name, np.pos)
	return true


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


	if manager != null and manager.replace_injured(p):
		return
	_emit("injury", CommentaryBench.injury(rng, p.name, false), t, p)
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
