extends GdToolsTest

## The on-ball half of the brain (MatchAIPlanning): a keeper distributes, a
## carrier decides on a fixed cadence, and each possession choice — shoot,
## long shot, pass, cross, through ball, clear, dribble — can be staged and
## observed. Seeded engines, no UI, live state only.

func _scene(seed_in: int) -> MatchEngine:
	var eng := MatchEngine.new(seed_in)
	eng.phase = "play"
	eng.possession_team = 0
	eng.ball.pos = Vector2(eng.L * 0.5, eng.W * 0.5)
	eng.ball.owner_id = -1
	eng.ball.vel = Vector2.ZERO
	return eng

func _outfield(eng, t: int):
	for p in eng.players:
		if p.team == t and not p.is_gk and not p.sent_off:
			return p
	return null

func _clear_opponents(eng, team: int, keep := -1) -> void:
	# Park the other side on its own byline so a staged decision has no bodies
	# in the lane and no pressure, except the one keeper we keep in goal.
	for q in eng.players:
		if q.team == team or q.id == keep:
			continue
		q.pos = Vector2(eng.L - 2.0, 2.0 + float(q.id % 60))

func test_reset_state_forgets_chains_and_cooldowns() -> void:
	var eng := _scene(61)
	var plan = eng.brain.on_ball
	plan.chain_team = 0
	plan.pass_chain[0] = [1, 2]
	plan.decide_cd[7] = 99.0
	plan.last_shot[0] = 40.0
	plan.reset_state()
	assert_eq(plan.chain_team, -1, "the pass chain team survived a reset")
	assert_eq(plan.pass_chain[0].size(), 0, "the pass chain survived a reset")
	assert_true(plan.decide_cd.is_empty(), "the decision cooldowns survived a reset")
	assert_almost_eq(plan.last_shot[0], -10.0, 0.01, "the shot timer survived a reset")

func test_a_keeper_in_possession_distributes() -> void:
	var eng := _scene(62)
	var gk = eng._gk_of(0)
	assert_not_null(gk, "the fixture has no home keeper")
	eng.ball.owner_id = gk.id
	eng.ball.pos = gk.pos
	eng.brain.on_ball.update(0.016)
	assert_gt(gk.action_t, 0.0, "the keeper did not start a distribution")
	# A short outlet hands the ball on; a clearance leaves it loose. Either
	# way the keeper no longer holds it.
	assert_ne(eng.ball.owner_id, gk.id, "the keeper kept the ball after distributing")
	assert_gt(gk.action_t, 0.4, "the keeper finished the distribution beat early")
	# While a distribution is cooling down it must not fire twice.
	var t: float = gk.action_t
	eng.brain.on_ball.update(0.016)
	assert_almost_eq(gk.action_t, t, 0.001, "the keeper distributed twice in the same beat")

func test_the_carrier_decides_on_a_cooldown() -> void:
	var eng := _scene(63)
	_clear_opponents(eng, 0)
	var p = _outfield(eng, 0)
	eng.ball.owner_id = p.id
	eng.ball.pos = p.pos
	p.pos = Vector2(eng.L * 0.5, eng.W * 0.5)
	p.action_t = 0.0
	eng.brain.on_ball.update(0.016)
	var cd: float = eng.brain.on_ball.decide_cd.get(p.id, 0.0)
	assert_gt(cd, eng.clock, "the first decision did not arm a cooldown")
	eng.brain.on_ball.update(0.016)
	assert_almost_eq(eng.brain.on_ball.decide_cd[p.id], cd, 0.01, "the carrier decided again inside its cooldown")

func _striker(eng):
	for q in eng.players:
		if q.team == 0 and q.role == "ST":
			return q
	return _outfield(eng, 0)

func test_a_carrier_in_the_box_shoots() -> void:
	var eng := _scene(64)
	_clear_opponents(eng, 0)
	var p = _striker(eng)
	p.pos = eng.to_world(0, Vector2(0.90, 0.5))
	p.facing = Vector2(1, 0)
	p.attr["sho"] = 95.0
	p.cooldown = 0.0
	eng.ball.pos = p.pos
	eng.ball.owner_id = p.id
	eng.ball.vel = Vector2.ZERO
	eng.brain.on_ball.reset_state()
	# The scoring bar is strict and the clear-sight arm is a 14% roll, so keep
	# the beat running frame by frame until the finish lands.
	var shot_at := -1.0
	for i in range(240):
		eng.clock += 1.0 / 60.0
		p.action_t = 0.0
		p.cooldown = 0.0
		eng.brain.on_ball.decide(p)
		if eng.brain.on_ball.last_shot[0] > -1.0:
			shot_at = eng.brain.on_ball.last_shot[0]
			break
	assert_gt(shot_at, -1.0, "a striker alone in the box never shot")
	assert_ne(eng.ball.owner_id, p.id, "the striker still owned the ball after shooting")

func test_a_wide_carrier_crosses_or_passes_into_the_box() -> void:
	var eng := _scene(65)
	_clear_opponents(eng, 0)
	var p = _outfield(eng, 0)
	p.pos = eng.to_world(0, Vector2(0.75, 0.12))
	p.attr["dri"] = 1.0
	p.attr["sho"] = 1.0
	var mate = null
	for q in eng.players:
		if q.team == 0 and q.id != p.id and not q.is_gk:
			mate = q
			break
	mate.pos = eng.to_world(0, Vector2(0.92, 0.5))
	eng.ball.pos = p.pos
	eng.ball.owner_id = p.id
	eng.ball.vel = Vector2.ZERO
	eng.brain.on_ball.reset_state()
	eng.brain.on_ball.decide(p)
	assert_ne(eng.ball.owner_id, p.id, "a wide carrier kept the ball instead of playing it in")

