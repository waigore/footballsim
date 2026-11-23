extends GdToolsTest

## Duels and handling: a keeper who catches and one who parries, a header at
## goal and a header away from it, a tackle that wins the ball and a challenge
## late enough to give away the restart. Engine-level, seeded, no UI.

const TRIES := 40

func _eng(seed_in: int = 21) -> MatchEngine:
	var eng := MatchEngine.new(seed_in)
	eng.phase = "play"
	eng.restart = {}
	eng.ball.owner_id = -1
	return eng

func _outfield(eng, t: int):
	for p in eng.players:
		if p.team == t and not p.is_gk:
			return p
	return null

func _keeper(eng, t: int):
	return eng._gk_of(t)

func _events(eng, kind: String) -> int:
	var n := 0
	for e in eng.events:
		if str(e.get("type", "")) == kind:
			n += 1
	return n

func _put_on_the_spot(p, pos: Vector2) -> void:
	p.pos = pos
	p.target = pos
	p.vel = Vector2.ZERO
	p.cooldown = 0.0

# ------------------------------------------------------------ first touch ---

func test_loose_ball_at_his_feet_is_taken_cleanly() -> void:
	var eng := _eng()
	var p = _outfield(eng, 0)
	_put_on_the_spot(p, Vector2(60.0, 34.0))
	eng.ball.pos = p.pos
	eng.ball.vel = Vector2(4.0, 0.0)
	eng._try_control(p, 0.4)
	assert_true(p.has_ball, "a slow ball at his feet was not brought under control")
	assert_eq(eng.ball.owner_id, p.id, "the ball was not claimed by the nearest player")

func test_heavy_touch_lets_the_ball_squirt_away() -> void:
	var eng := _eng(3)
	var p = _outfield(eng, 0)
	_put_on_the_spot(p, Vector2(40.0, 34.0))
	eng.ball.z = 0.3
	var miscontrols := 0
	for i in range(TRIES):
		eng.ball.owner_id = -1
		eng.ball.pos = p.pos
		eng.ball.vel = Vector2(26.0, 0.0)
		p.cooldown = 0.0
		p.has_ball = false
		eng._try_control(p, 0.3)
		if eng.ball.owner_id < 0:
			miscontrols += 1
			assert_eq(eng.ball.last_touch_id, p.id, "a heavy touch did not count as the last touch")
			assert_gt(p.cooldown, 0.0, "a miscontrol did not cost the player a beat")
	assert_gt(miscontrols, 0, "a ball arriving at speed was never miscontrolled")

func test_carrying_over_the_line_is_no_touch_by_the_keeper() -> void:
	# A keeper holding the ball on his own line keeps it in play.
	var eng := _eng(5)
	var gk = _keeper(eng, 0)
	_put_on_the_spot(gk, Vector2(0.3, 34.0))
	eng.ball.pos = Vector2(0.0, 34.0)
	eng._check_rules()
	assert_eq(eng.score[1], 0, "a keeper carrying the ball over his line was scored past")

# ------------------------------------------------------------- keepers ------

func test_keeper_catches_and_it_counts_as_a_save() -> void:
	var held := 0
	for seed_in in range(TRIES):
		var eng := _eng(seed_in)
		var gk = _keeper(eng, 0)
		_put_on_the_spot(gk, eng.own_goal_pos(0))
		eng.ball.pos = gk.pos + Vector2(0.6, 0.0)
		eng.ball.vel = Vector2(16.0, 0.0)
		eng.ball.shot_team = 1
		eng.ball.shot_time = eng.clock
		eng.ball.shot_xg = 0.4
		eng.ball.shot_saved = false
		eng._gk_claim(gk, 0.4)
		if eng.ball.owner_id == gk.id:
			held += 1
			assert_gte(int(eng.stats[0]["saves"]), 1, "a held shot was not counted as a save")
			assert_true(eng.ball.shot_saved, "a held shot did not close the shot")
			assert_gte(_events(eng, "save"), 1, "a save produced no commentary")
			assert_eq(eng.ball.shot_team, -1, "a held ball kept its shooter")
	assert_gt(held, 0, "the keeper never caught a shot aimed at him")

