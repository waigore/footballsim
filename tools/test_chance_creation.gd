extends SceneTree

## Chance creation: a full match must produce a realistic shot and xG volume,
## with attacks no longer dying to avoidable offsides.
##   godot --headless --path . --script tools/test_chance_creation.gd

const FIXTURES := [["ARS", "NFO"], ["MUN", "MCI"], ["LIV", "CHE"]]
const SEED0 := 1000

func _init() -> void:
	var shots := 0.0
	var xg := 0.0
	var goals := 0.0
	var offs := 0.0
	var n := 0
	for i in range(FIXTURES.size()):
		var f: Array = FIXTURES[i]
		var eng := MatchEngine.new(SEED0 + i, str(f[0]), str(f[1]))
		var guard := 0
		while eng.phase != "full_time" and guard < 60 * 60 * 400:
			if eng.phase == "half_time":
				eng.begin_second_half()
			eng.tick()
			guard += 1
		var s: float = float(eng.stats[0]["shots"]) + float(eng.stats[1]["shots"])
		var x: float = float(eng.stats[0]["xg"]) + float(eng.stats[1]["xg"])
		shots += s
		xg += x
		goals += float(eng.score[0] + eng.score[1])
		offs += float(eng.stats[0]["offsides"]) + float(eng.stats[1]["offsides"])
		n += 1
		print("%s v %s s%d  %d-%d  shots %d  xG %.2f  offsides %d" % [
			f[0], f[1], SEED0 + i, eng.score[0], eng.score[1], int(s), x,
			int(eng.stats[0]["offsides"]) + int(eng.stats[1]["offsides"])])
	var avg_shots := shots / n
	var avg_xg := xg / n
	var avg_goals := goals / n
	var avg_offs := offs / n
	var per_shot := avg_xg / maxf(1.0, avg_shots)
	print("AVG: shots %.1f  xG %.2f  goals %.2f  offsides %.1f  xG/shot %.3f" % [
		avg_shots, avg_xg, avg_goals, avg_offs, per_shot])
	var fails := 0
	if avg_shots < 20.0:
		print("FAIL: too few shots")
		fails += 1
	if avg_shots > 42.0:
		print("FAIL: shot volume is arcade-high")
		fails += 1
	if avg_xg < 1.9:
		print("FAIL: too little xG for a full match")
		fails += 1
	if avg_goals < 1.5 or avg_goals > 4.6:
		print("FAIL: goal volume out of range")
		fails += 1
	if avg_offs > 9.0:
		print("FAIL: attacks still dying to avoidable offsides")
		fails += 1
	if per_shot < 0.05 or per_shot > 0.18:
		print("FAIL: xG per shot is not credible")
		fails += 1
	if fails == 0:
		print("PASS: chance creation")
	else:
		print("FAIL: %d chance-creation checks" % fails)
	quit()
