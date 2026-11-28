extends SceneTree

## The witness for the aggression lever: what the same staged challenge does as a
## side's `aggression` bar moves. A full match yields ~10 fouls, which cannot
## resolve a style at any sane n; a staged duel sweep can, the same way
## `cross_choice_sweep.gd` resolves the cross preference.
##
##   godot --headless --path . --script res://tools/aggression_sweep.gd
##
## `MatchContact` leans both halves of the duel, so read both columns: a side
## higher on the bar must win more of the same challenge **and** give more of
## them away when it misses. A bar that raised only the wins would be a free
## upgrade, not a style.
##
## The duel is staged 25 m from the **carrier's** own goal — still outside the
## box, so a foul is a free kick rather than a penalty — because that is where
## `_attempt_tackle` prices a foul at its highest and the missed half can be read
## at a sane n. The win column does not depend on where the duel is.

const TRIALS := 3000
const LEVELS := [0.0, 0.48, 0.535, 0.62, 1.0]

func _init() -> void:
	print("aggression | won%  | fouls per 100 lost")
	for level in LEVELS:
		var eng := MatchEngine.new(4242, "ENG-MUN1", "ENG-MCI1")
		eng.phase = "play"
		eng.possession_team = 0
		var def = null
		for q in eng.players:
			if q.team == 1 and not q.is_gk:
				def = q
				break
		var carrier = null
		for q in eng.players:
			if q.team == 0 and not q.is_gk:
				carrier = q
				break
		var style: Dictionary = eng.style_of(1).duplicate()
		style["aggression"] = level
		eng.live_style[1] = style
		var spot: Vector2 = eng.own_goal_pos(0) + Vector2(float(eng.teams[0]["dir"]) * 25.0, 0.0)
		var won := 0
		var fouls := 0
		for i in range(TRIALS):
			# The same challenge every time: 1.2 m apart, facing, level speed.
			carrier.pos = spot
			carrier.vel = Vector2.ZERO
			carrier.has_ball = true
			carrier.cooldown = 0.0
			carrier.sent_off = false
			def.pos = spot + Vector2(-float(eng.teams[0]["dir"]) * 1.2, 0.0)
			def.vel = Vector2.ZERO
			def.facing = Vector2(float(eng.teams[0]["dir"]), 0.0)
			def.cooldown = 0.0
			def.sent_off = false
			def.yellow = 0
			eng.ball.pos = spot
			eng.ball.owner_id = carrier.id
			eng.ball.vel = Vector2.ZERO
			eng.ball.shot_team = -1
			var t0: int = int(def.stats["tackles"])
			var f0: int = int(eng.stats[1]["fouls"])
			eng._attempt_tackle(def, carrier)
			won += int(def.stats["tackles"]) - t0
			fouls += int(eng.stats[1]["fouls"]) - f0
		var lost: int = TRIALS - won
		print("%.3f      | %.1f | %.2f" % [
			level, float(won) * 100.0 / float(TRIALS),
			float(fouls) * 100.0 / maxf(float(lost), 1.0)])
	quit(0)
