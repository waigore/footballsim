class_name MatchManagerSubs
extends RefCounted


const EARLIEST := 2700.0
const MIN_GAP := 200.0

static func consider(m: MatchManager, t: int, at_half_time: bool, urgency: float) -> bool:
	if int(m.e.teams[t]["subs_left"]) <= 0:
		return false
	if not at_half_time and m.e.clock < EARLIEST:
		return false
	if not at_half_time and m.e.clock - float(m.last_sub[t]) < MIN_GAP:
		return false
	var off = candidate(m, t)
	if off == null:
		return false
	if not at_half_time and not m.e.sub_window_available(t, false):
		return false
	var need: float = 1.0 - float(off.stamina)
	if m._margin(t) < 0:
		need += 0.18
	if at_half_time:
		need += 0.25
	var p: float = clampf((0.02 + need * 0.12) * (0.60 + float(m.profiles[t].sub_style) * 0.80) + urgency, 0.0, 0.85)
	if m.e.rng.randf() >= p:
		return false
	var reason := "half_time" if at_half_time else "tired"
	return do_sub(m, t, off, at_half_time, reason)


static func candidate(m: MatchManager, t: int):
	var best = null
	var best_score := 0.0
	var chasing: bool = m._margin(t) < 0 and m.e.clock > 3900.0
	for p in m.e.players:
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


static func do_sub(m: MatchManager, t: int, off: Variant, at_half_time: bool, reason: String) -> bool:
	var meta := {"reason": reason, "manager": m.manager_name(t)}
	var ok: bool = m.e._bring_on(t, off, false, at_half_time, meta)
	if ok:
		m.last_sub[t] = m.e.clock
		m._record(t, "sub", "%s off (%s)" % [off.name, reason.replace("_", " ")])
	return ok


static func replace_injured(m: MatchManager, p: Variant) -> bool:
	if p == null or p.sent_off:
		return false
	var t: int = p.team
	if int(m.e.teams[t]["subs_left"]) <= 0:
		return false
	var at_ht: bool = m.e.phase == "half_time"
	if not m.e.sub_window_available(t, at_ht):
		return false
	m.e._emit("injury", CommentaryBench.injury(m.e.rng, p.name, true), t, p)
	var ok: bool = m.e._bring_on(t, p, false, at_ht, {"reason": "injury", "manager": m.manager_name(t)})
	if ok:
		m.last_sub[t] = m.e.clock
		m._record(t, "injury", "Injury change: %s" % p.name)
	return ok
