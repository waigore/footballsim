extends GdToolsTest

## Commentary: lines name the actors, fit the ticker, vary, and the live line
## describes the actual state of play.

const MAX_LEN := 92

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	return r

func test_shot_names_shooter_and_varies() -> void:
	var rng := _rng()
	var seen := {}
	for i in range(40):
		var line: String = Commentary.shot(rng, "B. Šeško", 26.0 - float(i % 8) * 3.0,
			0.05 + float(i % 10) * 0.08, float(i % 5) * 0.15, "shot")
		assert_true(line.contains("Šeško"), "shot line lost the shooter: " + line)
		assert_lte(line.length(), MAX_LEN, "shot line too long: " + line)
		seen[line] = true
	assert_gte(seen.size(), 4, "shot commentary does not vary")

func test_header_reads_as_a_header() -> void:
	var line: String = Commentary.shot(_rng(), "E. Haaland", 9.0, 0.2, 0.2, "header")
	assert_true(line.contains("head"), "header line does not read as a header: " + line)

func test_save_names_keeper() -> void:
	for how in ["hold", "parry", "goal_line"]:
		var line: String = Commentary.save(_rng(), "S. Lammens", "E. Haaland", how, 0.45)
		assert_true(line.contains("Lammens"), "save line lost the keeper: " + line)
		assert_lte(line.length(), MAX_LEN, "save line too long: " + line)

func test_goal_carries_score_and_context() -> void:
	var level: String = Commentary.goal(_rng(), "B. Fernandes", "Amad", false, "MUN", "MCI", 0, 1, 30)
	assert_true(level.contains("Fernandes"), "goal line lost the scorer: " + level)
	assert_true(level.contains("MUN 1-1 MCI"), "goal line lost the score: " + level)
	assert_true(level.contains("Level"), "equaliser not read as a leveller: " + level)
	var late: String = Commentary.goal(_rng(), "B. Šeško", "", false, "MUN", "MCI", 1, 0, 89)
	assert_true(late.contains("Late drama"), "89th-minute goal not called late: " + late)
	var og: String = Commentary.goal(_rng(), "D. Dalot", "", true, "MUN", "MCI", 1, 1, 55)
	assert_true(og.begins_with("OWN GOAL!"), "own goal line wrong: " + og)

func test_block_names_both_players() -> void:
	var line: String = Commentary.block(_rng(), "L. Yoro", "E. Haaland")
	assert_true(line.contains("Yoro") and line.contains("Haaland"), "block line lost a name: " + line)

func test_restart_wait_names_team() -> void:
	var line: String = CommentaryRestarts.restart(_rng(), "corner", "NFO", "", true)
	assert_true(line.contains("NFO"), "restart wait line lost the team: " + line)
	assert_lte(line.length(), MAX_LEN, "restart line too long: " + line)

func test_live_line_describes_state() -> void:
	# Craft the picture the live line reads — possession, a carrier, pressure —
	# instead of ticking six hundred steps to stumble into one under coverage.
	var eng := TestEngineBoot.match(5)
	eng.phase = "play"
	eng.possession_team = 0
	eng.possession_loose = false
	var carrier = eng.players[10]
	eng.ball.owner_id = carrier.id
	eng.ball.pos = carrier.pos
	eng.ball.vel = Vector2.ZERO
	var line: String = CommentaryLive.live(eng)
	assert_ne(line, "", "live line is empty")
	assert_true(line.contains(carrier.name) or line.contains(eng.teams[0]["data"]["short"]),
		"live line lost the side in possession: " + line)
	assert_lte(line.length(), MAX_LEN, "live line too long: " + line)

# ---------------------------------------------------------- every builder ---

func _each(builder: Callable, count: int, must_contain: String) -> void:
	# Every line a builder can produce must name the actor and fit the ticker.
	for i in range(count):
		var line: String = builder.call(i)
		assert_true(line.contains(must_contain), "a line lost \"%s\": %s" % [must_contain, line])
		assert_lte(line.length(), MAX_LEN, "line too long: " + line)

func test_save_lines_cover_hold_parry_and_the_goal_line() -> void:
	for how in ["hold", "parry", "goal_line"]:
		_each(func(i): return Commentary.save(_rng(), "A. Onana", "E. Haaland", how, 0.05 + 0.1 * i), 12, "Onana")
	_each(func(i): return Commentary.save(_rng(), "A. Onana", "", "hold", 0.5), 6, "Onana")

func test_goal_lines_read_leads_assists_and_late_winners() -> void:
	_each(func(i): return Commentary.goal(_rng(), "B. Šeško", "Bruno", false, "MUN", "MCI", 1, 0, 30), 8, "Šeško")
	# An assist is only named when the goal line is not already carrying the
	# state of the game (level, ahead, late drama).
	var assisted: String = Commentary.goal(_rng(), "B. Šeško", "Bruno", false, "MUN", "MCI", 0, 2, 30)
	assert_true(assisted.to_lower().contains("bruno"), "an assist was dropped from the goal line: " + assisted)
	var lead: String = Commentary.goal(_rng(), "B. Šeško", "", false, "MUN", "MCI", 1, 0, 30)
	assert_true(lead.contains("MUN lead"), "a goal that puts a side ahead was not read as a lead: " + lead)

func test_foul_lines_read_penalties_and_free_kicks() -> void:
	_each(func(i): return Commentary.foul(_rng(), "D. Dalot", "E. Haaland", true), 8, "Haaland")
	_each(func(i): return Commentary.foul(_rng(), "D. Dalot", "E. Haaland", false), 8, "Dalot")

