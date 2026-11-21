extends SceneTree

func _init() -> void:
	var eng := MatchEngine.new(1000)
	eng.verbose = true
	var goals := 0
	for i in range(60 * 60 * 20):
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		if eng.phase == "full_time":
			break
	quit()
