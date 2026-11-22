extends SceneTree

## Chance-creation audit across seeds.
##   godot --headless --path . --script tools/probe_chances.gd -- [matches] [seed0]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := 10
	if args.size() > 0:
		n = int(args[0])
	var seed0 := 1000
	if args.size() > 1:
		seed0 = int(args[1])
	var fx := [["ARS", "NFO"], ["MUN", "MCI"], ["LIV", "CHE"], ["NEW", "TOT"], ["BHA", "CRY"]]
	var shots := 0
	var on_t := 0
	var goals := 0
	var xg := 0.0
	var corners := 0
	var offs := 0
	for i in range(n):
		var f: Array = fx[i % fx.size()]
		var eng := MatchEngine.new(seed0 + i, str(f[0]), str(f[1]))
		var guard := 0
		while eng.phase != "full_time" and guard < 60 * 60 * 400:
			if eng.phase == "half_time":
				eng.begin_second_half()
			eng.tick()
			guard += 1
		var s: int = int(eng.stats[0]["shots"]) + int(eng.stats[1]["shots"])
		var ot: int = int(eng.stats[0]["on_target"]) + int(eng.stats[1]["on_target"])
		var g: int = eng.score[0] + eng.score[1]
		var x: float = float(eng.stats[0]["xg"]) + float(eng.stats[1]["xg"])
		var c: int = int(eng.stats[0]["corners"]) + int(eng.stats[1]["corners"])
		var o: int = int(eng.stats[0]["offsides"]) + int(eng.stats[1]["offsides"])
		shots += s
		on_t += ot
		goals += g
		xg += x
		corners += c
		offs += o
		print("%s v %s s%d  %d-%d  shots %d  on %d  xG %.2f  corners %d  offsides %d" % [
			f[0], f[1], seed0 + i, eng.score[0], eng.score[1], s, ot, x, c, o])
	print("AVG: shots %.1f  on %.1f  goals %.2f  xG %.2f  corners %.1f  offsides %.1f  xG/shot %.3f" % [
		float(shots) / n, float(on_t) / n, float(goals) / n, xg / n, float(corners) / n, float(offs) / n,
		xg / maxf(1.0, float(shots))])
	quit()
