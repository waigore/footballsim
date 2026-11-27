extends GdToolsTest


func _eng(seed_in: int = 31) -> MatchEngine:
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

func _events(eng, kind: String) -> int:
	var n := 0
	for e in eng.events:
		if str(e.get("type", "")) == kind:
			n += 1
	return n

func _park_keepers_off_the_line(eng) -> void:
	for p in eng.players:
		if p.is_gk:
			p.pos = Vector2(52.5, 34.0)
			p.cooldown = 0.0


func test_ball_over_the_line_between_the_posts_is_a_goal() -> void:
	var eng := _eng(41)
	_park_keepers_off_the_line(eng)
	var scorer = _outfield(eng, 0)
	eng.ball.pos = Vector2(eng.L, 34.0)
	eng.ball.z = 0.4
	eng.ball.vz = 0.0
	eng.ball.shot_team = 0
	eng.ball.shot_time = eng.clock
	eng.ball.last_touch_id = scorer.id
	eng.ball.last_touch_team = 0
	eng.ball.planned_goal = true
	eng._check_rules()
	assert_eq(eng.score[0], 1, "a ball over the line between the posts was not a goal")
	assert_eq(eng.phase, "goal", "the goal did not stop play")
	assert_eq(int(scorer.stats["goals"]), 1, "the scorer was not credited with the goal")
	assert_gte(_events(eng, "goal"), 1, "the goal produced no commentary")
	assert_eq(str(eng.last_goal["scorer"]), scorer.name, "the goal was credited to the wrong player")

func test_ball_over_the_line_outside_the_posts_earns_a_restart() -> void:
	var eng := _eng(42)
	_park_keepers_off_the_line(eng)
	eng.ball.pos = Vector2(eng.L, 5.0)
	eng.ball.z = 0.4
	eng.ball.last_touch_team = 0
	eng.ball.last_touch_id = -1
	var before: int = eng.score[0] + eng.score[1]
	eng._check_rules()
	assert_eq(eng.score[0] + eng.score[1], before, "a ball wide of the posts was given as a goal")
	assert_eq(eng.phase, "restart", "a ball out of play did not stop play")
	assert_eq(str(eng.restart["type"]), "goal_kick", "a shot wide of the posts did not earn a goal kick")
	assert_eq(int(eng.restart["team"]), 1, "the goal kick went to the wrong side")

func test_last_touch_by_the_defender_earns_a_corner() -> void:
	var eng := _eng(43)
	_park_keepers_off_the_line(eng)
	var defender = _outfield(eng, 1)
	eng.ball.pos = Vector2(eng.L, 60.0)
	eng.ball.z = 0.4
	eng.ball.last_touch_team = 1
	eng.ball.last_touch_id = defender.id
	eng._check_rules()
	assert_eq(str(eng.restart["type"]), "corner", "a defender's last touch over his own line is not a corner")
	assert_eq(int(eng.restart["team"]), 0, "the corner went to the wrong side")
	assert_gte(int(eng.stats[0]["corners"]), 1, "the corner was not counted")

func test_carrying_the_ball_over_the_line_scores_a_walk_in() -> void:
	var eng := _eng(44)
	_park_keepers_off_the_line(eng)
	var carrier = _outfield(eng, 0)
	carrier.pos = Vector2(eng.L, 34.0)
	eng.ball.owner_id = carrier.id
	eng.ball.pos = carrier.pos
	eng.ball.last_touch_id = carrier.id
	eng.ball.last_touch_team = 0
	eng.ball.z = 0.2
	var shots: int = int(eng.stats[0]["shots"])
	eng._check_rules()
	assert_eq(eng.score[0], 1, "a walked-in ball was not given")
	assert_eq(int(eng.stats[0]["shots"]), shots + 1, "the walk-in was not recorded as a shot")
	assert_gte(float(eng.stats[0]["xg"]), 0.85, "the walk-in carried no expected goal")

