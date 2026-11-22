extends SceneTree

func _init() -> void:
	var eng := MatchEngine.new(1001)
	eng.verbose = true
	for i in range(60 * 25):
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		if i % 120 == 0:
			var near := 999.0
			var near_name := "-"
			for p in eng.players:
				var d: float = p.pos.distance_to(eng.ball.pos)
				if d < near:
					near = d
					near_name = p.name
			print("STATE t=%.0f phase=%s ball=(%.1f,%.1f) vel=%.1f near=%s %.1fm owner=%d" % [eng.clock, eng.phase, eng.ball.pos.x, eng.ball.pos.y, eng.ball.vel.length(), near_name, near, eng.ball.owner_id])
	quit()
