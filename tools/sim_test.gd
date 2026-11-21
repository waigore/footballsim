extends SceneTree

## Headless match harness:  godot --headless --path . --script tools/sim_test.gd -- 3

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := 3
	if args.size() > 0:
		n = int(args[0])
	var seed0 := 1000
	if args.size() > 1:
		seed0 = int(args[1])
	var totals := {
		"goals": 0.0, "shots": 0.0, "on_target": 0.0, "passes": 0.0, "pass_pct": 0.0,
		"fouls": 0.0, "offsides": 0.0, "corners": 0.0, "saves": 0.0, "cards": 0.0,
	}
	for i in range(n):
		var eng := MatchEngine.new(seed0 + i)
		var t0 := Time.get_ticks_msec()
		var guard := 0
		var max_ticks := int(60 * 60 * 125)
		while eng.phase != "full_time" and guard < max_ticks:
			if eng.phase == "half_time":
				eng.begin_second_half()
			eng.tick()
			guard += 1
		var ms := Time.get_ticks_msec() - t0
		var sc: Array = eng.score
		var s0: Dictionary = eng.stats[0]
		var s1: Dictionary = eng.stats[1]
		var pp: Vector2 = eng.possession_pct()
		var pass_pct0: float = 0.0 if s0["passes"] == 0 else 100.0 * s0["passes_ok"] / s0["passes"]
		var pass_pct1: float = 0.0 if s1["passes"] == 0 else 100.0 * s1["passes_ok"] / s1["passes"]
		print("--- match %d seed %d | %.1fs sim in %dms | %d ticks" % [i + 1, seed0 + i, eng.clock / 60.0, ms, guard])
		print("  score %d-%d   shots %d-%d (on target %d-%d)  xG %.2f-%.2f" % [sc[0], sc[1], s0["shots"], s1["shots"], s0["on_target"], s1["on_target"], s0["xg"], s1["xg"]])
		print("  possession %.1f-%.1f  passes %d-%d (%.0f%%/%.0f%%)  saves %d-%d" % [pp.x, pp.y, s0["passes"], s1["passes"], pass_pct0, pass_pct1, s0["saves"], s1["saves"]])
		print("  fouls %d-%d  offsides %d-%d  corners %d-%d  cards %d-%d" % [s0["fouls"], s1["fouls"], s0["offsides"], s1["offsides"], s0["corners"], s1["corners"], s0["yellow"] + s0["red"], s1["yellow"] + s1["red"]])
		var goal_lines := []
		for ev in eng.events:
			if ev["type"] == "goal":
				goal_lines.append("%d' %s" % [ev["minute"], ev["text"]])
		for l in goal_lines:
			print("  GOAL ", l)
		totals["goals"] += sc[0] + sc[1]
		totals["shots"] += s0["shots"] + s1["shots"]
		totals["on_target"] += s0["on_target"] + s1["on_target"]
		totals["passes"] += s0["passes"] + s1["passes"]
		totals["pass_pct"] += (pass_pct0 + pass_pct1) * 0.5
		totals["fouls"] += s0["fouls"] + s1["fouls"]
		totals["offsides"] += s0["offsides"] + s1["offsides"]
		totals["corners"] += s0["corners"] + s1["corners"]
		totals["saves"] += s0["saves"] + s1["saves"]
		totals["cards"] += s0["yellow"] + s0["red"] + s1["yellow"] + s1["red"]
	print("\n=== AVERAGES over %d matches ===" % n)
	for k in totals.keys():
		print("  %-10s %.2f" % [k, totals[k] / n])
	quit()
