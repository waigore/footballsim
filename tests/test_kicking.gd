extends GdToolsTest

## The keeper's KICKING bar: the fifth of the five keeper ratings the player page
## draws, shipped per keeper (49–79 for the starting keepers, mean 64.75) and
## read by the long ball he strikes — how far it carries and how truly it lands
## (`MatchKicking`).
##
## A match gives a handful of keeper long balls, which cannot resolve a rating at
## any sane n, so the rule is pinned directly here and measured on a staged
## goal-kick sweep (`tools/kicking_sweep.gd`).

## A keeper on his own goal-kick spot, with the engine's own target line. The gk
## bars are copied first: `TeamData` caches the squad dict, so writing the rating
## in place would move every other engine's keeper too.
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

## The seed ships a per-keeper rating, and the spread is real — that is the value
## the two reads are fitted to.
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

## The league's mean boot strikes exactly the ball the engine always struck: the
## target is the engine's own, and there is no scatter to draw.
func test_the_neutral_boot_lands_the_engines_own_ball() -> void:
	var staged := _staged(MatchKicking.NEUTRAL)
	var gk = staged["gk"]
	var aim: Vector2 = staged["aim"]
	var landed: Vector2 = MatchKicking.landing(staged["bars"], gk.pos, aim, 0.9, -0.7)
	assert_almost_eq(landed.x, aim.x, 0.01, "the mean boot moved the ball off its target in x")
	assert_almost_eq(landed.y, aim.y, 0.01, "the mean boot moved the ball off its target in y")
	assert_almost_eq(MatchKicking.scatter(staged["bars"]), 0.0, 1e-9,
		"the mean boot still sprays the ball")
	# A keeper shipped without the bars (a bare fixture, an older save) reads the
	# league's neutral boot, never a keeper who cannot kick.
	assert_almost_eq(MatchKicking.kick_of({}), MatchKicking.NEUTRAL, 1e-9,
		"a keeper with no bars did not read neutral")
	# A ball aimed at the keeper's own feet is not a long ball: the target is
	# taken as given rather than divided by nothing.
	var at_feet: Vector2 = gk.pos + Vector2(0.1, 0.0)
	assert_almost_eq(MatchKicking.aim_point(staged["bars"], gk.pos, at_feet), at_feet,
		"a zero-length long ball moved its own target")

## Reach is monotone: a better boot puts the same ball further down its own line,
## and the shipped band has to be worth a visible amount of ground.
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

## Scatter is the other half: a boot under the league's mean sprays the ball and
## a boot at or above it lands true — so a weak kicker loses both halves of the
## same ball, and the shipped weakest keeper's miss is measured.
func test_a_weak_boot_sprays_the_ball() -> void:
	assert_gt(MatchKicking.scatter(_staged(49.0)["bars"]), 1.0,
		"the weakest starting keeper sprays the ball by less than a metre")
	assert_lt(MatchKicking.scatter(_staged(49.0)["bars"]), 4.0,
		"the weakest starting keeper's ball is a shank, not a punt")
	for level in [64.75, 70.0, 79.0]:
		assert_almost_eq(MatchKicking.scatter(_staged(level)["bars"]), 0.0, 1e-9,
			"a boot at or above the mean still sprays the ball")
	# The cap keeps a rating far below the seed from turning a goal kick loose.
	assert_lte(MatchKicking.scatter(_staged(0.0)["bars"]), MatchKicking.SCATTER_CAP,
		"the scatter escaped its cap")

## The rule reaches the ball: the same staged goal kick, struck by two keepers,
## lands in two different places — and a seed reproduces each of them.
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
	# The long ball's own speed carries the reach: it is struck to travel
	# further, so the ball leaves the boot harder than the weak keeper's.
	var weak_speed: float = weak_eng.ball.vel.length()
	var strong_speed: float = strong_eng.ball.vel.length()
	assert_gt(strong_speed, weak_speed,
		"the two boots struck the same goal kick identically (%.2f vs %.2f)" % [strong_speed, weak_speed])
	# Determinism: the same keeper, the same seed, the same ball.
	var again := _staged(49.0, 900)
	again["eng"].keeper_clear(again["gk"], aim)
	assert_almost_eq(again["eng"].ball.vel.x, weak_eng.ball.vel.x, 1e-9,
		"the same seed struck a different ball in x")
	assert_almost_eq(again["eng"].ball.vel.y, weak_eng.ball.vel.y, 1e-9,
		"the same seed struck a different ball in y")

## A keeper at or above the league's mean lands the ball on his line, so the rule
## adds no draw to the match stream: the same strike costs the RNG exactly the
## clearances it always did. A weak boot pays two draws for its scatter.
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
	# And the ball still lands on its own line: the draws moved nothing across it.
	var gk = via_keeper["gk"]
	var landed: Vector2 = MatchKicking.landing(via_keeper["bars"], gk.pos, aim, 0.9, -0.7)
	var line: Vector2 = (aim - gk.pos).normalized()
	assert_almost_eq((landed - gk.pos).cross(line), 0.0, 1e-6,
		"a true boot's landing point moved across its line with the draws")
