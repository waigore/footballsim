extends SceneTree

## The witness for the keeper's KICKING bar: where the same staged goal kick
## lands as the keeper's boot moves. A full match gives a handful of keeper long
## balls, which cannot resolve a rating at any sane n; a staged goal kick can,
## the same way `aggression_sweep.gd` resolves the challenge and
## `cross_choice_sweep.gd` resolves the cross.
##
##   godot --headless --path . --script res://tools/kicking_sweep.gd
##
## Two columns, because `MatchKicking` reads both halves of the same ball:
##
##   travel  — metres the punt carries from the goal-kick spot (a strong boot
##             puts it past the target the engine asks for, a weak one drops it
##             short of it);
##   off     — metres the ball lands off its own line (a boot at or above the
##             league's mean lands it true, exactly as the engine always did).
##
## The kick is staged on the real goal-kick spot and line, and the landing point
## is read through the same pure module the engine calls, with the seed's own
## draws — the rule reads only the keeper's rating, so the geometry can be fixed.

const TRIALS := 400
const LEVELS := [44.0, 49.0, 56.0, 64.75, 70.0, 79.0]

func _init() -> void:
	print("kicking | travel m | off-line m | line err")
	for level in LEVELS:
		var eng := MatchEngine.new(4242, "ENG-MUN1", "ENG-MCI1")
		eng.phase = "play"
		var gk = eng._gk_of(0)
		var bars: Dictionary = gk.gk.duplicate()
		bars["kic"] = level
		var dir: float = float(eng.teams[0]["dir"])
		gk.pos = Vector2(5.5 if dir == 1 else eng.L - 5.5, eng.W * 0.5)
		var aim: Vector2 = Vector2(eng.L * 0.5 + dir * 12.0, eng.W * 0.5)
		var travel := 0.0
		var off := 0.0
		for i in range(TRIALS):
			var landing: Vector2 = MatchKicking.landing(bars, gk.pos, aim,
				eng.rng.randf_range(-1.0, 1.0), eng.rng.randf_range(-1.0, 1.0))
			var line: Vector2 = (aim - gk.pos).normalized()
			var rel: Vector2 = landing - gk.pos
			travel += rel.dot(line)
			off += absf(rel.cross(line))
		travel /= float(TRIALS)
		off /= float(TRIALS)
		print("%5.2f   | %6.2f   | %6.2f     | %.2f deg" % [
			level, travel, off, rad_to_deg(atan2(off, maxf(travel, 0.01)))])
	quit()
