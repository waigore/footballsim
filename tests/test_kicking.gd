extends GdToolsTest


var CACHE_DIR := TestScratch.dir("cache_test_kicking")


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func after_all() -> void:
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _staged(level, seed_in: int = 4242) -> Dictionary:
	var eng := MatchEngine.new(seed_in, "MUN", "MCI")
	eng.phase = "play"
	var gk = eng._gk_of(0)
	var bars: Dictionary = gk.gk.duplicate()
	bars["kic"] = level
	gk.gk = bars
	var dir: float = float(eng.teams[0]["dir"])
	gk.pos = Vector2(5.5 if dir == 1 else eng.L - 5.5, eng.W * 0.5)
	return {"eng": eng, "gk": gk, "bars": bars,
		"aim": Vector2(eng.L * 0.5 + dir * 12.0, eng.W * 0.5)}


func test_the_seed_ships_a_per_keeper_kicking_bar() -> void:
	var seen := {}
	var n := 0
	for id in TeamData.team_ids():
		var data := TeamData.get_team(id)
		var gk: Dictionary = {}
		for p in data.get("starters", []):
			if str(p.get("role", "")) == "GK":
				gk = p.get("gk", {})
				break
		assert_true(gk.has("kic"), "%s ships a keeper with no KICKING bar" % id)
		var bar := float(gk.get("kic", 0))
		assert_true(bar > 0.0 and bar <= 100.0, "%s has a KICKING bar outside 1..100 (%.0f)" % [id, bar])
		seen[bar] = true
		n += 1
	assert_gt(n, 100, "almost no clubs ship a starting keeper")
	assert_gt(seen.size(), 10, "every keeper ships the same KICKING, so the bar cannot be a rating")


func test_the_neutral_boot_lands_the_engines_own_ball() -> void:
	var staged := _staged(MatchKicking.NEUTRAL)
	var gk = staged["gk"]
	var aim: Vector2 = staged["aim"]
	var landed: Vector2 = MatchKicking.landing(staged["bars"], gk.pos, aim, 0.9, -0.7)
	assert_almost_eq(landed.x, aim.x, 0.01, "the mean boot moved the ball off its target in x")
	assert_almost_eq(landed.y, aim.y, 0.01, "the mean boot moved the ball off its target in y")
	assert_almost_eq(MatchKicking.scatter(staged["bars"]), 0.0, 1e-9,
		"the mean boot still sprays the ball")


	assert_almost_eq(MatchKicking.kick_of({}), MatchKicking.NEUTRAL, 1e-9,
		"a keeper with no bars did not read neutral")


	var at_feet: Vector2 = gk.pos + Vector2(0.1, 0.0)
	var kept: Vector2 = MatchKicking.aim_point(staged["bars"], gk.pos, at_feet)
	assert_almost_eq(kept.x, at_feet.x, 1e-6, "a zero-length long ball moved its own target in x")
	assert_almost_eq(kept.y, at_feet.y, 1e-6, "a zero-length long ball moved its own target in y")


func test_a_better_boot_carries_further() -> void:
	var line: Array = []
	for level in [49.0, 56.0, 64.75, 70.0, 79.0]:
		var staged := _staged(level)
		var gk = staged["gk"]
		var aim: Vector2 = staged["aim"]
		var travel: float = MatchKicking.aim_point(staged["bars"], gk.pos, aim).distance_to(gk.pos)
		line.append(travel)
	for i in range(1, line.size()):
		assert_gt(float(line[i]), float(line[i - 1]),
			"a stronger boot did not carry further: %s" % str(line))
	var shipped: float = float(line[4]) - float(line[0])
	assert_gt(shipped, 8.0, "the shipped KICKING spread is worth no ground (%.1f m)" % shipped)
	assert_lt(shipped, 20.0, "the shipped KICKING spread swamps a goal kick (%.1f m)" % shipped)


func test_a_weak_boot_sprays_the_ball() -> void:
	assert_gt(MatchKicking.scatter(_staged(49.0)["bars"]), 1.0,
		"the weakest starting keeper sprays the ball by less than a metre")
	assert_lt(MatchKicking.scatter(_staged(49.0)["bars"]), 4.0,
		"the weakest starting keeper's ball is a shank, not a punt")
	for level in [64.75, 70.0, 79.0]:
		assert_almost_eq(MatchKicking.scatter(_staged(level)["bars"]), 0.0, 1e-9,
			"a boot at or above the mean still sprays the ball")

	assert_lte(MatchKicking.scatter(_staged(0.0)["bars"]), MatchKicking.SCATTER_CAP,
		"the scatter escaped its cap")


func test_the_bar_reaches_the_struck_ball() -> void:
	var weak := _staged(49.0, 900)
	var strong := _staged(79.0, 900)
	var aim: Vector2 = weak["aim"]
	var weak_eng = weak["eng"]
	var strong_eng = strong["eng"]
	weak_eng.keeper_clear(weak["gk"], aim)
	strong_eng.keeper_clear(strong["gk"], aim)
	assert_eq(weak_eng.ball.owner_id, -1, "the keeper kept the ball after clearing it")
	assert_eq(strong_eng.ball.owner_id, -1, "the strong keeper kept the ball after clearing it")


	var weak_speed: float = weak_eng.ball.vel.length()
	var strong_speed: float = strong_eng.ball.vel.length()
	assert_gt(strong_speed, weak_speed,
		"the two boots struck the same goal kick identically (%.2f vs %.2f)" % [strong_speed, weak_speed])

	var again := _staged(49.0, 900)
	again["eng"].keeper_clear(again["gk"], aim)
	assert_almost_eq(again["eng"].ball.vel.x, weak_eng.ball.vel.x, 1e-9,
		"the same seed struck a different ball in x")
	assert_almost_eq(again["eng"].ball.vel.y, weak_eng.ball.vel.y, 1e-9,
		"the same seed struck a different ball in y")


func test_a_true_boot_adds_no_draws_to_the_match() -> void:
	var via_keeper := _staged(79.0, 77)
	var via_engine := _staged(79.0, 77)
	var aim: Vector2 = via_keeper["aim"]
	var s0: int = int(via_keeper["eng"].rng.state)
	via_keeper["eng"].keeper_clear(via_keeper["gk"], aim)
	var keeper_draws: int = s0 - int(via_keeper["eng"].rng.state)
	var e0: int = int(via_engine["eng"].rng.state)
	via_engine["eng"].clear_ball(via_engine["gk"], aim)
	var engine_draws: int = e0 - int(via_engine["eng"].rng.state)
	assert_eq(keeper_draws, engine_draws, "a true boot drew extra from the match RNG")

	var gk = via_keeper["gk"]
	var landed: Vector2 = MatchKicking.landing(via_keeper["bars"], gk.pos, aim, 0.9, -0.7)
	var line: Vector2 = (aim - gk.pos).normalized()
	assert_almost_eq((landed - gk.pos).cross(line), 0.0, 1e-6,
		"a true boot's landing point moved across its line with the draws")
