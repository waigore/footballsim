extends SceneTree

func _init() -> void:
	var eng := MatchEngine.new(1001)
	var owner_ticks := 0
	var loose_ticks := 0
	var phases := {}
	var ev_counts := {}
	var ticks := 7200
	for i in range(ticks):
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		phases[eng.phase] = phases.get(eng.phase, 0) + 1
		if eng.ball.owner_id >= 0:
			owner_ticks += 1
		else:
			loose_ticks += 1
		if i % 300 == 0:
			var near := 0
			for p in eng.players:
				if p.pos.distance_to(eng.ball.pos) < 8.0:
					near += 1
			print("%5.1fs phase=%-8s owner=%3d ball=(%5.1f,%5.1f) z=%.1f speed=%4.1f near=%2d score=%s" % [eng.clock, eng.phase, eng.ball.owner_id, eng.ball.pos.x, eng.ball.pos.y, eng.ball.z, eng.ball.vel.length(), near, str(eng.score)])
	for e in eng.events:
		ev_counts[e["type"]] = ev_counts.get(e["type"], 0) + 1
	print("owner ticks %d / %d (%.0f%%)" % [owner_ticks, ticks, 100.0 * owner_ticks / ticks])
	print("events: ", ev_counts)
	print("shots %d-%d passes %d-%d passok %d-%d fouls %d-%d offsides %d-%d corners %d-%d" % [
		eng.stats[0]["shots"], eng.stats[1]["shots"], eng.stats[0]["passes"], eng.stats[1]["passes"],
		eng.stats[0]["passes_ok"], eng.stats[1]["passes_ok"], eng.stats[0]["fouls"], eng.stats[1]["fouls"],
		eng.stats[0]["offsides"], eng.stats[1]["offsides"], eng.stats[0]["corners"], eng.stats[1]["corners"]])
	print("remaining passes in flight? ball pos ", eng.ball.pos, " vel ", eng.ball.vel)
	quit()
