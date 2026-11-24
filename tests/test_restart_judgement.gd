extends GdToolsTest

## Dead-ball judgement, split out of the engine leaf: how a taker reads his
## side's shape, how long he holds play up, and when the wait ends even if the
## picture never hits the ideal. Engine-level, seeded, headless.

func _eng(seed_in: int = 61) -> MatchEngine:
	var eng := MatchEngine.new(seed_in)
	eng.phase = "restart"
	eng.restart = {"type": "throw_in", "team": 0, "pos": Vector2(60.0, 0.0), "wait": 0.0, "patience": 3.0}
	return eng

func _taker(eng) -> Object:
	for p in eng.players:
		if p.team == 0 and not p.is_gk:
			return p
	return null

## A stand-in taker carrying a chosen technical profile, for the reads that
## only look at pas/ovr and never need the live object.
func _reader(pas: int, ovr: int) -> Object:
	var p = MatchEngine.new(62).players[1]
	p.attr = p.attr.duplicate()
	p.attr["pas"] = pas
	p.attr["ovr"] = ovr
	return p

## Put the whole side on its slots offset by `offset`, moving at `speed`, then
## read the picture from inside the shape so every mate is in range.
func _set_side(eng, taker, offset: Vector2, speed: float) -> void:
	var anchor := Vector2.ZERO
	for q in eng.players:
		if q.team != 0 or q.sent_off or q.is_gk:
			continue
		q.target = q.base
		q.pos = q.base + offset
		q.vel = Vector2(speed, 0.0)
		if q.id == taker.id:
			anchor = q.pos
	taker.pos = anchor
	taker.target = anchor

func test_a_side_on_its_slots_reads_as_set() -> void:
	var eng := _eng()
	var taker = _taker(eng)
	_set_side(eng, taker, Vector2.ZERO, 0.0)
	var pic := MatchRestarts.picture(eng, 0, taker, taker.pos)
	assert_almost_eq(pic.x, 1.0, 0.001, "a settled side was not read as set")
	assert_almost_eq(pic.y, 0.0, 0.001, "a settled side still reported an error")

func test_a_side_still_sprinting_is_not_set() -> void:
	var eng := _eng()
	var taker = _taker(eng)
	_set_side(eng, taker, Vector2.ZERO, 9.0)
	var pic := MatchRestarts.picture(eng, 0, taker, taker.pos)
	assert_almost_eq(pic.x, 0.0, 0.001, "players still sprinting counted as ready")

func test_a_better_reader_wants_a_cleaner_picture() -> void:
	var eng := _eng()
	var sharp = _reader(95, 95)
	var blunt = _reader(40, 40)
	var rich: float = MatchRestarts.read(eng, sharp)
	var poor: float = MatchRestarts.read(eng, blunt)
	assert_gt(rich, poor, "reading the picture did not follow the technical profile")
	assert_gt(MatchRestarts.ready_needed(eng, sharp), MatchRestarts.ready_needed(eng, blunt),
		"the better reader did not wait for a cleaner picture")

func test_patience_is_bounded_and_kind_aware() -> void:
	var eng := _eng()
	var taker = _taker(eng)
	var throw_in: float = MatchRestarts.patience(eng, taker, "throw_in", 0)
	var corner: float = MatchRestarts.patience(eng, taker, "corner", 0)
	assert_gt(corner, throw_in, "a corner is held up longer than a throw-in")
	assert_lte(corner, 4.5, "patience ran past the four-and-a-half second bound")
	assert_eq(MatchRestarts.patience(eng, null, "corner", 0), 0.0, "a restart without a taker waited")

func test_the_wait_ends_on_patience_and_on_a_stalled_picture() -> void:
	var eng := _eng()
	var taker = _taker(eng)
	eng.restart["patience"] = 0.9
	assert_true(MatchRestarts.should_wait(eng, eng.restart, 0.2, taker), "a set-poor side was not held up")
	eng.restart["wait"] = 1.2
	assert_false(MatchRestarts.should_wait(eng, eng.restart, 0.2, taker), "patience ran out and play did not resume")
	eng.restart["wait"] = 0.0
	eng.restart["still"] = 1.5
	assert_false(MatchRestarts.should_wait(eng, eng.restart, 0.2, taker),
		"a picture that stopped improving kept the ball waiting")

func test_a_penalty_is_never_held_up() -> void:
	var eng := _eng()
	eng.restart["type"] = "penalty"
	assert_false(MatchRestarts.should_wait(eng, eng.restart, 0.0, _taker(eng)),
		"the spot kick was held up like a throw-in")

func test_a_stalled_picture_stops_counting_up() -> void:
	var restart := {"err": 2.0, "best_ready": 0.4, "still": 0.0}
	MatchRestarts.note_picture(restart, Vector2(0.4, 2.0))
	assert_almost_eq(float(restart["still"]), MatchRestarts.WAIT_STEP, 0.0001,
		"an unchanged picture did not count as stalled")
	MatchRestarts.note_picture(restart, Vector2(0.7, 1.0))
	assert_almost_eq(float(restart["still"]), 0.0, 0.0001, "an improving picture kept counting as stalled")

func test_trailing_side_takes_quick_restarts_late() -> void:
	var eng := _eng()
	eng.half = 2
	eng.clock = 5200.0
	var taker = _taker(eng)
	var early: float = MatchRestarts.patience(eng, taker, "throw_in", 0)
	eng.score[1] = 1
	var chasing: float = MatchRestarts.patience(eng, taker, "throw_in", 0)
	assert_lt(chasing, early, "a side chasing the game did not quicken its restarts")
	eng.clock = 5400.0
	assert_eq(MatchRestarts.patience(eng, taker, "corner", 0), 0.0,
		"the taker held the ball past the end of the half")

func test_a_sent_off_taker_does_not_hold_play_up() -> void:
	var eng := _eng()
	var taker = _taker(eng)
	taker.sent_off = true
	assert_false(MatchRestarts.should_wait(eng, {"patience": 3.0, "wait": 0.0}, 0.1, taker),
		"a sent-off taker held play up")

func test_a_restart_with_no_side_near_it_is_taken() -> void:
	var eng := _eng()
	var taker = _taker(eng)
	for q in eng.players:
		if q.team != 0 or q.sent_off or q.is_gk:
			continue
		q.pos = Vector2(5.0, 5.0)
		q.target = q.pos
	var pic := MatchRestarts.picture(eng, 0, taker, Vector2(100.0, 66.0))
	assert_almost_eq(pic.x, 1.0, 0.001, "a restart nobody is near was still judged unsettled")
	assert_eq(MatchRestarts.read(eng, null), 0.5, "a restart without a taker had no reading")

