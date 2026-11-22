extends GdToolsTest

## Dead-ball judgement: a restart waits while the taker's side is still sorting
## itself out, kicks at once when it is set, and never exceeds his patience.

const TEAM := 0

func _run_until_kick(eng, cap: float) -> float:
	var r = eng.restart
	var t := 0.0
	while eng.phase == "restart" and t < cap:
		eng.tick()
		t += 1.0 / 60.0
	return float(r.get("wait", 0.0))

func test_scattered_side_waits() -> void:
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
	assert_gt(waited, 0.0, "scattered side took the free kick with no wait")
	assert_lte(waited, patience + 0.35, "wait overran patience")

func test_settled_side_does_not_wait() -> void:
	var eng := MatchEngine.new(9)
	eng.phase = "play"
	eng.restart = {}
	eng._start_restart("free_kick", TEAM, Vector2(78.0, 34.0))
	for i in range(30):
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
	assert_lte(waited, 0.35, "settled side still held the restart up")

func test_penalty_never_waits() -> void:
	var eng := MatchEngine.new(3)
	eng.phase = "play"
	eng.restart = {}
	for q in eng.players:
		if q.team == TEAM and not q.is_gk:
			q.pos = Vector2(20.0, 10.0)
	eng._start_restart("penalty", TEAM, Vector2(94.0, 34.0))
	assert_eq(_run_until_kick(eng, 8.0), 0.0, "penalty waited for shape")

func test_kickoff_never_waits() -> void:
	var eng := MatchEngine.new(4)
	var guard := 0
	while eng.phase == "restart" and guard < 600:
		eng.tick()
		guard += 1
	assert_eq(float(eng.restart.get("wait", 0.0)), 0.0, "kick-off waited for shape")

func test_patience_is_bounded() -> void:
	var eng := MatchEngine.new(9)
	eng.phase = "play"
	eng.restart = {}
	eng._start_restart("corner", TEAM, Vector2(105.0, 0.0))
	var patience: float = float(eng.restart.get("patience", 0.0))
	assert_lte(patience, 4.5, "patience above the ceiling")
	assert_gte(patience, 0.0, "negative patience")