func test_defender_putting_it_in_his_own_net_is_an_own_goal() -> void:
	var eng := _eng(45)
	_park_keepers_off_the_line(eng)
	var defender = _outfield(eng, 1)
	eng.ball.pos = Vector2(eng.L, 34.0)
	eng.ball.z = 0.3
	eng.ball.last_touch_id = defender.id
	eng.ball.last_touch_team = 1
	eng._check_rules()
	assert_eq(eng.score[0], 1, "an own goal did not go to the other side")
	assert_true(bool(eng.last_goal["own_goal"]), "the own goal was credited as a normal goal")
	assert_eq(int(eng.stats[1]["goals"]), 0, "the conceding side was credited with the goal")


func _goal_for(eng, team: int) -> void:
	_park_keepers_off_the_line(eng)
	eng.phase = "play"
	eng.restart = {}
	var scorer = _outfield(eng, team)
	var goal: Vector2 = eng.target_goal_pos(team)
	eng.ball.pos = Vector2(goal.x, 34.0)
	eng.ball.vel = Vector2.ZERO
	eng.ball.z = 0.4
	eng.ball.vz = 0.0
	eng.ball.owner_id = -1
	eng.ball.shot_team = team
	eng.ball.shot_time = eng.clock
	eng.ball.last_touch_id = scorer.id
	eng.ball.last_touch_team = team
	eng.ball.planned_goal = true
	eng._check_rules()

func test_the_whistle_sheet_lists_every_goal_in_order() -> void:
	var eng := _eng(70)
	eng.clock = 660.0
	_goal_for(eng, 0)
	assert_eq(eng.goal_sheet.size(), 1, "the goal never reached the whistle sheet")
	assert_eq(int(eng.goal_sheet[0]["team"]), 0, "the first goal went to the wrong side")
	assert_eq(int(eng.goal_sheet[0]["minute"]), 11, "the first goal's minute was not read")
	eng.clock = 2400.0
	_goal_for(eng, 1)
	assert_eq(eng.goal_sheet.size(), 2, "the sheet did not keep both goals")
	assert_eq(int(eng.goal_sheet[0]["team"]), 0, "the sheet reordered the goals")
	assert_eq(int(eng.goal_sheet[1]["team"]), 1, "the second goal went to the wrong side")
	assert_eq(int(eng.goal_sheet[1]["minute"]), 40, "the second goal's minute was not read")

func test_an_own_goal_lands_in_the_other_side_of_the_sheet() -> void:
	var eng := _eng(71)
	_park_keepers_off_the_line(eng)
	var defender = _outfield(eng, 1)
	var goal: Vector2 = eng.target_goal_pos(0)
	eng.ball.pos = Vector2(goal.x, 34.0)
	eng.ball.vel = Vector2.ZERO
	eng.ball.z = 0.3
	eng.ball.owner_id = -1
	eng.ball.last_touch_id = defender.id
	eng.ball.last_touch_team = 1
	eng._check_rules()
	assert_eq(eng.goal_sheet.size(), 1, "the own goal never reached the whistle sheet")
	assert_eq(int(eng.goal_sheet[0]["team"]), 0, "the own goal was credited to the wrong side")
	assert_true(bool(eng.goal_sheet[0]["own_goal"]), "the sheet dropped the own-goal mark")
	assert_eq(str(eng.goal_sheet[0]["scorer"]), defender.name, "the sheet named the wrong player")

func test_the_whistle_sheet_survives_a_snapshot() -> void:
	var eng := _eng(72)
	eng.clock = 900.0
	_goal_for(eng, 0)
	var other := MatchEngine.new(72)
	other.from_dict(eng.to_dict())
	assert_eq(other.goal_sheet.size(), 1, "the snapshot lost the goal sheet")
	assert_eq(str(other.goal_sheet[0]["scorer"]), str(eng.goal_sheet[0]["scorer"]), "the snapshot renamed the scorer")
	assert_eq(int(other.goal_sheet[0]["minute"]), 15, "the snapshot lost the goal's minute")

