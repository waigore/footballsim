class_name CommentaryExtraTime
extends RefCounted

## The decider lane's words: extra time and the shootout. Split from Commentary
## so the regulation lines stay inside their size budget (RUB-P3-01).

static func _pick(rng, lines: Array) -> String:
	return lines[rng.randi_range(0, lines.size() - 1)]

static func extra_time(rng, short_a: String, short_b: String) -> String:
	return _pick(rng, [
		"Level after 90 — %s and %s go to extra time." % [short_a, short_b],
		"We are not done: extra time between %s and %s." % [short_a, short_b],
	])

static func extra_time_start(rng, short_a: String, short_b: String) -> String:
	return _pick(rng, [
		"Extra time under way.",
		"%s and %s go again, thirty minutes to settle it." % [short_a, short_b],
	])

static func extra_time_second(rng, short_a: String, short_b: String) -> String:
	return _pick(rng, [
		"Second period of extra time.",
		"Fifteen more minutes for %s and %s." % [short_a, short_b],
	])

static func extra_time_break() -> String:
	return "That is the end of the first period of extra time."

static func shootout_start(rng, short_a: String) -> String:
	return _pick(rng, [
		"Still level — penalties decide it. %s first." % short_a,
		"Level after extra time. The shootout starts with %s." % short_a,
	])

static func shootout_kick(rng, name: String, scored: bool) -> String:
	if scored:
		return _pick(rng, [
			"%s scores." % name,
			"Buried by %s." % name,
		])
	return _pick(rng, [
		"%s misses." % name,
		"Saved! %s is denied." % name,
	])

static func shootout_end(short_winner: String, score_a: int, score_b: int) -> String:
	return "%s win the shootout %d-%d." % [short_winner, score_a, score_b]

static func full_time_pens(rng, short_a: String, score_a: int, short_b: String, score_b: int,
		pens_a: int, pens_b: int) -> String:
	var short_pens: String = short_a if pens_a > pens_b else short_b
	return "Full time: %s %d-%d %s. %s win %d-%d on penalties." % [
		short_a, score_a, score_b, short_b,
		short_pens, maxi(pens_a, pens_b), mini(pens_a, pens_b),
	]
