extends GdToolsTest

## The decider lane: a competition that cannot end level plays extra time,
## then penalties. Every kick comes from the match RNG, so a seed settles the
## same tie twice (DR-20261126-11).

func _level_engine(seed: int) -> MatchEngine:
	var eng := MatchEngine.new(seed)
	eng.requires_winner = true
	eng.score = [0, 0]
	eng.teams[0]["score"] = 0
	eng.teams[1]["score"] = 0
	return eng

func _has_event(eng, kind: String) -> bool:
	for e in eng.events:
		if str(e.get("type", "")) == kind:
			return true
	return false

func _settle_shootout(eng) -> void:
	var guard := 0
	while eng.phase != "full_time" and guard < 60000:
		eng.tick()
		guard += 1

# ----------------------------------------------------------- extra time ----

func test_a_level_tie_goes_to_extra_time() -> void:
	var eng := _level_engine(101)
	eng.half = 2
	eng.phase = "play"
	eng.clock = 5401.0
	eng.tick()
	assert_eq(eng.phase, "et_break", "a level tie needing a winner did not stop for extra time")
	assert_eq(eng.half, 2, "extra time started before the break")
	assert_true(_has_event(eng, "extra_time"), "the extra-time call was not narrated")

func test_a_decisive_match_ends_at_ninety() -> void:
	var eng := _level_engine(102)
	eng.half = 2
	eng.phase = "play"
	eng.score = [2, 1]
	eng.clock = 5401.0
	eng.tick()
	assert_eq(eng.phase, "full_time", "a decisive tie played extra time anyway")
	assert_eq(int(eng.winner), 0, "the winner was not the side ahead")
	assert_true(eng.shootout.is_empty(), "a decisive match went to penalties")

func test_a_level_tie_without_a_winner_rule_ends_at_ninety() -> void:
	var eng := MatchEngine.new(103)
	eng.half = 2
	eng.phase = "play"
	eng.clock = 5401.0
	eng.tick()
	assert_eq(eng.phase, "full_time", "a league draw was forced into extra time")
	assert_eq(int(eng.winner), -1, "a draw named a winner")

func test_extra_time_plays_both_periods_then_penalties() -> void:
	var eng := _level_engine(104)
	eng.half = 2
	eng.phase = "et_break"
	eng.clock = 5400.0
	eng.resume_after_break()
	assert_eq(eng.half, 3, "the first extra-time period did not start")
	assert_eq(eng.phase, "restart", "extra time did not kick off")
	assert_gt(float(eng.added[2]), 0.0, "the first extra-time period got no added time")
	eng.phase = "play"
	eng.clock = 6300.0 + float(eng.added[2]) + 0.1
	eng.tick()
	assert_eq(eng.phase, "et_break", "the first extra-time period did not end")
	assert_eq(eng.half, 3, "the half number moved during the extra-time break")
	eng.resume_after_break()
	assert_eq(eng.half, 4, "the second extra-time period did not start")
	assert_gt(float(eng.added[3]), 0.0, "the second extra-time period got no added time")
	eng.phase = "play"
	eng.clock = 7200.0 + float(eng.added[3]) + 0.1
	eng.tick()
	assert_eq(eng.phase, "shootout", "level after extra time did not go to penalties")
	assert_true(_has_event(eng, "shootout_start"), "the shootout was not announced")

# ------------------------------------------------------------- shootout ----

func test_the_shootout_settles_the_tie() -> void:
	var eng := _level_engine(105)
	eng.phase = "shootout"
	eng._begin_shootout()
	_settle_shootout(eng)
	assert_eq(eng.phase, "full_time", "the shootout never finished")
	assert_true(_has_event(eng, "shootout_end"), "the shootout result was not narrated")
	assert_true(_has_event(eng, "full_time"), "the final whistle never came")
	assert_between(float(eng.winner), 0.0, 1.0, "the shootout named no winner")
	assert_gte(eng.shootout.size(), 5, "the shootout ended before five kicks were taken")
	assert_ne(int(eng.shootout_score[0]), int(eng.shootout_score[1]), "the shootout finished level")
	assert_eq(int(eng.score[0]), int(eng.score[1]), "penalties changed the match score")
	assert_true(eng.finished, "the match did not mark itself finished")

func test_the_shootout_is_deterministic_for_a_seed() -> void:
	var a := _level_engine(777)
	a._begin_shootout()
	_settle_shootout(a)
	var b := _level_engine(777)
	b._begin_shootout()
	_settle_shootout(b)
	assert_eq(a.shootout_score, b.shootout_score, "the same seed settled a different shootout")
	assert_eq(a.shootout.size(), b.shootout.size(), "the same seed took a different number of kicks")
	assert_eq(int(a.winner), int(b.winner), "the same seed named a different winner")

func test_the_shootout_stops_once_the_tie_is_decided() -> void:
	var eng := _level_engine(106)
	eng.shootout_score = [3, 0]
	eng.shootout = [
		{"team": 0}, {"team": 1}, {"team": 0}, {"team": 1}, {"team": 0}, {"team": 1},
	]
	assert_true(eng._shootout_decided(), "a three-goal lead with three kicks left was not decided")
	eng.shootout_score = [1, 1]
	assert_false(eng._shootout_decided(), "a level shootout was called early")

