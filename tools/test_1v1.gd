extends SceneTree

## Direct regression test: a striker clean through on goal must shoot quickly.

func setup(eng, dist: float, y: float) -> void:
	eng.phase = "play"
	eng.possession_team = 0
	eng.restart = {}
	# Park City's outfield players far behind the ball so the lane is clear.
	for p in eng.players:
		if p.team == 1 and not p.is_gk:
			p.pos = Vector2(5.0, 10.0 + p.id * 2.0)
			p.target = p.pos
			p.cooldown = 5.0
	var striker = eng.by_id[8]  # Bruno Fernandes, MUN
	striker.pos = Vector2(105.0 - dist, y)
	striker.target = striker.pos
	striker.facing = (Vector2(105.0, 34.0) - striker.pos).normalized()
	striker.cooldown = 0.0
	striker.action_t = 0.0
	eng.ball.pos = striker.pos + Vector2(0.4, 0)
	eng.ball.owner_id = striker.id
	eng.ball.last_touch_id = striker.id
	eng.ball.last_touch_team = 0
	eng.ball.vel = Vector2.ZERO
	eng.ball.z = 0.0
	eng.ball.loose_t = 0.0
	eng.brain.last_shot = [-10.0, -10.0]
	eng.brain.decide_cd.clear()

func run_case(dist: float, y: float, label: String) -> void:
	var eng := MatchEngine.new(77)
	var tally := {"shots": 0, "passes": 0}
	eng.event_fired.connect(func(e):
		if e["type"] == "shot": tally["shots"] += 1
		elif e["type"] == "pass": tally["passes"] += 1
	)
	setup(eng, dist, y)
	for i in range(120):
		eng.tick()
	print("%-28s dist=%4.1f y=%4.1f -> shots=%d  passes=%d  ball_owner=%s" % [label, dist, y, tally["shots"], tally["passes"], str(eng.ball.owner_id)])

func _init() -> void:
	run_case(16.0, 34.0, "central 16m")
	run_case(12.0, 34.0, "central 12m")
	run_case(8.0, 34.0, "central 8m")
	run_case(6.0, 44.0, "angled 10m from goal")
	run_case(20.0, 34.0, "central 20m (should pass)")
	quit()