## The Live tactics page says `crossing` sets "cross preference and cross
## accuracy". The accuracy half has always been read in `pass_ball`; this pins
## the preference half, which used to be a flat constant, so the lever moves a
## side's on-ball choice and not only the ball's error.
func test_the_crossing_lever_moves_the_choice_to_cross() -> void:
	# The pull is added to every candidate's score, so it decides between a cross
	# and the same ball played short; a lever that never moves it is the bug this
	# pins. Low lever: the cross is worth nothing. High lever: plainly worth more.
	var low: float = MatchAIPlanning.cross_pull({"crossing": 0.0})
	var mid: float = MatchAIPlanning.cross_pull({"crossing": 0.5})
	var high: float = MatchAIPlanning.cross_pull({"crossing": 1.0})
	assert_lt(low, mid, "a side told not to cross still valued the cross as much")
	assert_gt(high, mid, "a side told to cross did not value the cross more")
	assert_gt(high - low, 0.90,
		"the crossing lever's whole range barely moves the cross (%0.2f)" % (high - low))
	# The shipped clubs run 0.48–0.60. At that spread the lever has to be worth
	# something — a preference that cannot separate the league's own sides is not
	# a preference. Measured: this spread decides the close calls in the staged
	# wide-carrier sweep.
	var weakest: float = MatchAIPlanning.cross_pull({"crossing": 0.48})
	var strongest: float = MatchAIPlanning.cross_pull({"crossing": 0.60})
	assert_gt(strongest - weakest, 0.15,
		"the shipped clubs' own crossing spread is worth nothing (%0.2f)" % (strongest - weakest))

## At the league's default lever (0.5) the cross is worth exactly what the flat
## constant used to be, so a default side plays the match it always played.
func test_the_default_crossing_level_keeps_the_old_pull() -> void:
	assert_almost_eq(MatchAIPlanning.cross_pull({"crossing": 0.5}), 0.28, 0.0001,
		"the default crossing level no longer reproduces the shipped cross pull")
	# A style with no lever at all (a bare fixture, a save written before the
	# field existed) reads the default, never zero.
	assert_almost_eq(MatchAIPlanning.cross_pull({}), 0.28, 0.0001,
		"a style without a crossing lever did not fall back to the default")

## The staged wide carrier still plays the ball in, so the lever never strands a
## cross the geometry asks for at a low setting.
func test_a_wide_carrier_still_plays_the_ball_in_at_a_low_lever() -> void:
	var eng := _scene(652)
	_clear_opponents(eng, 0)
	var p = _outfield(eng, 0)
	p.pos = eng.to_world(0, Vector2(0.75, 0.12))
	var mate = null
	for q in eng.players:
		if q.team == 0 and q.id != p.id and not q.is_gk:
			mate = q
			break
	mate.pos = eng.to_world(0, Vector2(0.92, 0.5))
	eng.ball.pos = p.pos
	eng.ball.owner_id = p.id
	eng.ball.vel = Vector2.ZERO
	var style: Dictionary = eng.style_of(0).duplicate()
	style["crossing"] = 0.0
	eng.live_style[0] = style
	eng.brain.on_ball.reset_state()
	var choice: Dictionary = eng.brain.on_ball._best_pass(p, style)
	assert_false((choice["mate"] as Object) == null, "a low lever stranded the wide carrier")

func test_a_crowded_own_box_clears() -> void:
	var eng := _scene(66)
	var p = _outfield(eng, 0)
	p.role = "CD"
	p.pos = eng.to_world(0, Vector2(0.08, 0.5))
	for q in eng.players:
		if q.team == 1 and not q.is_gk:
			q.pos = p.pos + Vector2(1.2, 0.4 * float(q.id % 3))
	eng.ball.pos = p.pos
	eng.ball.owner_id = p.id
	eng.ball.vel = Vector2.ZERO
	eng.brain.on_ball.reset_state()
	eng.brain.on_ball.decide(p)
	assert_ne(p.state, "dribble", "a defender surrounded in his own box dribbled")

func test_the_urgency_rises_while_the_ball_is_stuck() -> void:
	var eng := _scene(67)
	eng.ball.pos = Vector2(eng.L * 0.5, eng.W * 0.5)
	var plan = eng.brain.on_ball
	plan.reset_state()
	assert_almost_eq(plan._urgency(0), 0.0, 0.001, "a fresh clock claims urgency")
	assert_almost_eq(plan._urgency(0), 0.0, 0.001, "the first look should only record the band")
	eng.clock += 20.0
	assert_gt(plan._urgency(0), 0.5, "a ball stuck in one band never grew urgent")
	eng.ball.pos = eng.to_world(0, Vector2(0.95, 0.5))
	assert_almost_eq(plan._urgency(0), 0.0, 0.001, "progress did not clear the urgency")

func test_dribble_steers_away_from_the_nearest_defender() -> void:
	var eng := _scene(68)
	var p = _outfield(eng, 0)
	p.pos = Vector2(eng.L * 0.5, eng.W * 0.5)
	var q = _outfield(eng, 1)
	q.pos = p.pos + Vector2(3.0, 0.0)
	eng.ball.pos = p.pos
	eng.ball.owner_id = p.id
	eng.brain.on_ball._dribble(p, eng.target_goal_pos(0), 0.0)
	assert_eq(p.state, "dribble", "the carrier did not enter a dribble")
	var dirv: Vector2 = (p.target - p.pos).normalized()
	assert_lt(dirv.angle_to(Vector2.RIGHT), 0.5, "the carrier dribbled straight into the defender")