func test_extra_time_can_be_won_before_penalties() -> void:
	var eng := _level_engine(111)
	eng.half = 4
	eng.phase = "play"
	eng.added[3] = 1.0
	eng.score = [1, 0]
	eng.clock = 7201.0
	eng.tick()
	assert_eq(eng.phase, "full_time", "a tie won in extra time still went to penalties")
	assert_eq(int(eng.winner), 0, "the extra-time winner was not named")
	assert_true(eng.shootout.is_empty(), "a decided tie took penalties")

func test_the_break_only_starts_extra_time_when_it_is_due() -> void:
	var eng := _level_engine(112)
	eng.phase = "play"
	eng.resume_after_break()
	assert_eq(eng.half, 1, "a break resumed a match that was not in one")
	assert_eq(eng.phase, "play", "a break changed a live match")

func test_a_side_with_no_outfielders_still_fields_a_taker() -> void:
	var eng := _level_engine(113)
	for p in eng.players:
		if p.team == 0 and not p.is_gk:
			p.sent_off = true
	eng.shootout_ids = [[], []]
	var taker = eng._shootout_taker(0)
	assert_not_null(taker, "a side with no outfielders had no taker")
	assert_true(bool(taker.is_gk), "the fallback taker was not the keeper")

func test_the_decider_lines_read_well() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	assert_true(CommentaryExtraTime.extra_time(rng, "MUN", "MCI").contains("extra time"),
		"the extra-time line did not read")
	assert_true(CommentaryExtraTime.extra_time_start(rng, "MUN", "MCI") != "", "no extra-time kick-off line")
	assert_true(CommentaryExtraTime.extra_time_second(rng, "MUN", "MCI") != "", "no second-period line")
	assert_true(CommentaryExtraTime.extra_time_break() != "", "no extra-time break line")
	assert_true(CommentaryExtraTime.shootout_start(rng, "MUN").contains("MUN"), "no shootout start line")
	assert_true(CommentaryExtraTime.shootout_kick(rng, "Haaland", true).contains("Haaland"),
		"a scored kick did not name the taker")
	assert_true(CommentaryExtraTime.shootout_kick(rng, "Haaland", false).contains("Haaland"),
		"a missed kick did not name the taker")
	assert_true(CommentaryExtraTime.shootout_end("MUN", 4, 3).contains("4-3"), "no shootout result line")
	assert_true(CommentaryExtraTime.full_time_pens(rng, "MUN", 1, "MCI", 1, 4, 3).contains("MUN"),
		"the winning side was not named in the full-time line")
	assert_true(CommentaryExtraTime.full_time_pens(rng, "MUN", 1, "MCI", 1, 3, 4).contains("MCI"),
		"the winning side was not named in the full-time line")

func test_a_leftover_shootout_finishes_in_one_call() -> void:
	var eng := _level_engine(107)
	eng._begin_shootout()
	var frozen: float = eng.clock
	assert_true(eng.run_to_full_time(-1), "the leftover shootout did not reach full time")
	assert_eq(eng.clock, frozen, "the match clock ran during the shootout")
	assert_true(eng.winner >= 0, "the fast-forwarded shootout named no winner")

# --------------------------------------------------------------- state -----

func test_the_extra_time_clock_reads_as_the_match_does() -> void:
	var eng := _level_engine(108)
	eng.half = 3
	eng.clock = 6000.0
	assert_eq(eng.display_clock(), "100:00", "the extra-time clock did not read in minutes")
	eng.clock = 6301.0
	assert_eq(eng.display_clock(), "105:00 +00:01", "extra-time added time did not read")
	eng.half = 4
	eng.clock = 7000.0
	assert_eq(eng.display_clock(), "116:40", "the second extra-time period did not read")
	eng.phase = "shootout"
	assert_eq(eng.display_clock(), "PENALTIES", "the clock did not hand over to the shootout")

func test_a_snapshot_keeps_the_decider() -> void:
	var eng := _level_engine(109)
	eng.phase = "shootout"
	eng._begin_shootout()
	eng.tick()
	eng.tick()
	var snap := eng.to_dict()
	var other := MatchEngine.new(1, "IPS", "NEW")
	other.from_dict(snap)
	assert_eq(other.phase, "shootout", "the snapshot lost the shootout phase")
	assert_true(other.requires_winner, "the snapshot lost the winner rule")
	assert_eq(other.shootout_score, eng.shootout_score, "the snapshot lost the shootout tally")
	assert_eq(other.shootout.size(), eng.shootout.size(), "the snapshot lost the kicks")
	assert_eq(other.shootout_ids, eng.shootout_ids, "the snapshot lost the kick order")

func test_the_full_time_card_names_the_shootout() -> void:
	var eng := _level_engine(110)
	eng.shootout_score = [4, 3]
	assert_eq(HudBannersBand.pens_line(eng), "PENS 4 – 3", "the card did not name the shootout")
	eng.shootout_score = [2, 2]
	assert_eq(HudBannersBand.pens_line(eng), "", "a level shootout was printed as a result")

func test_the_break_cards_read_the_new_phases() -> void:
	assert_eq(HudBannersBand.break_title("et_break"), "EXTRA TIME", "the extra-time card had no title")
	assert_eq(HudBannersBand.break_title("shootout"), "PENALTIES", "the shootout card had no title")
	assert_eq(HudBannersBand.break_title("full_time"), "FULL TIME", "full time lost its title")
	assert_eq(HudBannersBand.break_hint("et_break", true, false, false),
		"EXTRA TIME STARTS SHORTLY", "the extra-time card had no hint")
	assert_eq(HudBannersBand.break_hint("shootout", false, false, false),
		"PENALTIES DECIDE IT", "the shootout card had no hint")