func test_a_goal_with_no_last_touch_is_still_on_the_sheet() -> void:


	var eng := _eng(73)
	_park_keepers_off_the_line(eng)
	var goal: Vector2 = eng.target_goal_pos(0)
	eng.ball.pos = Vector2(goal.x, 34.0)
	eng.ball.vel = Vector2.ZERO
	eng.ball.z = 0.4
	eng.ball.owner_id = -1
	eng.ball.last_touch_id = -1
	eng.ball.last_touch_team = 0
	eng._check_rules()
	assert_eq(eng.goal_sheet.size(), 1, "an unattributed goal never reached the sheet")
	assert_eq(str(eng.goal_sheet[0]["scorer"]), "Unknown", "the sheet invented a scorer")

func test_goal_line_save_keeps_the_ball_out() -> void:
	var saved := 0
	for seed_in in range(30):
		var eng := _eng(seed_in + 500)
		var gk = eng._gk_of(0)
		gk.pos = Vector2(0.4, 34.0)
		gk.cooldown = 0.0
		eng.ball.pos = Vector2(0.0, 34.0)
		eng.ball.vel = Vector2(-14.0, 0.0)
		eng.ball.z = 0.4
		eng.ball.shot_team = 1
		eng.ball.shot_time = eng.clock
		eng.ball.shot_xg = 0.3
		eng.ball.shot_saved = false
		eng.ball.planned_goal = false
		eng._check_rules()
		if _events(eng, "save") > 0:
			saved += 1
			assert_eq(eng.score[1], 0, "a saved ball on the line was still given")
			assert_eq(int(eng.stats[0]["saves"]), 1, "the goal-line save was not counted")
	assert_gt(saved, 0, "the keeper never got a ball on his own line")


func test_ball_over_the_touchline_is_a_throw_in_for_the_other_side() -> void:
	var eng := _eng(46)
	eng.ball.pos = Vector2(60.0, -0.5)
	eng.ball.z = 0.1
	eng.ball.last_touch_team = 0
	eng._check_rules()
	assert_eq(str(eng.restart["type"]), "throw_in", "a ball over the touchline is not a throw-in")
	assert_eq(int(eng.restart["team"]), 1, "the throw-in went to the wrong side")
	assert_eq((eng.restart["pos"] as Vector2).y, 0.0, "the throw was not taken from the touchline")

func test_ball_straight_into_touch_from_nobody_is_a_throw_for_the_home_side() -> void:
	var eng := _eng(47)
	eng.ball.pos = Vector2(30.0, eng.W + 0.5)
	eng.ball.last_touch_team = -1
	eng._check_rules()
	assert_eq(str(eng.restart["type"]), "throw_in", "an untouched ball out of play is not a throw-in")
	assert_eq(int(eng.restart["team"]), 0, "the throw-in went to the wrong side")


func test_runner_beyond_the_last_defender_is_flagged_at_the_pass() -> void:
	var eng := _eng(48)
	var passer = _outfield(eng, 0)
	var runner = _outfield(eng, 0)
	while runner != null and runner.id == passer.id:
		runner = null
	for p in eng.players:
		if p.team == 0 and p.id != passer.id and not p.is_gk:
			runner = p
			break
	passer.pos = Vector2(60.0, 34.0)
	runner.pos = Vector2(100.0, 34.0)
	eng.ball.pos = passer.pos
	for p in eng.players:
		if p.team == 1:
			p.pos = Vector2(70.0 + float(p.id % 5), 30.0 + float(p.id % 7))
	assert_true(eng.would_be_offside(runner), "a runner beyond the last defender is not read as offside")
	eng._mark_offside_at_pass(passer)
	assert_true(runner.offside_flag, "the runner was not flagged at the pass")
	assert_eq(runner.run_until, 0.0, "a flagged runner kept chasing the pass")

