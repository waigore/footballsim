class_name MatchManagerTactics
extends RefCounted

## Touchline lever changes: the act roll, the trigger→lever map, apply and the
## opponent's reaction. Split from `MatchManager` so the dugout orchestration
## stays under the method ceiling (RUB-P3-01), the same way `MatchCadence`
## holds the wait rule.

static func consider(m: MatchManager, t: int, trigger: String, weight: float) -> bool:
	if m.e == null or t < 0 or t > 1:
		return false
	if m.changes[t] >= MatchManager.TACTICS_CAP or m.e.clock < MatchManager.EARLIEST:
		return false
	if not MatchCadence.may_change(m.profiles[t], m.e.clock - float(m.last_change[t])):
		return false
	if m.e.rng.randf() >= act_probability(m, t, weight):
		return false
	var change: Dictionary = choose(m, t, trigger)
	if change.is_empty():
		return false
	return apply(m, t, change, trigger)


static func act_probability(m: MatchManager, t: int, weight: float) -> float:
	var prof: Dictionary = m.profiles[t]
	var sit: float = 1.0 - 0.22 * float(m.changes[t])
	if m.e.clock > 4200.0 and m._margin(t) < 0:
		sit *= 1.20
	var p: float = weight * (0.55 + float(prof.reactive) * 0.9) * (1.15 - float(prof.stubborn) * 0.35) * sit * MatchManager.ACT_SCALE
	return clampf(p, 0.0, 0.80)


## Turn a trigger into concrete levers, weighted by the manager's risk appetite
## and preferred levers. Never returns an empty change for a known trigger.
static func choose(m: MatchManager, t: int, trigger: String) -> Dictionary:
	var prof: Dictionary = m.profiles[t]
	var levers: Array = prof.get("levers", [])
	var risk: float = float(prof.risk)
	var late: bool = m.e.clock > 3900.0
	var margin: int = m._margin(t)
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


static func apply(m: MatchManager, t: int, change: Dictionary, reason: String) -> bool:
	var labels: Array = m.tactics[t].apply(change)
	if labels.is_empty():
		return false
	m.changes[t] += 1
	m.last_change[t] = m.e.clock
	if change.has("formation"):
		for q in m.e.players:
			if q.team == t:
				q.base = TeamData.formation_slot_for(m.tactics[t].formation, q.role)
	m.e.live_style[t] = m.tactics[t].style()
	var short: String = str(m.e.teams[t]["data"]["short"])
	var text: String = CommentaryBench.tactics(m.e.rng, m.manager_name(t), short, labels)
	m.e._emit("tactics", text, t, null, {
		"manager": m.manager_name(t), "changes": labels, "formation": m.tactics[t].formation,
		"mentality": m.tactics[t].mentality, "reason": reason, "count": m.changes[t],
	})
	m._record(t, "tactics", MatchManager._join(labels))
	react_to(m, t)
	return true


static func react_to(m: MatchManager, t: int) -> void:
	if m.reacting:
		return
	m.reacting = true
	consider(m, 1 - t, "opponent_change", 0.18)
	m.reacting = false
