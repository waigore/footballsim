extends SceneTree

## Dead-ball judgement: a restart waits while the taker's side is still sorting
## itself out, kicks at once when it is set, and never exceeds his patience.
##   godot --headless --path . --script tools/test_restart_wait.gd

const TEAM := 0

func _init() -> void:
	var fails := 0
	fails += _scattered_waits()
	fails += _set_side_does_not_wait()
	fails += _penalty_never_waits()
	fails += _full_match_bounded()
	if fails == 0:
		print("PASS: dead-ball judgement")
	else:
		print("FAIL: %d dead-ball checks" % fails)
	quit()

## Taker's side scattered: he must hold the ball up for a beat, then kick.
func _scattered_waits() -> int:
	var eng := MatchEngine.new(9)
	eng.phase = "play"
	eng.restart = {}
	for q in eng.players:
		if q.team == TEAM and not q.is_gk:
			q.pos = Vector2(70.0, 40.0)
			q.vel = Vector2.ZERO
	eng._start_restart("free_kick", TEAM, Vector2(78.0, 34.0))
	var patience: float = float(eng.restart.get("patience", 0.0))
	var waited := _run_until_kick(eng, 8.0)
	print("scattered side: waited %.2fs (patience %.2fs)" % [waited, patience])
	if waited <= 0.0:
		print("FAIL: scattered side took the free kick with no wait")
		return 1
	if waited > patience + 0.65:
		print("FAIL: wait overran patience")
		return 1
	return 0

## Side already on its slots: the taker should not stall.
func _set_side_does_not_wait() -> int:
	var eng := MatchEngine.new(9)
	eng.phase = "play"
	eng.restart = {}
	eng._start_restart("free_kick", TEAM, Vector2(78.0, 34.0))
	# Let the shape settle for half a second, then pin every team-mate on his slot.
	for i in range(30):
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
	for q in eng.players:
		if q.team == TEAM and not q.is_gk:
			q.pos = q.target
			q.vel = Vector2.ZERO
	eng.restart = {"type": "free_kick", "team": TEAM, "pos": Vector2(78.0, 34.0),
		"timer": 0.0, "taker": eng.restart.get("taker", -1), "base_delay": 0.5,
		"wait": 0.0, "patience": float(eng.restart.get("patience", 2.0)), "called_wait": false,
		"best_ready": 1.0, "ready": 1.0, "still": 0.0}
	eng.restart_timer = 0.0
	var waited := _run_until_kick(eng, 4.0)
	print("settled side: waited %.2fs (one re-read step is fine)" % waited)
	if waited > 0.35:
		print("FAIL: settled side still held the restart up")
		return 1
	return 0

## A penalty never waits for shape — the taker is on his own.
func _penalty_never_waits() -> int:
	var eng := MatchEngine.new(3)
	eng.phase = "play"
	eng.restart = {}
	for q in eng.players:
		if q.team == TEAM and not q.is_gk:
			q.pos = Vector2(20.0, 10.0)
	eng._start_restart("penalty", TEAM, Vector2(94.0, 34.0))
	var waited := _run_until_kick(eng, 8.0)
	print("penalty: waited %.2fs" % waited)
	if waited > 0.0:
		print("FAIL: penalty waited for shape")
		return 1
	return 0

## Across a full match every restart still ends, and total extra wait stays sane.
func _full_match_bounded() -> int:
	var eng := MatchEngine.new(11)
	var prev = null
	var restarts := 0
	var extra := 0.0
	var max_one := 0.0
	var guard := 0
	while eng.phase != "full_time" and guard < 60 * 60 * 400:
		guard += 1
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		if eng.phase == "restart":
			if not is_same(eng.restart, prev):
				prev = eng.restart
				restarts += 1
		elif prev != null:
			var w: float = float(prev.get("wait", 0.0))
			extra += w
			max_one = maxf(max_one, w)
			prev = null
	print("match: %d restarts, %.1fs total extra wait, max %.2fs" % [restarts, extra, max_one])
	if restarts < 10:
		print("FAIL: too few restarts tracked")
		return 1
	if max_one > 4.6:
		print("FAIL: a restart waited past the patience ceiling")
		return 1
	if extra > 180.0:
		print("FAIL: total dead-ball waiting dominates the match")
		return 1
	return 0

## Tick until the restart resolves (phase leaves "restart"); return extra wait.
func _run_until_kick(eng, cap: float) -> float:
	var r = eng.restart
	var t := 0.0
	while eng.phase == "restart" and t < cap:
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		t += 1.0 / 60.0
	return float(r.get("wait", 0.0))
