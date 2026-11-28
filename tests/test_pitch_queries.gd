extends GdToolsTest


func _engine(seed_in: int = 31) -> MatchEngine:
	var eng := MatchEngine.new(seed_in, "ENG-MUN1", "ENG-MCI1")
	eng.phase = "play"
	eng.possession_team = 0
	return eng


func _seeded(seed_in: int) -> MatchEngine:
	return TestEngineBoot.match(seed_in)


func _walk_reach(eng, p) -> float:
	var bp: Vector2 = eng.ball.pos
	var bv: Vector2 = eng.ball.vel
	var spd: float = Attrs.max_speed(p) * (0.72 + 0.28 * p.stamina)
	var t := 0.0
	while t < 3.6:
		if p.pos.distance_to(bp) <= spd * t + 1.35:
			return t
		bp += bv * 0.12
		var dec: float = 0.95 + 0.055 * bv.length()
		bv = bv.move_toward(Vector2.ZERO, dec * 0.12)
		t += 0.12
	return 9.0

func _walk_intercept(eng, p) -> Vector2:
	var bp: Vector2 = eng.ball.pos
	var bv: Vector2 = eng.ball.vel
	var spd: float = Attrs.max_speed(p) * (0.72 + 0.28 * p.stamina)
	var t := 0.0
	var last := bp
	while t < 3.6:
		last = bp
		if p.pos.distance_to(bp) <= spd * t + 1.35:
			return bp
		bp += bv * 0.12
		var dec: float = 0.95 + 0.055 * bv.length()
		bv = bv.move_toward(Vector2.ZERO, dec * 0.12)
		t += 0.12
	return last


func _in_flight() -> MatchEngine:
	var eng := _engine()
	eng.ball.pos = eng.to_world(0, Vector2(0.55, 0.5))
	eng.ball.vel = Vector2(12.0, 2.5)
	eng.ball.owner_id = -1
	return eng


func test_shared_path_answers_the_same_reach_time_as_the_per_player_walk() -> void:
	var eng := _in_flight()
	var pq := PitchQueries.new(eng)
	var path: Dictionary = pq.ball_trajectory()
	assert_gt(path["points"].size(), 20, "the path had fewer than the 30 samples a 3.6s walk holds")
	for p in eng.players:
		if p.sent_off:
			continue
		assert_eq(pq.reach_time_on(p, path), _walk_reach(eng, p),
			"the shared path changed %s's reach time" % p.key)

func test_shared_path_answers_the_same_intercept_point() -> void:
	var eng := _in_flight()
	var pq := PitchQueries.new(eng)
	var path: Dictionary = pq.ball_trajectory()
	for p in eng.players:
		if p.sent_off:
			continue
		assert_eq(pq.intercept_on(p, path), _walk_intercept(eng, p),
			"the shared path moved %s's intercept point" % p.key)

func test_a_still_ball_is_reachable_by_the_man_standing_on_it() -> void:
	var eng := _engine(33)
	var pq := PitchQueries.new(eng)
	var p = eng.players[4]
	eng.ball.pos = p.pos + Vector2(0.4, 0.0)
	eng.ball.vel = Vector2.ZERO
	var path: Dictionary = pq.ball_trajectory()
	assert_eq(pq.reach_time_on(p, path), 0.0, "a body next to a still ball is not credited with being there now")
	assert_eq(pq.intercept_on(p, path), eng.ball.pos, "a still ball's intercept point is not where it sits")

func test_a_ball_far_beyond_the_horizon_is_unreachable() -> void:
	var eng := _engine(34)
	var pq := PitchQueries.new(eng)
	var p = eng.players[6]
	eng.ball.pos = p.pos + Vector2(60.0, 0.0)
	eng.ball.vel = Vector2.ZERO
	var path: Dictionary = pq.ball_trajectory()
	assert_eq(pq.reach_time_on(p, path), PitchQueries.UNREACHABLE,
		"a ball 60 m away was reported reachable inside 3.6 s")

func test_the_wrappers_still_answer_the_per_player_walk() -> void:
	var eng := _in_flight()
	var pq := PitchQueries.new(eng)
	for p in eng.players:
		if p.sent_off:
			continue
		assert_eq(pq.ball_reach_time(p), _walk_reach(eng, p),
			"ball_reach_time no longer matches the walk it replaced for %s" % p.key)
		assert_eq(pq.intercept_point(p), _walk_intercept(eng, p),
			"intercept_point no longer matches the walk it replaced for %s" % p.key)


func test_the_defensive_line_is_the_deepest_outfield_back() -> void:
	var eng := _engine(36)
	var pq := PitchQueries.new(eng)
	for t in range(2):
		var deepest = null
		var deepest_ax := 1.0e9
		for p in eng.players:
			if p.team != t or p.sent_off or p.is_gk or not Attrs.is_defender(p.role):
				continue
			var ax: float = eng.attacking_x(t, p.pos)
			if ax < deepest_ax:
				deepest_ax = ax
				deepest = p
		assert_true(deepest != null, "side %d fielded no outfield defender" % t)
		assert_eq(pq.defensive_line(t), deepest.pos, "side %d's line is not its deepest back" % t)

func test_the_defensive_line_is_shared_within_one_shape_pass() -> void:


	var eng := _engine(37)
	var pq := PitchQueries.new(eng)
	var shared := {}
	for p in eng.players:
		if p.team != 0 or p.sent_off or p.is_gk or not Attrs.is_defender(p.role):
			continue
		if not shared.has(p.team):
			shared[p.team] = pq.defensive_line(p.team)
		assert_eq(shared[p.team], pq.defensive_line(p.team),
			"the line moved between two backs of the same side inside one pass")


func test_the_line_follows_the_bodies_rather_than_a_stale_read() -> void:


	var eng := _engine(38)
	var pq := PitchQueries.new(eng)
	var before: Vector2 = pq.defensive_line(1)
	var backs: Array = []
	for p in eng.players:
		if p.team == 1 and not p.sent_off and not p.is_gk and Attrs.is_defender(p.role):
			backs.append(p)
	assert_gt(backs.size(), 1, "side 1 did not field a back four")


	var spot: Vector2 = eng.to_world(1, Vector2(0.30, 0.5))
	for i in backs.size():
		backs[i].pos = spot + Vector2(0.0, 3.0 * float(i))
	backs[0].pos = eng.to_world(1, Vector2(0.22, 0.5))
	var after: Vector2 = pq.defensive_line(1)
	assert_eq(after, backs[0].pos, "the line did not follow the back four that moved")
	assert_true(after != before, "the line was answered from a stale read rather than the bodies on the pitch")


func test_a_shared_path_leaves_a_seeded_match_reproducible() -> void:
	var a := _seeded(4242)
	var b := _seeded(4242)
	var seen: Array = []
	var after_play := 0
	for i in 140:
		if a.phase == "half_time":
			a.begin_second_half()
			b.begin_second_half()
		a.tick()
		b.tick()
		if not seen.has(a.phase):
			seen.append(a.phase)
		if seen.has("play"):
			after_play += 1
			if after_play >= 36:
				break
	assert_true(seen.has("play"), "the seeded match never reached open play")
	for i in a.players.size():
		assert_eq(a.players[i].pos, b.players[i].pos, "the same seed drifted the squad's positions")
	assert_eq(a.ball.pos, b.ball.pos, "the same seed drifted the ball")
	assert_eq(a.score, b.score, "the same seed drifted the score")
