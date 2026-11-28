extends GdToolsTest


func _outfield(eng, t: int):
	for p in eng.players:
		if p.team == t and not p.is_gk:
			return p
	return null

func _on_pitch(eng, t: int) -> int:
	var n := 0
	for p in eng.players:
		if p.team == t and not p.sent_off:
			n += 1
	return n

func _has_event(eng, kind: String) -> bool:
	for e in eng.events:
		if str(e.get("type", "")) == kind:
			return true
	return false


func test_first_half_plays_added_time() -> void:
	var eng := MatchEngine.new(11)
	eng.phase = "play"
	eng.clock = 2701.0
	eng.tick()
	assert_gt(float(eng.added[0]), 0.0, "no first-half added time was set")
	assert_eq(eng.phase, "play", "the half ended at 45:00 with no added time")
	assert_true(eng.display_clock().contains("+"), "clock does not show added time: " + eng.display_clock())

func test_first_half_ends_after_added_time() -> void:
	var eng := MatchEngine.new(12)
	eng.phase = "play"
	eng.clock = 2701.0
	eng.tick()
	eng.clock = 2700.0 + float(eng.added[0]) + 1.0
	eng.tick()
	assert_eq(eng.phase, "half_time", "the half did not end after its added time")


func test_handball_outside_the_box_is_a_free_kick() -> void:
	var eng := MatchEngine.new(13)
	eng.phase = "play"
	var d = _outfield(eng, 0)
	d.pos = Vector2(60.0, 34.0)
	eng._award_handball(d)
	assert_eq(eng.phase, "restart", "a handball did not stop play")
	assert_eq(str(eng.restart["type"]), "free_kick", "handball outside the box should be a free kick")
	assert_eq(int(eng.restart["team"]), 1, "the free kick went to the wrong side")
	assert_eq(int(eng.stats[0]["handballs"]), 1, "the handball was not recorded")

func test_handball_inside_the_box_is_a_penalty() -> void:
	var eng := MatchEngine.new(14)
	eng.phase = "play"
	var d = _outfield(eng, 0)
	var own: Vector2 = eng.own_goal_pos(0)
	d.pos = Vector2(own.x + (10.0 if own.x < eng.L * 0.5 else -10.0), 34.0)
	assert_true(eng.in_penalty_box(d.pos, 0), "fixture did not place the defender in his own box")
	eng._award_handball(d)
	assert_eq(str(eng.restart["type"]), "penalty", "handball in the box should be a penalty")
	assert_eq(int(eng.restart["team"]), 1, "the penalty went to the wrong side")


func test_injury_costs_a_change_and_is_replaced() -> void:
	var eng := MatchEngine.new(15)
	var p = _outfield(eng, 0)
	var before: int = int(eng.teams[0]["subs_left"])
	var role: String = p.role
	eng._injure(p)
	assert_true(p.injured, "the player was not marked injured")
	assert_eq(int(eng.teams[0]["subs_left"]), before - 1, "the injury did not cost a substitution")
	assert_false(eng.players.has(p), "the injured player is still in the line-up")
	assert_eq(_on_pitch(eng, 0), 11, "the injured side was not made back up to eleven")
	var slot = null
	for q in eng.players:
		if q.team == 0 and q.role == role and not q.is_gk:
			slot = q
			break
	assert_not_null(slot, "no replacement filled the injured player's slot")
	assert_true(_has_event(eng, "injury"), "no injury line reached the event log")

func test_injury_without_changes_leaves_ten() -> void:
	var eng := MatchEngine.new(16)
	eng.teams[0]["subs_left"] = 0
	var p = _outfield(eng, 0)
	var before := _on_pitch(eng, 0)
	eng._injure(p)
	assert_true(p.sent_off, "an injured player stayed on with no change available")
	assert_eq(_on_pitch(eng, 0), before - 1, "the side did not go down to ten")


func test_referee_stays_on_the_pitch_and_whistles() -> void:
	var eng := MatchEngine.new(17)
	assert_eq(eng.referee_name, TeamData.REFEREE, "the official is not named from squad data")
	for i in range(48):
		eng.tick()
	var r = eng.referee
	assert_between(r.pos.x, 3.0, eng.L - 3.0, "the referee left the pitch: %s" % r.pos)
	assert_between(r.pos.y, 3.0, eng.W - 3.0, "the referee left the pitch: %s" % r.pos)
	eng._emit("foul", "Foul.", 0, _outfield(eng, 0))
	assert_gt(float(r.whistle), 0.0, "the referee did not whistle a foul")
	for i in range(60):
		eng.tick()
	assert_eq(float(r.whistle), 0.0, "the whistle never cleared")

