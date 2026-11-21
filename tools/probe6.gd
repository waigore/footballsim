extends SceneTree
func _init() -> void:
	var eng := MatchEngine.new(1000)
	var guard := 0
	while eng.phase != "full_time" and guard < 60 * 60 * 40:
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		guard += 1
	print("score ", eng.score, "  clock ", eng.clock / 60.0)
	print("shot distance buckets (5m): ", eng.shot_buckets)
	for g in eng.gk_debug:
		print("  ", g)
	quit()
