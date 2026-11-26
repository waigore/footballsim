extends GdToolsTest

## Attribute mapping: the one table that turns EA FC ratings into simulation
## quantities. Every mapping is asserted at both ends of the scale so a tuning
## change cannot silently invert a curve.
##
## The contact half reads those numbers back on the pitch: a keeper who catches
## and one who parries, a header at goal and one away from it, a tackle that
## wins the ball and a challenge late enough to give away the restart. Mapped
## attributes and the duels they decide are one theme.

class Stub:
	var attr := {}
	var gk := {}
	func _init(a: Dictionary, g: Dictionary = {}) -> void:
		attr = a
		gk = g

func _p(pac: int, sho: int, pas: int, dri: int, def: int, phy: int, height: int = 180) -> Stub:
	return Stub.new({"ovr": 70, "pac": pac, "sho": sho, "pas": pas, "dri": dri,
		"def": def, "phy": phy, "height": height})

func _keeper(div: int, han: int, kic: int, ref: int, spd: int) -> Stub:
	return Stub.new({"ovr": 70, "pac": 50, "sho": 20, "pas": 50, "dri": 40, "def": 20,
		"phy": 60, "height": 190}, {"div": div, "han": han, "kic": kic, "ref": ref, "spd": spd})

func test_pace_drives_speed_and_acceleration() -> void:
	var slow := _p(40, 50, 50, 50, 50, 50)
	var fast := _p(95, 50, 50, 50, 50, 50)
	assert_lt(Attrs.max_speed(slow), Attrs.max_speed(fast), "pace does not raise top speed")
	assert_lt(Attrs.accel(slow), Attrs.accel(fast), "pace does not raise acceleration")
	assert_almost_eq(Attrs.max_speed(fast), 5.0 + pow(0.95, 2.0) * 4.0, 0.001)
	assert_almost_eq(Attrs.accel(fast), 3.0 + 0.95 * 3.4, 0.001)

func test_physicality_drives_deceleration_and_strength() -> void:
	var light := _p(50, 50, 50, 50, 50, 30)
	var heavy := _p(50, 50, 50, 50, 50, 90)
	assert_lt(Attrs.decel(light), Attrs.decel(heavy), "strength does not slow a body down")
	assert_lt(Attrs.strength(light), Attrs.strength(heavy), "physicality does not raise strength")
	assert_almost_eq(Attrs.decel(heavy), 6.5 + 90.0 * 0.02, 0.001)

func test_dribbling_raises_touch_control_and_carry_speed() -> void:
	var clumsy := _p(60, 50, 50, 30, 50, 50)
	var silky := _p(60, 50, 50, 95, 50, 50)
	assert_lt(Attrs.dribble_speed(clumsy), Attrs.dribble_speed(silky), "dribbling does not raise carry speed")
	assert_lt(Attrs.control_radius(clumsy), Attrs.control_radius(silky), "dribbling does not widen control")
	assert_lt(Attrs.first_touch_quality(clumsy), Attrs.first_touch_quality(silky), "dribbling does not improve the first touch")
	assert_gt(Attrs.dribble_speed(silky), 0.0, "carry speed must be positive")

func test_passing_accuracy_and_pace() -> void:
	var poor := _p(50, 50, 30, 50, 50, 50)
	var elite := _p(50, 50, 95, 50, 50, 50)
	assert_gt(Attrs.pass_sigma_deg(poor, 20.0, 0.0), Attrs.pass_sigma_deg(elite, 20.0, 0.0),
		"a weaker passer is not less accurate")
	assert_gt(Attrs.pass_sigma_deg(elite, 40.0, 0.0), Attrs.pass_sigma_deg(elite, 10.0, 0.0),
		"distance does not widen the pass cone")
	assert_gt(Attrs.pass_sigma_deg(elite, 20.0, 0.8), Attrs.pass_sigma_deg(elite, 20.0, 0.0),
		"pressure does not widen the pass cone")
	assert_gt(Attrs.pass_speed_for(elite, 30.0), Attrs.pass_speed_for(elite, 5.0),
		"a longer pass is not hit harder")

func test_shooting_accuracy_and_power() -> void:
	var blunt := _p(50, 30, 50, 50, 50, 50)
	var lethal := _p(50, 95, 50, 50, 50, 50)
	assert_gt(Attrs.shot_sigma_deg(blunt, 18.0, 0.0), Attrs.shot_sigma_deg(lethal, 18.0, 0.0),
		"a weaker shooter is not less accurate")
	assert_gt(Attrs.shot_sigma_deg(lethal, 18.0, 0.7), Attrs.shot_sigma_deg(lethal, 18.0, 0.0),
		"pressure does not widen the shot cone")
	assert_gt(Attrs.shot_speed(lethal), Attrs.shot_speed(blunt), "shooting does not raise shot speed")
	assert_gt(Attrs.shot_speed(lethal, 1.2), Attrs.shot_speed(lethal, 1.0), "power does not raise shot speed")

func test_defending_and_aerial_duels() -> void:
	var weak := _p(50, 50, 50, 50, 20, 40, 170)
	var tower := _p(50, 50, 50, 50, 90, 90, 195)
	assert_lt(Attrs.tackle_skill(weak), Attrs.tackle_skill(tower), "defending does not raise tackle skill")
	assert_lt(Attrs.aerial(weak), Attrs.aerial(tower), "height and strength do not win headers")
	assert_lte(Attrs.aerial(tower), 1.0, "aerial rating must stay in 0..1")
	assert_gte(Attrs.aerial(weak), 0.0, "aerial rating must stay in 0..1")