func test_card_lines_cover_every_kind() -> void:
	for kind in ["yellow", "red", "red_second"]:
		_each(func(i): return Commentary.card(_rng(), "L. Yoro", kind), 8, "Yoro")

func test_clearance_lines_read_headed_or_hoofed() -> void:
	_each(func(i): return Commentary.clearance(_rng(), "M. Škriniar", true), 6, "Škriniar")
	_each(func(i): return Commentary.clearance(_rng(), "M. Škriniar", false), 6, "Škriniar")

func test_handball_lines_read_the_box() -> void:
	_each(func(i): return Commentary.handball(_rng(), "D. Dalot", true), 6, "Dalot")
	_each(func(i): return Commentary.handball(_rng(), "D. Dalot", false), 6, "Dalot")

func test_injury_lines_read_whether_a_change_is_left() -> void:
	_each(func(i): return CommentaryBench.injury(_rng(), "L. Martínez", true), 6, "Martínez")
	_each(func(i): return CommentaryBench.injury(_rng(), "L. Martínez", false), 6, "Martínez")

func test_substitution_lines_name_manager_or_team() -> void:
	_each(func(i): return CommentaryBench.substitution(_rng(), "MUN", "R. Højlund", "C. Eriksen", "R. Amorim"),
		6, "Højlund")
	_each(func(i): return CommentaryBench.substitution(_rng(), "MUN", "R. Højlund", "C. Eriksen"), 6, "Højlund")

func test_restart_lines_cover_every_kind_and_the_wait() -> void:
	for kind in ["throw_in", "corner", "free_kick", "penalty", "kickoff"]:
		_each(func(i): return CommentaryRestarts.restart(_rng(), kind, "NFO", "M. Sels", false), 6, "NFO")
	# A goal kick is named for the keeper who takes it.
	_each(func(i): return CommentaryRestarts.restart(_rng(), "goal_kick", "NFO", "M. Sels", false), 6, "Sels")
	_each(func(i): return CommentaryRestarts.restart(_rng(), "goal_kick", "NFO", "", false), 6, "NFO")
	for kind in ["corner", "free_kick", "throw_in"]:
		_each(func(i): return CommentaryRestarts.restart(_rng(), kind, "NFO", "M. Sels", true), 6, "NFO")
	assert_true(CommentaryRestarts.restart(_rng(), "goal_kick", "NFO", "", false).begins_with("Goal kick"),
		"a goal kick with no named taker was not read as one")

func test_kickoff_cross_offside_and_penalty_lines_name_the_actor() -> void:
	_each(func(i): return CommentaryRestarts.kickoff(_rng(), "Manchester United"), 6, "Manchester United")
	_each(func(i): return Commentary.cross(_rng(), "A. Garnacho"), 8, "Garnacho")
	_each(func(i): return Commentary.offside(_rng(), "A. Garnacho"), 6, "Garnacho")
	_each(func(i): return CommentaryRestarts.penalty_taken(_rng(), "B. Fernandes"), 6, "Fernandes")

func test_half_time_and_full_time_read_the_score() -> void:
	var half: String = CommentaryRestarts.half_time(_rng(), "MUN", 2, "MCI", 1)
	assert_true(half.contains("MUN") and half.contains("MCI"), "half-time line lost a side: " + half)
	var draw: String = CommentaryRestarts.full_time(_rng(), "MUN", 1, "MCI", 1)
	assert_true(draw.contains("Honours even"), "a draw was not read as honours even: " + draw)
	var home: String = CommentaryRestarts.full_time(_rng(), "MUN", 3, "MCI", 1)
	assert_true(home.contains("MUN take it"), "a home win was not credited to the home side: " + home)
	var away: String = CommentaryRestarts.full_time(_rng(), "MUN", 1, "MCI", 2)
	assert_true(away.contains("MCI take it"), "an away win was not credited to the away side: " + away)

func test_tactics_line_names_the_manager_and_the_change() -> void:
	var line: String = CommentaryBench.tactics(_rng(), "R. Amorim", "MUN", ["press higher", "narrower"])
	assert_true(line.contains("Amorim"), "tactics line lost the manager: " + line)
	assert_true(line.contains("press higher"), "tactics line lost the change: " + line)
	var nothing: String = CommentaryBench.tactics(_rng(), "R. Amorim", "MUN", [])
	assert_true(nothing.contains("shape change"), "an empty change list was not described: " + nothing)

func test_live_line_reads_the_zone_and_the_scoreline() -> void:
	var eng := MatchEngine.new(6)
	eng.phase = "play"
	eng.clock = 4700.0
	eng.score[0] = 2
	eng.score[1] = 0
	for pos in [Vector2(10.0, 34.0), Vector2(50.0, 34.0), Vector2(75.0, 34.0), Vector2(92.0, 5.0)]:
		var p = eng.players[3]
		eng.ball.owner_id = p.id
		eng.ball.pos = pos
		p.pos = pos
		var line: String = CommentaryLive.live(eng)
		assert_true(line.contains("MUN 2-0 MCI"), "a late live line dropped the score: " + line)
	for kind in ["penalty", "corner", "throw_in", "goal_kick", "kickoff", "free_kick"]:
		eng.phase = "restart"
		eng.restart = {"type": kind}
		assert_ne(CommentaryLive.live(eng), "", "no live line for a " + kind)
	eng.phase = "play"
	eng.ball.owner_id = -1
	eng.ball.last_touch_team = 0
	eng.ball.pos = Vector2(52.0, 34.0)
	assert_ne(CommentaryLive.live(eng), "", "no live line for a loose ball")
	var gk = eng._gk_of(0)
	eng.ball.owner_id = gk.id
	assert_true(CommentaryLive.live(eng).contains("keeper"), "a keeper on the ball was not read as building from the back")
