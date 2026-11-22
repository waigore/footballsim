extends SceneTree
func _init() -> void:
	var eng := MatchEngine.new(1000)
	var guard := 0
	while eng.phase != "full_time" and guard < 60 * 60 * 110:
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		guard += 1
	print("score ", eng.score, " shots ", eng.stats[0]["shots"], "-", eng.stats[1]["shots"], " on target ", eng.stats[0]["on_target"], "-", eng.stats[1]["on_target"])
	print("shot buckets (5m): ", eng.shot_buckets)
	var goals := 0
	for e in eng.events:
		if e["type"] == "goal":
			goals += 1
	print("goals ", goals, "  saves ", eng.stats[0]["saves"], "-", eng.stats[1]["saves"])
	quit()
