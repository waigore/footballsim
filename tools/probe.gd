extends SceneTree

func _init() -> void:
	var eng := MatchEngine.new(1001)
	var t0 := Time.get_ticks_msec()
	for i in range(3000):
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		if i % 500 == 0:
			print("tick %d  clock %.1f  phase %s  ball %s  owner %d  events %d  score %s" % [i, eng.clock, eng.phase, str(eng.ball.pos), eng.ball.owner_id, eng.events.size(), str(eng.score)])
	print("done 3000 ticks in %d ms" % (Time.get_ticks_msec() - t0))
	print("last events:")
	for j in range(max(0, eng.events.size() - 10), eng.events.size()):
		print("  ", eng.events[j]["minute"], eng.events[j]["type"], " ", eng.events[j]["text"])
	var sh: Dictionary = eng.stats[0]
	var sa: Dictionary = eng.stats[1]
	print("shots ", sh["shots"], "-", sa["shots"], " passes ", sh["passes"], "-", sa["passes"], " fouls ", sh["fouls"], "-", sa["fouls"])
	quit()
