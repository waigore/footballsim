extends SceneTree


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var home: String = a[0] if a.size() > 0 else "MCI"
	var away: String = a[1] if a.size() > 1 else "IPS"
	var n: int = int(a[2]) if a.size() > 2 else 4
	var seed0: int = int(a[3]) if a.size() > 3 else 1000
	var model := PoissonModel.new(seed0, home, away)
	var goal_h: Array = []
	var goal_a: Array = []
	var shots_h := 0
	var shots_a := 0
	var ot_h := 0
	var ot_a := 0
	var xg_h := 0.0
	var xg_a := 0.0
	for i in range(n):
		var eng := MatchEngine.new(seed0 + i * 13, home, away)
		var guard := 0
		while eng.phase != "full_time" and guard < 60 * 60 * 400:
			if eng.phase == "half_time":
				eng.begin_second_half()
			eng.tick()
			guard += 1
		var s0: Dictionary = eng.stats[0]
		var s1: Dictionary = eng.stats[1]
		goal_h.append(eng.score[0])
		goal_a.append(eng.score[1])
		shots_h += int(s0["shots"])
		shots_a += int(s1["shots"])
		ot_h += int(s0["on_target"])
		ot_a += int(s1["on_target"])
		xg_h += float(s0["xg"])
		xg_a += float(s1["xg"])
		print("M %d %d %d %.2f %.2f %d %d" % [seed0 + i * 13, eng.score[0], eng.score[1],
			float(s0["xg"]), float(s1["xg"]), int(s0["on_target"]), int(s1["on_target"])])
	var mh := _mean(goal_h)
	var ma := _mean(goal_a)
	var vh := _var(goal_h, mh)
	var va := _var(goal_a, ma)
	print("SUMMARY %s v %s n=%d  goals %.2f-%.2f (λ %.2f-%.2f)  var %.2f-%.2f  xG %.2f-%.2f  shots %.1f-%.1f  onTarget %.2f-%.2f" % [
		home, away, n, mh, ma, model.lambda_home, model.lambda_away, vh, va,
		xg_h / n, xg_a / n, float(shots_h) / n, float(shots_a) / n, float(ot_h) / maxf(1.0, shots_h), float(ot_a) / maxf(1.0, shots_a)])
	print("DELTA mean_h %+.1f%%  mean_a %+.1f%%  var_h %+.1f%%  var_a %+.1f%%" % [
		(mh - model.lambda_home) / model.lambda_home * 100.0, (ma - model.lambda_away) / model.lambda_away * 100.0,
		(vh - model.lambda_home) / model.lambda_home * 100.0, (va - model.lambda_away) / model.lambda_away * 100.0])
	quit()

func _mean(xs: Array) -> float:
	var t := 0.0
	for x in xs:
		t += float(x)
	return t / maxf(float(xs.size()), 1.0)

func _var(xs: Array, mean: float) -> float:
	if xs.size() < 2:
		return 0.0
	var t := 0.0
	for x in xs:
		t += (float(x) - mean) * (float(x) - mean)
	return t / float(xs.size() - 1)
