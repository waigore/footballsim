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
	var line: String = Commentary.restart(_rng(), "corner", "NFO", "", true)
	assert_true(line.contains("NFO"), "restart wait line lost the team: " + line)
	assert_lte(line.length(), MAX_LEN, "restart line too long: " + line)

func test_live_line_describes_state() -> void:
	var eng := MatchEngine.new(5)
	for i in range(600):
		eng.tick()
	var line: String = Commentary.live(eng)
	assert_ne(line, "", "live line is empty")
	assert_lte(line.length(), MAX_LEN, "live line too long: " + line)
