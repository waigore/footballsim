class_name CommentaryLive
extends RefCounted

## Filler lines when no fresh event has fired: possession, ball zone, pressure
## and, late on, the scoreline. Split from Commentary so the in-play event voice
## stays inside its size budget (RUB-P3-01).

## One line from a set. `i >= 0` takes that variant deterministically — the
## live line must not disturb the sim — and otherwise the match RNG chooses.
static func _pick(rng, lines: Array, i: int = -1) -> String:
	if i >= 0:
		return lines[i % lines.size()]
	return lines[rng.randi_range(0, lines.size() - 1)]


static func _lane(e, t: int, pos: Vector2) -> String:
	var ax: float = e.attacking_x(t, pos)
	if absf(pos.y - 34.0) > 17.0:
		if ax > 60.0:
			return "out wide in the final third"
		return "out on the flank"
	if ax > 88.0:
		return "right on the edge of the box"
	if ax > 70.0:
		return "in the final third"
	if ax > 45.0:
		return "in midfield"
	if ax > 24.0:
		return "in their own half"
	return "deep"


static func _scoreline(e) -> String:
	return "%s %d-%d %s" % [e.teams[0]["data"]["short"], e.score[0], e.score[1], e.teams[1]["data"]["short"]]


## A truthful description of the current picture, for when no fresh event has
## fired: possession, ball zone, pressure and, late on, the scoreline.
static func live(e) -> String:
	var t: int = e.possession_team
	var tn: String = e.teams[t]["data"]["short"]
	var on: String = e.teams[1 - t]["data"]["short"]
	if e.phase == "restart":
		var k: String = str(e.restart.get("type", ""))
		if k == "penalty":
			return "Penalty for %s. The ground holds its breath." % tn
		if k == "corner":
			return "Corner for %s — bodies arriving in the box." % tn
		if k == "throw_in":
			return "%s to restart from the touchline." % tn
		if k == "goal_kick":
			return "Goal kick for %s." % tn
		if k == "kickoff":
			return "%s lined up to get us going." % tn
		return "%s over a free kick." % tn
	var owner = e.ball_owner()
	var where := _lane(e, t, e.ball.pos)
	var i: int = int(e.clock * 0.4) % 3
	if owner != null and owner.is_gk:
		return "%s work it out from the back through the keeper." % tn
	if owner != null:
		var pu: float = e.pressure_on(owner)
		var tail := ""
		if e.clock > 4500.0 and e.score[0] != e.score[1]:
			tail = "  %s." % _scoreline(e)
		if pu >= 0.6:
			return _pick(null, [
				"%s snap at %s %s." % [on, owner.name, where],
				"%s is hounded %s by %s." % [owner.name, where, on],
				"%s press hard and %s has nowhere to go." % [on, owner.name],
			], i) + tail
		return _pick(null, [
			"%s carries it %s for %s." % [owner.name, where, tn],
			"%s keep it patient %s." % [tn, where],
			"%s build %s through %s." % [tn, where, owner.name],
		], i) + tail
	var tail2 := ""
	if e.clock > 4500.0 and e.score[0] != e.score[1]:
		tail2 = "  %s." % _scoreline(e)
	return _pick(null, [
		"Loose ball %s — both sides scrapping for it." % where,
		"Scrappy stuff %s — nobody in control." % where,
		"It's pinball %s." % where,
	], i) + tail2
