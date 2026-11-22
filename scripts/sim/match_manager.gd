class_name MatchManager
extends RefCounted

## In-match AI managers: the man in the dugout, not the pitch brain.
##
## Event-driven by design. Goals, cards, injuries and half-time feed urgency;
## fatigue and a chasing game are polled on a slow timer. Each side may change
## tactics at most three times (about 2–3 in a normal game) and must leave a
## gap between changes, so the touchline tinkers rather than thrashes.
##
## Substitutions are a separate budget: IFAB five changes in three windows
## (half-time free), chosen by the manager from fatigue, cards and game state.
## All rolls use the match RNG, so a seed always produces the same decisions.

const TACTICS_CAP := 3
const MIN_GAP := 420.0          # seconds between tactical changes
const EARLIEST := 900.0         # no touchline panic inside the first fifteen minutes
const EVAL_INTERVAL := 120.0    # fatigue / chasing poll (not per tick)
const SUB_EARLIEST := 2700.0    # no changes before half-time unless forced
const MIN_SUB_GAP := 200.0
const ACT_SCALE := 0.45

var e = null
var profiles: Array = []
var tactics: Array = []
var changes: Array = [0, 0]
var last_change: Array = [-999.0, -999.0]
var last_sub: Array = [-999.0, -999.0]
var eval_timer := EVAL_INTERVAL
var decisions: Array = []
var reacting := false

func _init(engine) -> void:
	e = engine
	for t in range(2):
		profiles.append(ManagerData.profile(str(e.teams[t]["id"])))
		tactics.append(Tactics.from_team(e.teams[t]["data"], profiles[t]))
		e.live_style[t] = tactics[t].style()

func tactics_for(t: int) -> Tactics:
	return tactics[t]

func manager_name(t: int) -> String:
	return str(profiles[t].get("name", "The manager"))

# ------------------------------------------------------------------ triggers --

## Slow poll for the triggers that are not events: tired legs and a chase.
func tick(dt: float) -> void:
	eval_timer -= dt
	if eval_timer > 0.0:
		return
	eval_timer = EVAL_INTERVAL
	if e.phase != "play" and e.phase != "restart":
		return
	for t in range(2):
		if changes[t] >= TACTICS_CAP:
			continue
		var legs: float = _avg_stamina(t)
		if legs < 0.62 and e.clock > 3300.0 and _margin(t) >= 0:
			_consider_tactics(t, "fatigue", (0.62 - legs) * 0.30)
		if e.clock > 4200.0 and _margin(t) < 0:
			_consider_tactics(t, "chasing", 0.12)
		elif e.clock > 3300.0 and _margin(t) <= 0:
			_consider_tactics(t, "phase", 0.18)

func on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"goal":
			var scored: int = int(data.get("team", 0))
			_consider_tactics(scored, "goal_for", 0.26)
			_consider_tactics(1 - scored, "goal_against", 0.68)
			_consider_subs(1 - scored, false, 0.05)
		"card":
			var t: int = int(data.get("team", 0))
			if bool(data.get("red", false)):
				_consider_tactics(t, "red_against", 0.46)
				_consider_tactics(1 - t, "red_for", 0.24)
				_consider_subs(t, false, 0.08)
			else:
				_consider_tactics(t, "card", 0.12)
		"opponent_tactics":
			_consider_tactics(int(data.get("team", 0)), "opponent_change", 0.18)

## Every dead ball is a legal moment for a change. Cheap: a roll, not a scan.
func on_stoppage(_kind: String, _team: int) -> void:
	for t in range(2):
		_consider_subs(t, false, 0.0)

func on_half_time() -> void:
	for t in range(2):
		_consider_tactics(t, "half_time", 0.55)
		_consider_subs(t, true, 0.0)

func on_second_half() -> void:
	pass

## A forced change: the injured player leaves and the manager picks his
## replacement. Returns false when the change cannot be made (play on short).
func replace_injured(p) -> bool:
	if p == null or p.sent_off:
		return false
	var t: int = p.team
	if int(e.teams[t]["subs_left"]) <= 0:
		return false
	var at_ht: bool = e.phase == "half_time"
	if not e.sub_window_available(t, at_ht):
		return false
	e._emit("injury", Commentary.injury(e.rng, p.name, true), t, p)
	var ok: bool = e._bring_on(t, p, false, at_ht, {"reason": "injury", "manager": manager_name(t)})
	if ok:
		last_sub[t] = e.clock
		_record(t, "injury", "Injury change: %s" % p.name)
	return ok

# ------------------------------------------------------------------ tactics --

