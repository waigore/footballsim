extends SceneTree
func _init() -> void:
	var eng := MatchEngine.new(1700)
	eng.verbose = true
	var guard := 0
	while eng.phase != "full_time" and guard < 60 * 60 * 96:
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		guard += 1
	print("score ", eng.score)
	quit()
