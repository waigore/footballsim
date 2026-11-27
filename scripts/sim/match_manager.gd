class_name MatchManager
extends RefCounted


const TACTICS_CAP := 3
const EARLIEST := 900.0
const EVAL_INTERVAL := 120.0
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
			MatchManagerTactics.consider(self, t, "fatigue", (0.62 - legs) * 0.30)
		if e.clock > 4200.0 and _margin(t) < 0:
			MatchManagerTactics.consider(self, t, "chasing", 0.12)
		elif e.clock > 3300.0 and _margin(t) <= 0:
			MatchManagerTactics.consider(self, t, "phase", 0.18)

func on_event(kind: String, data: Dictionary) -> void:
	match kind:
		"goal":
			var scored: int = int(data.get("team", 0))
			MatchManagerTactics.consider(self, scored, "goal_for", 0.26)
			MatchManagerTactics.consider(self, 1 - scored, "goal_against", 0.68)
			MatchManagerSubs.consider(self, 1 - scored, false, 0.05)
		"card":
			var t: int = int(data.get("team", 0))
			if bool(data.get("red", false)):
				MatchManagerTactics.consider(self, t, "red_against", 0.46)
				MatchManagerTactics.consider(self, 1 - t, "red_for", 0.24)
				MatchManagerSubs.consider(self, t, false, 0.08)
			else:
				MatchManagerTactics.consider(self, t, "card", 0.12)
		"opponent_tactics":
			MatchManagerTactics.consider(self, int(data.get("team", 0)), "opponent_change", 0.18)


func on_stoppage(_kind: String, _team: int) -> void:
	for t in range(2):
		MatchManagerSubs.consider(self, t, false, 0.0)

func on_half_time() -> void:
	for t in range(2):
		MatchManagerTactics.consider(self, t, "half_time", 0.55)
		MatchManagerSubs.consider(self, t, true, 0.0)

func on_second_half() -> void:
	pass

func replace_injured(p) -> bool:
	return MatchManagerSubs.replace_injured(self, p)


func demo() -> void:
	if e == null:
		return
	if OS.get_cmdline_user_args().has("--managerstactics"):
		MatchManagerTactics.apply(self, 0, {"mentality": "attacking", "line_delta": 0.06, "corner": "near_post"}, "demo")
		return
	var off = MatchManagerSubs.candidate(self, 0)
	if off == null:
		for p in e.players:
			if p.team == 0 and not p.is_gk and not p.sent_off:
				off = p
				break
	if off != null:
		MatchManagerSubs.do_sub(self, 0, off, false, "demo")


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