func test_flagged_runner_losing_the_ball_gives_a_free_kick() -> void:
	var eng := _eng(49)
	var runner = _outfield(eng, 0)
	runner.offside_flag = true
	runner.pos = Vector2(90.0, 34.0)
	eng.ball.pos = runner.pos
	eng.ball.vel = Vector2(2.0, 0.0)
	eng._try_control(runner, 0.4)
	assert_eq(str(eng.restart["type"]), "free_kick", "an offside runner was not punished with a free kick")
	assert_eq(int(eng.restart["team"]), 1, "the offside free kick went to the wrong side")
	assert_eq(int(eng.stats[0]["offsides"]), 1, "the offside was not counted")
	assert_gte(_events(eng, "offside"), 1, "the offside produced no call")
	assert_false(runner.offside_flag, "the flag survived the whistle")

func test_a_touch_clears_the_offside_stage() -> void:
	var eng := _eng(50)
	var p = _outfield(eng, 0)
	var mate = _outfield(eng, 1)
	mate.offside_flag = true
	p.pos = Vector2(50.0, 34.0)
	eng.ball.pos = p.pos
	eng.ball.vel = Vector2.ZERO
	eng._try_control(p, 0.3)
	assert_false(mate.offside_flag, "a touch did not reset the offside stage")


func test_throw_in_is_taken_and_play_resumes() -> void:
	var eng := _eng(51)
	eng._start_restart("throw_in", 0, Vector2(60.0, 0.0))
	assert_eq(eng.phase, "restart", "the throw-in did not stop play")
	eng._execute_restart()
	assert_eq(eng.phase, "play", "the throw-in did not restart play")
	assert_eq(eng.ball.last_touch_team, 0, "the throw-in was taken by the wrong side")

func test_goal_kick_gets_the_ball_away() -> void:
	var eng := _eng(52)
	eng._start_restart("goal_kick", 0, Vector2(0.5, 34.0))
	assert_almost_eq((eng.restart["pos"] as Vector2).x, 5.5, 0.01)
	eng._execute_restart()
	assert_eq(eng.phase, "play", "the goal kick did not restart play")
	assert_gt(eng.ball.vel.length(), 0.0, "the goal kick left the ball on the spot")

func test_corner_is_crossed_into_the_box() -> void:
	var eng := _eng(53)
	eng._start_restart("corner", 0, Vector2(eng.L, 0.0))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "the corner did not restart play")
	assert_gte(int(eng.stats[0]["crosses"]), 1, "the corner was not recorded as a cross")

func test_penalty_is_struck_at_goal() -> void:
	var eng := _eng(54)
	var shots: int = int(eng.stats[0]["shots"])
	eng._start_restart("penalty", 0, Vector2(eng.L - 11.0, 34.0))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "the penalty did not restart play")
	assert_gte(int(eng.stats[0]["shots"]), shots + 1, "the penalty was not recorded as a shot")
	assert_gte(float(eng.stats[0]["xg"]), 0.76, "the penalty carried no expected goal")
	assert_gte(_events(eng, "penalty_taken"), 1, "the penalty produced no call")

func test_free_kick_from_range_is_struck_at_goal() -> void:
	var eng := _eng(55)
	eng._start_restart("free_kick", 0, Vector2(eng.L - 20.0, 34.0))
	var shots: int = int(eng.stats[0]["shots"])
	eng._execute_restart()
	assert_eq(eng.phase, "play", "the free kick did not restart play")
	assert_gte(int(eng.stats[0]["shots"]), shots, "the free kick lost its shot count")

func test_opponents_are_pushed_off_the_free_kick() -> void:
	var eng := _eng(56)
	var spot := Vector2(70.0, 34.0)
	for p in eng.players:
		if p.team == 1:
			p.pos = spot + Vector2(1.0, 0.5)
	eng._start_restart("free_kick", 0, spot)
	for p in eng.players:
		if p.team == 1 and not p.sent_off:
			assert_gte(p.pos.distance_to(spot), 9.0, "an opponent stood inside the free-kick wall distance")


