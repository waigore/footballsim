extends SceneTree

## The witness for DR-20261126-22: how many staged wide-carrier geometries change
## the ball they play when the side's `crossing` lever moves from its low end to
## its high end. A full match produces about five crosses, which cannot resolve a
## preference at any sane n; a geometry sweep can.
##
##   godot --headless --path . --script res://tools/cross_choice_sweep.gd
##
## The shipped slope (`CROSS_PULL_SPAN` 2.0) changes ~91 of 375 cells; a flat pull
## changes 2, which is why the slope is fitted rather than assumed.

func _init() -> void:
	var differs := 0
	var cells := 0
	var low_cross := 0
	var high_cross := 0
	var sample: Array = []
	for cy in [0.05, 0.10, 0.15, 0.20, 0.25]:
		for cx in [0.62, 0.68, 0.74, 0.80, 0.86]:
			for my in [0.30, 0.40, 0.50, 0.60, 0.70]:
				for mx in [0.86, 0.90, 0.94]:
					var kinds: Array = []
					for level in [0.0, 1.0]:
						var eng := MatchEngine.new(770 + cells, "ENG-MUN1", "ENG-MCI1")
						eng.phase = "play"
						eng.possession_team = 0
						# Park the other side on its own byline, keeper in goal.
						for q in eng.players:
							if q.team == 1 and not q.is_gk:
								q.pos = Vector2(eng.L - 2.0, 2.0 + float(q.id % 60))
						var p = null
						for q in eng.players:
							if q.team == 0 and not q.is_gk:
								p = q
								break
						var mate = null
						for q in eng.players:
							if q.team == 0 and q.id != p.id and not q.is_gk:
								mate = q
								break
						p.pos = eng.to_world(0, Vector2(cx, cy))
						mate.pos = Vector2(eng.L * mx if eng.teams[0]["dir"] == 1 else eng.L * (1.0 - mx), eng.W * my)
						eng.ball.pos = p.pos
						eng.ball.owner_id = p.id
						eng.ball.vel = Vector2.ZERO
						var style: Dictionary = eng.style_of(0).duplicate()
						style["crossing"] = level
						eng.live_style[0] = style
						eng.brain.on_ball.reset_state()
						var choice: Dictionary = eng.brain.on_ball._best_pass(p, style)
						kinds.append(str(choice["kind"]))
					cells += 1
					if kinds[0] == "cross":
						low_cross += 1
					if kinds[1] == "cross":
						high_cross += 1
					if kinds[0] != kinds[1]:
						differs += 1
						if sample.size() < 6:
							sample.append("c=(%.2f,%.2f) m=(%.2f,%.2f) %s->%s" % [cx, cy, mx, my, kinds[0], kinds[1]])
	print("CELLS %d  cross@low=%d  cross@high=%d  CHOICE DIFFERS=%d" % [cells, low_cross, high_cross, differs])
	for s in sample:
		print("  ", s)
	quit()