func _consider_tactics(t: int, trigger: String, weight: float) -> bool:
	if e == null or t < 0 or t > 1:
		return false
	if changes[t] >= TACTICS_CAP or e.clock < EARLIEST:
		return false
	if e.clock - float(last_change[t]) < MIN_GAP:
		return false
	if e.rng.randf() >= _act_probability(t, weight):
		return false
	var change: Dictionary = _choose_change(t, trigger)
	if change.is_empty():
		return false
	return _apply(t, change, trigger)

func _act_probability(t: int, weight: float) -> float:
	var prof: Dictionary = profiles[t]
	var sit: float = 1.0 - 0.22 * float(changes[t])
	if e.clock > 4200.0 and _margin(t) < 0:
		sit *= 1.20
	var p: float = weight * (0.55 + float(prof.reactive) * 0.9) * (1.15 - float(prof.stubborn) * 0.35) * sit * ACT_SCALE
	return clampf(p, 0.0, 0.80)

## Turn a trigger into concrete levers, weighted by the manager's risk appetite
## and preferred levers. Never returns an empty change for a known trigger.
func _choose_change(t: int, trigger: String) -> Dictionary:
	var prof: Dictionary = profiles[t]
	var levers: Array = prof.get("levers", [])
	var risk: float = float(prof.risk)
	var late: bool = e.clock > 3900.0
	var margin: int = _margin(t)
	var change := {}
	match trigger:
		"goal_against":
			change = {"mentality_shift": 1, "press_delta": 0.04}
			if late or risk > 0.55:
				change["line_delta"] = 0.04
			if risk > 0.62 and late:
				change["formation"] = "4-4-2"
		"goal_for":
			change = {"mentality_shift": -1, "time_wasting": 0.0}
			if late and margin > 0:
				change = {"mentality_shift": -1, "line_delta": -0.05, "time_wasting": 0.55}
		"red_against":
			change = {"mentality_shift": -2, "formation": "5-3-2", "line_delta": -0.06}
		"red_for":
			change = {"mentality_shift": 1, "press_delta": 0.04}
		"chasing":
			change = {"mentality_shift": 1, "press_delta": 0.04, "line_delta": 0.05}
			if risk > 0.55:
				change["formation"] = "4-3-3"
		"fatigue":
			if margin < 0:
				return {}
			change = {"press_delta": -0.05, "tempo_delta": -0.03}
		"opponent_change":
			change = {"press_delta": 0.04 if risk > 0.45 else -0.03, "line_delta": 0.03}
		"half_time":
			change = {"mentality_shift": -1 if margin > 0 else 1, "press_delta": 0.03}
		"phase":
			change = {"mentality_shift": 1 if margin < 0 else -1, "press_delta": 0.03}
		_:
			change = {"mentality_shift": -1 if margin > 0 else 1}
	if levers.has("set_piece") and trigger in ["goal_against", "chasing"]:
		change["corner"] = "near_post"
	if levers.has("width") and trigger == "chasing":
		change["width_delta"] = 0.05
	if levers.has("time_wasting") and late and margin > 0:
		change["time_wasting"] = 0.6
	if levers.has("tempo") and trigger in ["fatigue", "goal_for"]:
		change["tempo_delta"] = -0.05
	return change

func _apply(t: int, change: Dictionary, reason: String) -> bool:
	var labels: Array = tactics[t].apply(change)
	if labels.is_empty():
		return false
	changes[t] += 1
	last_change[t] = e.clock
	if change.has("formation"):
		for q in e.players:
			if q.team == t:
				q.base = TeamData.formation_slot_for(tactics[t].formation, q.role)
	e.live_style[t] = tactics[t].style()
	var short: String = str(e.teams[t]["data"]["short"])
	var text: String = Commentary.tactics(e.rng, manager_name(t), short, labels)
	e._emit("tactics", text, t, null, {
		"manager": manager_name(t), "changes": labels, "formation": tactics[t].formation,
		"mentality": tactics[t].mentality, "reason": reason, "count": changes[t],
	})
	_record(t, "tactics", _join(labels))
	_react_to(t)
	return true

func _react_to(t: int) -> void:
	if reacting:
		return
	reacting = true
	_consider_tactics(1 - t, "opponent_change", 0.18)
	reacting = false

# --------------------------------------------------------------------- subs --

