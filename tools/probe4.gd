extends SceneTree

func _init() -> void:
	var eng := MatchEngine.new(1000)
	var last_min := -1
	var guard := 0
	while eng.phase != "full_time" and guard < 60 * 60 * 130:
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		guard += 1
		var m := int(eng.clock / 60.0)
		if m != last_min and m % 10 == 0:
			last_min = m
			print("%3d' score %s shots %d-%d passes %d-%d fouls %d-%d cards %d-%d phase=%s ball=(%.1f,%.1f) taker-phase=%s" % [m, str(eng.score), eng.stats[0]["shots"], eng.stats[1]["shots"], eng.stats[0]["passes"], eng.stats[1]["passes"], eng.stats[0]["fouls"], eng.stats[1]["fouls"], eng.stats[0]["yellow"] + eng.stats[0]["red"], eng.stats[1]["yellow"] + eng.stats[1]["red"], eng.phase, eng.ball.pos.x, eng.ball.pos.y, str(eng.restart.get("type", "-"))])
	print("END clock %.1f min phase %s score %s" % [eng.clock / 60.0, eng.phase, str(eng.score)])
	var counts := {}
	for e in eng.events:
		counts[e["type"]] = counts.get(e["type"], 0) + 1
	print(counts)
	var goals := []
	for e in eng.events:
		if e["type"] == "goal":
			goals.append("%d %s" % [e["minute"], e["text"]])
	print("goals ", goals.size())
	for g in goals.slice(0, 30):
		print("   ", g)
	quit()
