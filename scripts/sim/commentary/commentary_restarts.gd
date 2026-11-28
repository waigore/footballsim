class_name CommentaryRestarts
extends RefCounted


static func _pick(rng: Variant, lines: Array) -> String:
	return lines[rng.randi_range(0, lines.size() - 1)]


static func kickoff(rng: Variant, team_name: String) -> String:
	return _pick(rng, [
		"We're underway — %s get us started." % team_name,
		"Kick-off! %s to get us going." % team_name,
	])


static func restart(rng: Variant, kind: String, team_short: String, taker: String,
		waiting: bool) -> String:
	if waiting:
		match kind:
			"corner":
				return _pick(rng, [
					"%s are in no rush — waiting for the box to fill." % team_short,
					"%s hold the corner back, bodies still arriving." % team_short,
				])
			"free_kick":
				return _pick(rng, [
					"%s take their time, letting the wall set." % team_short,
					"%s wait for runners before playing this." % team_short,
				])
			_:
				return _pick(rng, [
					"%s are still organising." % team_short,
					"%s wait for support." % team_short,
				])
	match kind:
		"throw_in":
			return _pick(rng, [
				"Throw-in to %s." % team_short,
				"%s restart from the touchline." % team_short,
			])
		"corner":
			return _pick(rng, [
				"Corner to %s — the big men are on their way up." % team_short,
				"Corner kick, %s. Plenty in the box." % team_short,
			])
		"goal_kick":
			if taker != "":
				return _pick(rng, [
					"Goal kick, %s." % taker,
					"%s to restart from his own six-yard box." % taker,
				])
			return "Goal kick, %s." % team_short
		"free_kick":
			return _pick(rng, [
				"Free kick to %s." % team_short,
				"%s have a free kick here." % team_short,
			])
		"penalty":
			return _pick(rng, [
				"PENALTY to %s!" % team_short,
				"%s have a penalty!" % team_short,
			])
	return "Restart to %s." % team_short


static func half_time(rng: Variant, short_a: String, score_a: int, short_b: String,
		score_b: int) -> String:
	return _pick(rng, [
		"Half-time: %s %d-%d %s." % [short_a, score_a, score_b, short_b],
		"That's the half-time whistle — %s %d, %s %d." % [short_a, score_a, short_b, score_b],
	])


static func full_time(rng: Variant, short_a: String, score_a: int, short_b: String,
		score_b: int) -> String:
	var tail := ""
	if score_a == score_b:
		tail = " Honours even."
	elif score_a > score_b:
		tail = " %s take it." % short_a
	else:
		tail = " %s take it." % short_b
	return "Full time: %s %d-%d %s.%s" % [short_a, score_a, score_b, short_b, tail]


static func penalty_taken(rng: Variant, name: String) -> String:
	return _pick(rng, [
		"%s steps up..." % name,
		"%s places the ball. Big moment." % name,
	])