func test_keeper_parry_pushes_the_ball_wide_and_stays_loose() -> void:
	var parried := 0
	for seed_in in range(TRIES):
		var eng := _eng(seed_in + 100)
		var gk = _keeper(eng, 0)
		_put_on_the_spot(gk, eng.own_goal_pos(0))
		eng.ball.pos = gk.pos + Vector2(0.6, 0.0)
		eng.ball.vel = Vector2(20.0, 0.0)
		eng.ball.shot_team = 1
		eng.ball.shot_time = eng.clock
		eng.ball.shot_xg = 0.3
		eng.ball.shot_saved = false
		eng._gk_claim(gk, 0.4)
		if eng.ball.owner_id < 0:
			parried += 1
			assert_gt(eng.ball.vel.length(), 0.0, "a parried ball stopped dead")
			assert_eq(eng.ball.shot_team, -1, "a parried ball kept its shooter")
			assert_eq(gk.stats["saves"], 1, "a parry was not counted as a save")
	assert_gt(parried, 0, "the keeper never parried a shot")

func test_keeper_smothers_a_carrier_who_broke_through() -> void:
	# The smother only happens on a ball nobody controls any more: the last
	# defender has just poked it away from the carrier.
	var smothered := 0
	for seed_in in range(TRIES):
		var eng := _eng(seed_in + 200)
		var gk = _keeper(eng, 0)
		_put_on_the_spot(gk, eng.own_goal_pos(0))
		var carrier = _outfield(eng, 1)
		_put_on_the_spot(carrier, gk.pos + Vector2(1.0, 0.0))
		eng.ball.owner_id = -1
		eng.ball.pos = carrier.pos
		eng.ball.vel = Vector2.ZERO
		eng.ball.last_touch_team = 1
		eng._ball_interactions(1.0 / 60.0)
		if eng.ball.owner_id == gk.id:
			smothered += 1
			assert_true(gk.has_ball, "the keeper smothered the ball but did not hold it")
	assert_gt(smothered, 0, "a keeper never came out to smother a loose ball at a striker's feet")

# -------------------------------------------------------------- headers -----

func test_header_at_goal_is_a_shot() -> void:
	var eng := _eng(7)
	var p = _outfield(eng, 0)
	var goal: Vector2 = eng.target_goal_pos(0)
	_put_on_the_spot(p, Vector2(goal.x - 9.0, 34.0))
	eng.ball.pos = p.pos
	eng.ball.z = 1.8
	eng.ball.last_touch_team = 0
	eng.possession_team = 0
	var shots: int = int(eng.stats[0]["shots"])
	eng._header(p)
	assert_eq(int(eng.stats[0]["shots"]), shots + 1, "a header at goal was not recorded as a shot")
	assert_gt(float(eng.stats[0]["xg"]), 0.0, "a header at goal earned no xG")
	assert_gt(p.jump_t, 0.0, "the header did not lift the player off the ground")
	assert_gte(_events(eng, "header"), 1, "a header produced no commentary")

func test_header_away_from_goal_cushions_to_a_teammate() -> void:
	var eng := _eng(8)
	var p = _outfield(eng, 0)
	_put_on_the_spot(p, Vector2(52.0, 34.0))
	eng.ball.pos = p.pos
	eng.ball.z = 1.6
	eng.ball.last_touch_team = 0
	eng.possession_team = 0
	var shots: int = int(eng.stats[0]["shots"])
	eng._header(p)
	assert_eq(int(eng.stats[0]["shots"]), shots, "a midfield header was counted as a shot")
	assert_gt(eng.ball.vel.length(), 0.0, "a cushioned header left the ball dead")
	assert_eq(eng.ball.last_touch_team, 0, "the header did not register as a touch")

