extends SceneTree

## Commentary: lines name the actors, fit the ticker, vary, and the live line
## describes the actual state of play.
##   godot --headless --path . --script tools/test_commentary.gd

const MAX_LEN := 92

func _init() -> void:
	var fails := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	fails += _check_shot(rng)
	fails += _check_save(rng)
	fails += _check_goal(rng)
	fails += _check_block(rng)
	fails += _check_restart(rng)
	fails += _check_live()
	fails += _check_match_feed()
	if fails == 0:
		print("PASS: commentary")
	else:
		print("FAIL: %d commentary checks" % fails)
	quit()

func _too_long(s: String) -> bool:
	if s.length() > MAX_LEN:
		print("FAIL: line too long (%d): %s" % [s.length(), s])
		return true
	return false

func _check_shot(rng) -> int:
	var fails := 0
	var seen := {}
	for i in range(40):
		var xg := 0.05 + float(i % 10) * 0.08
		var line: String = Commentary.shot(rng, "B. Šeško", 26.0 - float(i % 8) * 3.0, xg, float(i % 5) * 0.15, "shot")
		if not line.contains("Šeško"):
			print("FAIL: shot line lost the shooter: ", line)
			fails += 1
		if _too_long(line):
			fails += 1
		seen[line] = true
	var header: String = Commentary.shot(rng, "E. Haaland", 9.0, 0.2, 0.2, "header")
	if not header.contains("head"):
		print("FAIL: header line does not read as a header: ", header)
		fails += 1
	if seen.size() < 4:
		print("FAIL: shot commentary does not vary (%d variants)" % seen.size())
		fails += 1
	return fails

func _check_save(rng) -> int:
	var fails := 0
	for how in ["hold", "parry", "goal_line"]:
		var line: String = Commentary.save(rng, "S. Lammens", "E. Haaland", how, 0.45)
		if not line.contains("Lammens"):
			print("FAIL: save line lost the keeper: ", line)
			fails += 1
		if _too_long(line):
			fails += 1
	return fails

func _check_goal(rng) -> int:
	var fails := 0
	var level: String = Commentary.goal(rng, "B. Fernandes", "Amad", false, "MUN", "MCI", 0, 1, 30)
	if not level.contains("Fernandes") or not level.contains("MUN 1-1 MCI"):
		print("FAIL: goal line missing scorer/score: ", level)
		fails += 1
	if not level.contains("Level"):
		print("FAIL: equaliser not read as a leveller: ", level)
		fails += 1
	if _too_long(level):
		fails += 1
	var late: String = Commentary.goal(rng, "B. Šeško", "", false, "MUN", "MCI", 1, 0, 89)
	if not late.contains("Late drama"):
		print("FAIL: 89th-minute goal not called late: ", late)
		fails += 1
	if _too_long(late):
		fails += 1
	var og: String = Commentary.goal(rng, "D. Dalot", "", true, "MUN", "MCI", 1, 1, 55)
	if not og.begins_with("OWN GOAL!"):
		print("FAIL: own goal line wrong: ", og)
		fails += 1
	return fails

func _check_block(rng) -> int:
	var line: String = Commentary.block(rng, "L. Yoro", "E. Haaland")
	if not line.contains("Yoro") or not line.contains("Haaland"):
		print("FAIL: block line lost a name: ", line)
		return 1
	return 1 if _too_long(line) else 0

func _check_restart(rng) -> int:
	var wait: String = Commentary.restart(rng, "corner", "NFO", "", true)
	if not wait.contains("NFO"):
		print("FAIL: restart wait line lost the team: ", wait)
		return 1
	return 1 if _too_long(wait) else 0

func _check_live() -> int:
	var eng := MatchEngine.new(5)
	var guard := 0
	var empty := 0
	while guard < 60 * 60 * 20:
		guard += 1
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		var line: String = Commentary.live(eng)
		if line == "":
			empty += 1
		if line.length() > MAX_LEN:
			print("FAIL: live line too long (%d): %s" % [line.length(), line])
			return 1
	if empty > 0:
		print("FAIL: %d empty live lines" % empty)
		return 1
	print("live sample: ", Commentary.live(eng))
	return 0

func _check_match_feed() -> int:
	var eng := MatchEngine.new(23)
	var guard := 0
	var longest := 0
	var bad := 0
	while eng.phase != "full_time" and guard < 60 * 60 * 400:
		guard += 1
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
	for ev in eng.events:
		var text := str(ev.get("text", ""))
		longest = maxi(longest, text.length())
		if text == "":
			bad += 1
	print("match feed: %d events, longest line %d" % [eng.events.size(), longest])
	if bad > 0:
		print("FAIL: %d empty event lines" % bad)
		return 1
	if longest > 100:
		print("FAIL: event text overruns the ticker")
		return 1
	return 0