func test_stamina_drain_follows_effort_and_physicality() -> void:
	var fit := _p(80, 50, 50, 50, 50, 95)
	var tired := _p(80, 50, 50, 50, 50, 30)
	var jog: float = Attrs.stamina_drain(fit, 2.0, 1.0)
	var sprint: float = Attrs.stamina_drain(fit, 9.0, 1.0)
	assert_gt(sprint, jog, "sprinting does not cost more than jogging")
	assert_lt(Attrs.stamina_drain(fit, 9.0, 1.0), Attrs.stamina_drain(tired, 9.0, 1.0),
		"a stronger player drains as fast as a weak one")

func test_keeper_ratings_map_to_reach_reaction_and_hands() -> void:
	var poor := _keeper(30, 30, 40, 30, 60)
	var elite := _keeper(95, 95, 90, 95, 70)
	assert_lt(Attrs.gk_reach(poor), Attrs.gk_reach(elite), "reflexes do not raise reach")
	assert_lt(Attrs.gk_dive_reach(poor), Attrs.gk_dive_reach(elite), "diving does not raise dive reach")
	assert_gt(Attrs.gk_reaction(poor), Attrs.gk_reaction(elite), "a better keeper does not react sooner")
	assert_lt(Attrs.gk_handling(poor), Attrs.gk_handling(elite), "handling does not raise catch chance")
	assert_gte(Attrs.gk_reaction(elite), 0.10, "reaction time must stay positive")

func test_role_helpers_classify_every_line() -> void:
	for role in ["RB", "LB", "CB", "RCB", "LCB", "RWB", "LWB"]:
		assert_true(Attrs.is_defender(role), role + " is not read as a defender")
	for role in ["CDM", "RDM", "LDM", "CM", "RM", "LM", "CAM"]:
		assert_true(Attrs.is_mid(role), role + " is not read as a midfielder")
	for role in ["RW", "LW", "ST", "CF"]:
		assert_true(Attrs.is_forward(role), role + " is not read as a forward")
	for role in ["RB", "LB", "RWB", "LWB", "RW", "LW", "RM", "LM"]:
		assert_true(Attrs.is_wide(role), role + " is not read as a wide player")
	assert_true(Attrs.is_gk("GK"), "GK is not read as a keeper")
	assert_false(Attrs.is_gk("CB"), "a centre-back is read as a keeper")
	assert_false(Attrs.is_forward("CB"), "a centre-back is read as a forward")

func test_role_push_orders_the_attacking_weight() -> void:
	assert_gt(Attrs.role_push("ST"), Attrs.role_push("CAM"), "a striker does not push higher than a 10")
	assert_gt(Attrs.role_push("CAM"), Attrs.role_push("CM"), "a 10 does not push higher than a centre-mid")
	assert_gt(Attrs.role_push("CM"), Attrs.role_push("CB"), "a centre-mid does not push higher than a centre-back")
	assert_almost_eq(Attrs.role_push("ST"), 1.0, 0.001)
	assert_almost_eq(Attrs.role_push("CB"), 0.05, 0.001)
	assert_almost_eq(Attrs.role_push("UNKNOWN"), 0.3, 0.001)

# ------------------------------------------------------------------------


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

func _gk_of(eng, t: int):
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
	var gk = _gk_of(eng, 0)
	_put_on_the_spot(gk, Vector2(0.3, 34.0))
	eng.ball.pos = Vector2(0.0, 34.0)
	eng._check_rules()
	assert_eq(eng.score[1], 0, "a keeper carrying the ball over his line was scored past")

# ------------------------------------------------------------- keepers ------

func test_keeper_catches_and_it_counts_as_a_save() -> void:
	var held := 0
	for seed_in in range(TRIES):
		var eng := _eng(seed_in)
		var gk = _gk_of(eng, 0)
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
		var gk = _gk_of(eng, 0)
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
		var gk = _gk_of(eng, 0)
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

func test_keeper_challenges_a_carrier_still_in_control() -> void:
	# A carrier walking the ball in is a chance the model never priced: the ball
	# leads his feet by half a metre, so a keeper standing on top of him used to
	# watch it cross the line (issue #192). The dive has to read the carrier.
	var smothered := 0
	for seed_in in range(TRIES):
		var eng := _eng(seed_in + 300)
		var gk = _gk_of(eng, 0)
		_put_on_the_spot(gk, eng.own_goal_pos(0) + Vector2(1.0, 0.0))
		var carrier = _outfield(eng, 1)
		_put_on_the_spot(carrier, gk.pos + Vector2(0.8, 0.0))
		eng.ball.owner_id = carrier.id
		eng.ball.pos = carrier.pos
		eng.ball.vel = Vector2.ZERO
		eng.ball.last_touch_team = 1
		carrier.has_ball = true
		eng._ball_interactions(1.0 / 60.0)
		if eng.ball.owner_id == gk.id:
			smothered += 1
	assert_gt(smothered, 0, "a keeper never challenged a carrier in his reach")

func test_a_carried_ball_over_the_line_is_a_goal_once_the_keeper_is_beaten() -> void:
	# The other half of the same rule: a carrier the keeper cannot reach still
	# walks it in, and it is a goal.
	var eng := _eng(77)
	eng.teams[0]["dir"] = 1
	eng.teams[1]["dir"] = -1
	var gk = _gk_of(eng, 0)
	_put_on_the_spot(gk, eng.own_goal_pos(0) + Vector2(4.5, 0.0))
	var carrier = _outfield(eng, 1)
	_put_on_the_spot(carrier, eng.own_goal_pos(0) + Vector2(0.4, 0.0))
	eng.ball.owner_id = carrier.id
	eng.ball.pos = Vector2(0.0, 34.0)
	eng.ball.last_touch_id = carrier.id
	eng.ball.last_touch_team = 1
	eng._check_rules()
	assert_eq(eng.score[1], 1, "a carrier the keeper could not reach did not score")

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