func test_possession_clock_follows_the_side_in_control() -> void:
	var eng := _eng(57)
	var p = _outfield(eng, 0)
	eng.ball.owner_id = p.id
	var before: float = float(eng.stats[0]["possession"])
	eng._update_possession(0.5)
	assert_almost_eq(float(eng.stats[0]["possession"]), before + 0.5, 0.001, "the home side was not credited possession")
	assert_false(eng.possession_loose, "controlled possession was read as loose")

func test_loose_ball_still_credits_the_side_that_touched_it_last() -> void:
	var eng := _eng(58)
	eng.ball.owner_id = -1
	eng.ball.vel = Vector2(2.0, 0.0)
	eng.ball.last_touch_team = 1
	var before: float = float(eng.stats[1]["possession"])
	eng._update_possession(0.5)
	assert_almost_eq(float(eng.stats[1]["possession"]), before + 0.5, 0.001, "a loose ball credited nobody")
	assert_true(eng.possession_loose, "a loose ball was read as controlled")


func test_side_without_a_keeper_brings_one_on() -> void:
	var eng := _eng(59)
	var gk = eng._gk_of(0)
	eng._send_off_or_book(gk, "red")
	assert_null(eng._gk_of(0), "the keeper did not leave the pitch")
	var left: int = int(eng.teams[0]["subs_left"])
	eng._tick_substitutions()
	assert_not_null(eng._gk_of(0), "an outfield side was left without a keeper")
	assert_eq(int(eng.teams[0]["subs_left"]), left - 1, "the emergency keeper did not cost a change")

func test_injured_player_with_no_changes_left_is_lost() -> void:
	var eng := _eng(60)
	var p = _outfield(eng, 0)
	eng.teams[0]["subs_left"] = 0
	eng._injure(p)
	assert_true(p.sent_off, "an injured player with no change left stayed on")
	assert_eq(int(eng.stats[0]["injuries"]), 1, "the injury was not counted")
	assert_true(eng.players.has(p), "the injured player was dropped from the squad list")

func test_the_most_tired_outfield_player_is_the_one_changed() -> void:
	var eng := _eng(61)
	var tired = _outfield(eng, 0)
	for q in eng.players:
		if q.team == 0 and not q.is_gk:
			q.stamina = 0.9
	tired.stamina = 0.3
	var pick = eng._most_tired_outfield(0)
	assert_eq(pick.id, tired.id, "the freshest player was picked to come off")
	assert_null(eng._most_tired_outfield(5), "an empty side still produced a player")

func test_bench_keeper_is_only_used_for_the_gloves() -> void:
	var eng := _eng(62)
	var bench: Dictionary = eng._bench_keeper(0)
	assert_false(bench.is_empty(), "no keeper on the bench")
	assert_eq(str(bench["role"]), "GK", "the emergency keeper is not a keeper")
	var chosen: Dictionary = eng._pick_bench(0, "GK", true)
	assert_false(chosen.is_empty(), "no keeper was offered for the gloves")
	var outfield_pick: Dictionary = eng._pick_bench(0, "ST", false)
	assert_false(outfield_pick.is_empty(), "no striker was offered from the bench")
	assert_ne(str(outfield_pick["role"]), "GK", "a keeper was offered for an outfield role")

func test_sided_roles_share_a_bench_family() -> void:
	var eng := _eng(63)
	assert_eq(eng._role_family("RCB"), "CB", "a right centre-back is not read as a centre-back")
	assert_eq(eng._role_family("LCB"), "CB", "a left centre-back is not read as a centre-back")
	assert_eq(eng._role_family("RDM"), "CDM", "a right holding mid is not read as a holding mid")
	assert_eq(eng._role_family("RWB"), "RB", "a wing-back is not read as a full-back")
	assert_eq(eng._role_family("ST"), "ST", "a plain role was rewritten")