func _consider_subs(t: int, at_half_time: bool, urgency: float) -> bool:
	if int(e.teams[t]["subs_left"]) <= 0:
		return false
	if not at_half_time and e.clock < SUB_EARLIEST:
		return false
	if not at_half_time and e.clock - float(last_sub[t]) < MIN_SUB_GAP:
		return false
	var off = _sub_candidate(t)
	if off == null:
		return false
	if not at_half_time and not e.sub_window_available(t, false):
		return false
	var need: float = 1.0 - float(off.stamina)
	if _margin(t) < 0:
		need += 0.18
	if at_half_time:
		need += 0.25
	var p: float = clampf((0.02 + need * 0.12) * (0.60 + float(profiles[t].sub_style) * 0.80) + urgency, 0.0, 0.85)
	if e.rng.randf() >= p:
		return false
	var reason := "half_time" if at_half_time else "tired"
	return _do_sub(t, off, at_half_time, reason)

## The manager's pick: the most tired run-out outfielder, with a nudge toward
## defenders when the side is chasing and toward booked players.
func _sub_candidate(t: int):
	var best = null
	var best_score := 0.0
	var chasing: bool = _margin(t) < 0 and e.clock > 3900.0
	for p in e.players:
		if p.team != t or p.is_gk or p.sent_off or p.celebrate > 0.0:
			continue
		if p.id >= 200:
			continue
		var score: float = 1.0 - float(p.stamina)
		if chasing and Attrs.is_defender(p.role):
			score += 0.22
		if p.yellow >= 1:
			score += 0.06
		if score > best_score:
			best_score = score
			best = p
	if best_score < 0.10:
		return null
	return best

func _do_sub(t: int, off, at_half_time: bool, reason: String) -> bool:
	var meta := {"reason": reason, "manager": manager_name(t)}
	var ok: bool = e._bring_on(t, off, false, at_half_time, meta)
	if ok:
		last_sub[t] = e.clock
		_record(t, "sub", "%s off (%s)" % [off.name, reason.replace("_", " ")])
	return ok

## Capture/showcase: force one tactics change or one change from the bench so
## a screenshot run can prove the overlay without waiting for a real trigger.
## `--managerstactics` switches the showcase to the tactics card.
func demo() -> void:
	if e == null:
		return
	if OS.get_cmdline_user_args().has("--managerstactics"):
		_apply(0, {"mentality": "attacking", "line_delta": 0.06, "corner": "near_post"}, "demo")
		return
	var off = _sub_candidate(0)
	if off == null:
		for p in e.players:
			if p.team == 0 and not p.is_gk and not p.sent_off:
				off = p
				break
	if off != null:
		_do_sub(0, off, false, "demo")

# -------------------------------------------------------------------- state --

func _margin(t: int) -> int:
	return int(e.score[t]) - int(e.score[1 - t])

func _avg_stamina(t: int) -> float:
	var total := 0.0
	var n := 0
	for p in e.players:
		if p.team != t or p.sent_off or p.is_gk:
			continue
		total += float(p.stamina)
		n += 1
	if n == 0:
		return 1.0
	return total / float(n)

func _record(t: int, kind: String, text: String) -> void:
	decisions.append({
		"clock": e.clock, "minute": e.minute_of(e.clock), "team": t,
		"manager": manager_name(t), "kind": kind, "text": text,
	})
	if decisions.size() > 24:
		decisions.pop_front()

func recent(max_count: int = 3) -> Array:
	var out := []
	for i in range(maxi(0, decisions.size() - max_count), decisions.size()):
		out.append(decisions[i])
	return out

static func _join(labels: Array) -> String:
	var out := ""
	for l in labels:
		out += ("" if out == "" else " · ") + str(l)
	return out

func to_dict() -> Dictionary:
	var tact := []
	for t in range(2):
		tact.append(tactics[t].to_dict())
	return {
		"changes": changes.duplicate(), "last_change": last_change.duplicate(),
		"last_sub": last_sub.duplicate(), "eval_timer": eval_timer,
		"tactics": tact, "decisions": decisions.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	var ch: Array = d.get("changes", [0, 0])
	var lc: Array = d.get("last_change", [-999.0, -999.0])
	var ls: Array = d.get("last_sub", [-999.0, -999.0])
	for t in range(2):
		changes[t] = int(ch[t])
		last_change[t] = float(lc[t])
		last_sub[t] = float(ls[t])
		var td: Array = d.get("tactics", [])
		if td.size() > t and td[t] is Dictionary:
			tactics[t].from_dict(td[t])
	eval_timer = float(d.get("eval_timer", EVAL_INTERVAL))
	decisions = (d.get("decisions", []) as Array).duplicate(true)
	for t in range(2):
		e.live_style[t] = tactics[t].style()