func test_a_report_keeps_a_goal_the_scorer_left_behind() -> void:
	var eng := MatchEngine.new(41)
	var scorer = _outfield(eng, 0)
	eng._emit("goal", "GOAL!", 0, scorer)
	eng.score[0] = 1
	assert_true(eng._bring_on(0, scorer, false, false, {}), "the bench refused the change")
	assert_false(eng.by_id.has(scorer.id), "the scorer is still on the pitch")
	var rows := LeagueHighlights.engine_events(eng, "fx")
	assert_eq(rows.size(), 1, "the goal left the report with its scorer")
	assert_eq(str(rows[0]["kind"]), "goal", "the row is not a goal")
	assert_eq(str(rows[0]["player_id"]), str(scorer.key), "the goal lost its scorer")
	assert_eq(str(rows[0]["club_id"]), "MUN", "the goal lost its club")

func test_the_live_ring_trimming_never_takes_a_goal_off_the_report() -> void:
	var eng := MatchEngine.new(42)
	var p = _outfield(eng, 0)
	eng._emit("goal", "GOAL!", 0, p)
	for i in range(650):
		eng._emit("pass", "pass %d" % i, 0, p)
	assert_eq(eng.events.size(), 600, "the live ring grew past its cap")
	var rows := LeagueHighlights.engine_events(eng, "fx")
	assert_eq(rows.size(), 1, "the trimmed live ring took the goal with it")
	assert_eq(int(rows[0]["minute"]), 1, "the goal lost its minute")

func test_each_booking_keeps_the_colour_it_was_shown() -> void:
	var eng := MatchEngine.new(43)
	var p = _outfield(eng, 0)
	p.yellow = 1
	eng._send_off_or_book(p, "yellow")
	p.yellow = 2
	eng._send_off_or_book(p, "red_second")
	var rows := LeagueHighlights.engine_events(eng, "fx")
	assert_eq(rows.size(), 2, "a booking left the report")
	assert_eq(str(rows[0]["kind"]), "yellow", "the first yellow was recorded as a red")
	assert_eq(str(rows[1]["kind"]), "red", "the second yellow was not a red")

func test_a_snapshot_carries_the_report_log() -> void:
	var eng := MatchEngine.new(44)
	var p = _outfield(eng, 0)
	eng._emit("goal", "GOAL!", 0, p)
	var other := MatchEngine.new(45)
	other.from_dict(eng.to_dict())
	var rows := LeagueHighlights.engine_events(other, "fx")
	assert_eq(rows.size(), 1, "the restored engine lost its report")

func test_an_older_snapshot_rebuilds_its_report_from_its_events() -> void:
	var eng := MatchEngine.new(46)
	var p = _outfield(eng, 0)
	eng._emit("pass", "a pass", 0, p)
	eng._emit("goal", "GOAL!", 0, p)
	var snap: Dictionary = eng.to_dict()
	snap.erase("report_log")
	for e in snap["events"]:
		(e as Dictionary).erase("player_key")
	var other := MatchEngine.new(47)
	other.from_dict(snap)
	var rows := LeagueHighlights.engine_events(other, "fx")
	assert_eq(rows.size(), 1, "the older snapshot lost its goal")
	assert_eq(str(rows[0]["player_id"]), str(p.key), "the older snapshot lost its scorer")
	assert_eq(str(rows[0]["detail"]), str(p.name), "the older snapshot lost his name")

func test_an_older_snapshot_card_reads_its_colour_and_skips_a_missing_man() -> void:
	var eng := MatchEngine.new(48)
	var booked = _outfield(eng, 0)
	eng._send_off_or_book(booked, "yellow")
	var sent_off = _outfield(eng, 1)
	eng._send_off_or_book(sent_off, "red")
	var snap: Dictionary = eng.to_dict()
	snap.erase("report_log")
	for e in snap["events"]:
		(e as Dictionary).erase("player_key")
		(e as Dictionary).erase("card")
	var kept: Array = []
	for pd in snap["players"]:
		if str(pd["key"]) != str(sent_off.key):
			kept.append(pd)
	snap["players"] = kept
	var other := MatchEngine.new(49)
	other.from_dict(snap)
	var rows := LeagueHighlights.engine_events(other, "fx")
	assert_eq(rows.size(), 1, "a booking with no man on the pitch invented a row")
	assert_eq(str(rows[0]["player_id"]), str(booked.key), "the older booking lost its man")
	assert_eq(str(rows[0]["kind"]), "yellow", "the older booking lost its colour")