func test_defensive_header_clears_the_ball() -> void:
	var eng := _eng(9)
	var p = _outfield(eng, 0)
	_put_on_the_spot(p, Vector2(20.0, 34.0))
	eng.ball.pos = p.pos
	eng.ball.z = 1.7
	eng.ball.last_touch_team = 1
	eng.possession_team = 1
	eng._header(p)
	assert_gte(_events(eng, "clearance"), 1, "a defender's header was not read as a clearance")
	assert_gte(eng.ball.vz, 0.0, "a defensive header did not get the ball up and away")

func test_high_ball_is_won_by_the_better_header() -> void:
	var eng := _eng(10)
	var tall = _outfield(eng, 0)
	var small = _outfield(eng, 1)
	tall.attr["height"] = 195
	tall.attr["phy"] = 92
	small.attr["height"] = 168
	small.attr["phy"] = 40
	_put_on_the_spot(tall, Vector2(50.0, 34.0))
	_put_on_the_spot(small, Vector2(50.4, 34.0))
	eng.ball.pos = Vector2(50.2, 34.0)
	eng.ball.z = 1.8
	eng.ball.vz = 0.5
	eng.ball.owner_id = -1
	eng._ball_interactions(1.0 / 60.0)
	assert_eq(eng.ball.last_touch_id, tall.id, "the smaller player won a header against a giant")

# --------------------------------------------------------------- duels ------

func test_tackle_won_turns_the_ball_over() -> void:
	var won := 0
	for seed_in in range(TRIES):
		var eng := _eng(seed_in + 300)
		var carrier = _outfield(eng, 0)
		var d = _outfield(eng, 1)
		carrier.attr["dri"] = 30
		d.attr["def"] = 95
		_put_on_the_spot(carrier, Vector2(70.0, 34.0))
		_put_on_the_spot(d, Vector2(71.0, 34.0))
		d.facing = Vector2.LEFT
		carrier.has_ball = true
		eng.ball.owner_id = carrier.id
		eng.ball.pos = carrier.pos
		eng._attempt_tackle(d, carrier)
		if int(d.stats["tackles"]) > 0:
			won += 1
			assert_lt(eng.ball.owner_id, 0, "the tackled carrier kept the ball")
			assert_eq(eng.ball.last_touch_id, d.id, "the tackle did not register a touch")
			assert_eq(eng.possession_team, 1, "winning the ball did not turn possession over")
			assert_false(carrier.has_ball, "the carrier still thinks he has the ball")
	assert_gt(won, 0, "a strong defender never won a tackle against a weak carrier")

func test_late_challenge_inside_the_box_is_a_penalty() -> void:
	var eng := _eng(11)
	var carrier = _outfield(eng, 0)
	var d = _outfield(eng, 1)
	# The defender defends his own box: the victim is fouled there.
	var their_goal: Vector2 = eng.own_goal_pos(1)
	_put_on_the_spot(carrier, their_goal + Vector2(6.0, 0.0))
	_put_on_the_spot(d, carrier.pos + Vector2(0.8, 0.0))
	eng.possession_team = 0
	assert_true(eng.in_penalty_box(carrier.pos, 1), "fixture did not place the foul in the box")
	eng._award_foul(d, carrier)
	assert_eq(str(eng.restart["type"]), "penalty", "a foul in the box did not give a penalty")
	assert_eq(int(eng.restart["team"]), 0, "the penalty went to the wrong side")
	assert_gte(int(eng.stats[1]["fouls"]), 1, "the foul was not recorded against the defender")

func test_late_challenge_outside_the_box_is_a_free_kick() -> void:
	var eng := _eng(12)
	var carrier = _outfield(eng, 0)
	var d = _outfield(eng, 1)
	_put_on_the_spot(carrier, Vector2(60.0, 34.0))
	_put_on_the_spot(d, carrier.pos + Vector2(0.8, 0.0))
	eng.possession_team = 0
	eng._award_foul(d, carrier)
	assert_eq(str(eng.restart["type"]), "free_kick", "a foul outside the box did not give a free kick")
	assert_eq(int(eng.restart["team"]), 0, "the free kick went to the wrong side")