func test_snapshot_carries_official_and_injury_state() -> void:
	var eng := MatchEngine.new(18)
	eng.teams[0]["subs_left"] = 0
	var p = _outfield(eng, 0)
	eng._injure(p)
	for i in range(5):
		eng.tick()
	var snap: Dictionary = eng.to_dict()
	var other := MatchEngine.new(19)
	other.from_dict(snap)
	assert_almost_eq(other.referee.pos.x, eng.referee.pos.x, 0.001, "referee position was not restored")
	assert_almost_eq(float(other.injury_timer), float(eng.injury_timer), 0.001, "injury timer was not restored")
	var got = other.by_id.get(p.id, null)
	assert_not_null(got, "the injured player vanished from the restored squad")
	assert_true(got.injured, "the injured flag was not restored")


func _assisted_goal(eng: Variant, seed_off: int) -> Array:
	var scorer = null
	var helper = null
	for p in eng.players:
		if p.team != 0 or p.is_gk or p.sent_off:
			continue
		if scorer == null:
			scorer = p
		else:
			helper = p
			break
	eng.ball.last_touch_id = scorer.id
	eng.ball.last_touch_team = 0
	eng.ball.assist_id = helper.id
	eng.ball.assist_time = eng.clock - float(seed_off)
	eng._score_goal(1)
	return [scorer, helper]


func test_a_goal_names_the_assister_it_was_given() -> void:
	var eng := MatchEngine.new(51)
	var pair := _assisted_goal(eng, 0)
	assert_eq(str(eng.last_goal.get("assist", "")), str(pair[1].name),
		"the goal card lost the assister")
	assert_eq(int(pair[1].stats["assists"]), 1, "the assister was not credited")

func test_an_assist_older_than_the_window_is_not_given() -> void:
	var eng := MatchEngine.new(52)
	var pair := _assisted_goal(eng, 20)
	assert_eq(str(eng.last_goal.get("assist", "")), "", "an old pass still counted as an assist")
	assert_eq(int(pair[1].stats["assists"]), 0, "an old pass credited the wrong man")

func test_a_report_row_carries_the_assist_beside_its_goal() -> void:
	var eng := MatchEngine.new(53)
	var pair := _assisted_goal(eng, 0)
	var rows := LeagueHighlights.engine_events(eng, "fx")
	assert_eq(rows.size(), 2, "the report does not carry the assist beside the goal")
	assert_eq(str(rows[0]["kind"]), "goal", "the goal is not the first row")
	assert_eq(str(rows[1]["kind"]), "assist", "the assist is not filed as an assist")
	assert_eq(str(rows[1]["player_id"]), str(pair[1].key), "the assist names the wrong man")
	assert_eq(str(rows[1]["club_id"]), "MUN", "the assist was given to the wrong club")
	assert_eq(int(rows[1]["minute"]), int(rows[0]["minute"]),
		"the assist is not on the goal's own minute")

func test_a_penalty_share_goal_with_no_pass_gets_no_assist_row() -> void:
	var eng := MatchEngine.new(54)
	var p = _outfield(eng, 0)
	eng.ball.assist_id = -1
	eng.ball.last_touch_id = p.id
	eng.ball.last_touch_team = 0
	eng._score_goal(1)
	var rows := LeagueHighlights.engine_events(eng, "fx")
	assert_eq(rows.size(), 1, "an unassisted goal invented a helper")
	assert_eq(str(rows[0]["kind"]), "goal", "the goal left the report")


func test_a_helper_on_the_other_side_is_not_credited() -> void:
	var eng := MatchEngine.new(55)
	var scorer = _outfield(eng, 0)
	var rival = _outfield(eng, 1)
	eng.ball.assist_id = rival.id
	eng.ball.assist_time = eng.clock
	eng.ball.last_touch_id = scorer.id
	eng.ball.last_touch_team = 0
	eng._score_goal(1)
	assert_eq(str(eng.last_goal.get("assist", "")), "",
		"an opponent was credited with the assist")
	assert_eq(int(rival.stats["assists"]), 0, "an opponent earned an assist")

func test_the_scorer_cannot_assist_himself() -> void:
	var eng := MatchEngine.new(56)
	var scorer = _outfield(eng, 0)
	eng.ball.assist_id = scorer.id
	eng.ball.assist_time = eng.clock
	eng.ball.last_touch_id = scorer.id
	eng.ball.last_touch_team = 0
	eng._score_goal(1)
	assert_eq(str(eng.last_goal.get("assist", "")), "",
		"a solo goal credited the scorer with his own assist")
	var rows := LeagueHighlights.engine_events(eng, "fx")
	assert_eq(rows.size(), 1, "a solo goal grew an assist row")