func test_second_bookable_challenge_sends_a_player_off() -> void:
	var eng := _eng(13)
	var p = _outfield(eng, 0)
	eng._send_off_or_book(p, "yellow")
	assert_false(p.sent_off, "a first yellow card sent the player off")
	assert_false(p.red, "a yellow card was recorded as a red")
	assert_gte(_events(eng, "card"), 1, "a yellow card produced no call")
	eng._send_off_or_book(p, "red_second")
	assert_true(p.sent_off, "a second yellow did not send the player off")
	assert_true(p.red, "a second yellow was not recorded as a red")
	assert_eq(int(eng.stats[0]["red"]), 1, "the sending off was not recorded in the match stats")
	assert_eq(p.vel, Vector2.ZERO, "a sent-off player kept moving")

func test_awarding_fouls_books_someone() -> void:
	# Cards come out of the foul roll; over a run of fouls the book has to open.
	var eng := _eng(16)
	var carrier = _outfield(eng, 0)
	var d = _outfield(eng, 1)
	_put_on_the_spot(carrier, Vector2(60.0, 34.0))
	_put_on_the_spot(d, carrier.pos + Vector2(0.8, 0.0))
	for i in range(80):
		eng.phase = "play"
		eng._award_foul(d, carrier)
	assert_gte(_events(eng, "card"), 1, "eighty fouls produced no card at all")
	assert_gte(int(eng.stats[1]["fouls"]), 80, "fouls were not counted")

func test_straight_red_removes_the_body() -> void:
	var eng := _eng(14)
	var p = _outfield(eng, 1)
	eng.ball.owner_id = p.id
	eng.ball.last_touch_id = p.id
	p.has_ball = true
	eng._send_off_or_book(p, "red")
	assert_true(p.sent_off, "a straight red did not send the player off")
	assert_true(p.red, "a straight red was not recorded as a red")
	assert_false(p.has_ball, "a sent-off player still had the ball")
	assert_lt(eng.ball.owner_id, 0, "the sent-off player kept the ball")

func test_shot_into_the_lane_can_be_blocked() -> void:
	var blocked := 0
	for seed_in in range(TRIES):
		var eng := _eng(seed_in + 400)
		var shooter = _outfield(eng, 0)
		var blocker = _outfield(eng, 1)
		_put_on_the_spot(shooter, Vector2(80.0, 34.0))
		_put_on_the_spot(blocker, Vector2(84.0, 34.0))
		eng.ball.pos = blocker.pos - Vector2(0.5, 0.0)
		eng.ball.vel = Vector2(24.0, 0.0)
		eng.ball.z = 0.4
		eng.ball.owner_id = -1
		eng.ball.shot_team = 0
		eng.ball.shot_time = eng.clock
		eng.ball.last_touch_id = shooter.id
		eng.ball.last_touch_team = 0
		eng._ball_interactions(1.0 / 60.0)
		if _events(eng, "block") > 0:
			blocked += 1
			assert_eq(eng.ball.last_touch_team, 1, "the block did not register the defender's touch")
			assert_eq(eng.ball.shot_team, -1, "a blocked shot stayed a shot")
	assert_gt(blocked, 0, "a defender in the shot lane never blocked the ball")

func test_loose_ball_in_a_crowd_squirts_clear() -> void:
	var eng := _eng(15)
	var spot := Vector2(52.0, 34.0)
	var bunch := []
	for p in eng.players:
		if bunch.size() == 4:
			break
		_put_on_the_spot(p, spot + Vector2(0.25 * bunch.size(), 0.1 * bunch.size()))
		p.cooldown = 1.0
		bunch.append(p)
	assert_eq(bunch.size(), 4, "fixture did not gather a crowd")
	for q in eng.players:
		q.cooldown = 1.0
	eng.ball.owner_id = -1
	eng.ball.pos = spot
	eng.ball.vel = Vector2(0.5, 0.0)
	eng.ball.z = 0.0
	eng.ball.loose_t = 1.5
	eng._ball_interactions(1.0 / 60.0)
	assert_gt(eng.ball.vel.length(), 1.0, "a ball stuck in a crowd never squirted clear")
	assert_gt(eng.ball.vz, 0.0, "the escaped ball did not leave the ground")
