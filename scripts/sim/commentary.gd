class_name Commentary
extends RefCounted

## Broadcast voice. Pure text helpers, no engine mutation: the engine calls them
## at the instant something happens so the log describes the pitch, and the HUD
## asks for a live line when nothing fresh has happened.
##
## Lines are kept under ~90 characters so the commentary panel never truncates
## mid-word, and every variant names a real player/team from the event.

static func _pick(rng, lines: Array) -> String:
	return lines[rng.randi_range(0, lines.size() - 1)]

## Deterministic variant for the live line (no RNG: it must not disturb the sim).
static func _variant(lines: Array, i: int) -> String:
	return lines[abs(i) % lines.size()]

## Distance phrasing for shots, relative to the goal being attacked.
static func _shot_range(dist: float) -> String:
	if dist < 10.0:
		return "from point-blank range"
	if dist < 18.0:
		return "from inside the box"
	if dist < 26.0:
		return "from the edge of the area"
	return "from range"

static func shot(rng, name: String, dist: float, xg: float, pressure: float, kind: String) -> String:
	var where := _shot_range(dist)
	if kind == "header":
		return _pick(rng, [
			"%s climbs highest and heads it %s!" % [name, where],
			"%s gets his head to it %s!" % [name, where],
			"%s meets it with his head %s!" % [name, where],
		])
	if xg >= 0.32:
		return _pick(rng, [
			"Big chance! %s pulls the trigger %s!" % [name, where],
			"%s is clean through — he shoots %s!" % [name, where],
			"Golden chance for %s %s!" % [name, where],
		])
	if pressure >= 0.6:
		return _pick(rng, [
			"%s digs out a shot %s!" % [name, where],
			"Snap shot from %s %s!" % [name, where],
			"%s shoots under pressure %s!" % [name, where],
		])
	return _pick(rng, [
		"%s lets fly %s!" % [name, where],
		"%s lines one up %s!" % [name, where],
		"%s tries his luck %s!" % [name, where],
		"%s strikes it %s!" % [name, where],
	])

## how: "hold", "parry" or "goal_line".
static func save(rng, gk: String, shooter: String, how: String, xg: float) -> String:
	var big: bool = xg >= 0.30
	var denied := "" if shooter == "" else " to deny %s" % shooter
	if how == "goal_line":
		return _pick(rng, [
			"INCREDIBLE! %s keeps it out on the line!" % gk,
			"Off the line! %s saves the day!" % gk,
			"How has %s kept that out?!" % gk,
		])
	if how == "parry":
		if big:
			return _pick(rng, [
				"Brilliant reflex stop from %s — parried!" % gk,
				"%s throws himself at it and beats it away!" % gk,
				"%s gets a strong hand to it%s!" % [gk, denied],
			])
		return _pick(rng, [
			"%s parries it away." % gk,
			"%s can't hold it — pushed clear." % gk,
			"Beaten away by %s." % gk,
		])
	if big:
		return _pick(rng, [
			"Huge save! %s stands tall%s." % [gk, denied],
			"Superb from %s — he holds it%s." % [gk, denied],
			"%s gets everything behind it%s!" % [gk, denied],
		])
	return _pick(rng, [
		"%s gathers it comfortably." % gk,
		"Routine stop for %s." % gk,
		"%s scoops it up." % gk,
	])

static func goal(rng, scorer: String, assist: String, own_goal: bool, team_short: String,
		other_short: String, before_for: int, before_against: int, minute: int) -> String:
	var after_for := before_for + 1
	var score := "%s %d-%d %s" % [team_short, after_for, before_against, other_short]
	if own_goal:
		return "OWN GOAL! %s turns it into his own net. %s." % [scorer, score]
	var open := _pick(rng, ["GOAL!", "IT'S IN!", "GOAL!", "IT'S THERE!"])
	var state := ""
	if after_for == before_against:
		state = " Level!"
	elif after_for > before_against:
		state = " %s lead!" % team_short
	if minute >= 88:
		state += " Late drama!"
	var line := "%s %s scores — %s." % [open, scorer, score]
	if state != "":
		line += state
	elif assist != "":
		line += " %s with the assist." % assist
	if line.length() > 90:
		line = "%s %s scores! %s." % [open, scorer, score]
	return line

static func block(rng, name: String, shooter: String) -> String:
	if shooter != "":
		return _pick(rng, [
			"Blocked! %s throws himself in front of %s." % [name, shooter],
			"%s gets in the way of %s' shot!" % [name, shooter],
		])
	return _pick(rng, ["Blocked by %s!" % name, "%s throws his body in the way!" % name])

static func foul(rng, fouler: String, victim: String, penalty: bool) -> String:
	if penalty:
		return _pick(rng, [
			"PENALTY! %s brings down %s in the box!" % [fouler, victim],
			"PENALTY! %s clatters into %s — spot kick!" % [fouler, victim],
			"PENALTY! The referee points to the spot after %s fells %s!" % [fouler, victim],
		])
	return _pick(rng, [
		"%s clips %s — free kick." % [fouler, victim],
		"Foul by %s on %s. Free kick." % [fouler, victim],
		"%s brings %s down. Free kick." % [fouler, victim],
	])

static func card(rng, name: String, kind: String) -> String:
	match kind:
		"yellow":
			return _pick(rng, [
				"Yellow card — %s goes into the book." % name,
				"%s is booked for that one." % name,
				"Yellow for %s." % name,
			])
		"red_second":
			return _pick(rng, [
				"Second yellow — %s is off!" % name,
				"%s sees yellow again and he's gone!" % name,
			])
		"red":
			return _pick(rng, [
				"RED CARD! %s is sent off!" % name,
				"%s is off — straight red!" % name,
			])
	return ""

static func kickoff(rng, team_name: String) -> String:
	return _pick(rng, [
		"We're underway — %s get us started." % team_name,
		"Kick-off! %s to get us going." % team_name,
	])

static func cross(rng, name: String) -> String:
	return _pick(rng, [
		"%s whips a cross into the box." % name,
		"%s hangs one up to the back post." % name,
		"%s drills it across the six-yard box!" % name,
		"%s clips it in — dangerous ball!" % name,
	])

static func clearance(rng, name: String, headed: bool) -> String:
	if headed:
		return _pick(rng, [
			"%s heads it clear." % name,
			"%s gets it away with his head." % name,
		])
	return _pick(rng, [
		"%s hoofs it clear." % name,
		"%s smashes it away." % name,
		"%s hooks it clear." % name,
	])

static func offside(rng, name: String) -> String:
	return _pick(rng, [
		"Flag's up — %s strayed offside." % name,
		"Offside against %s." % name,
		"%s went too early — offside." % name,
	])

static func substitution(rng, team_short: String, on_name: String, off_name: String) -> String:
	return _pick(rng, [
		"Change for %s: %s on for %s." % [team_short, on_name, off_name],
		"%s make a change — %s replaces %s." % [team_short, on_name, off_name],
	])

## Set-piece / restart line. `waiting` marks the taker holding play up for
## team-mates to arrive.
static func restart(rng, kind: String, team_short: String, taker: String, waiting: bool) -> String:
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

static func half_time(rng, short_a: String, score_a: int, short_b: String, score_b: int) -> String:
	return _pick(rng, [
		"Half-time: %s %d-%d %s." % [short_a, score_a, score_b, short_b],
		"That's the half-time whistle — %s %d, %s %d." % [short_a, score_a, short_b, score_b],
	])

static func full_time(rng, short_a: String, score_a: int, short_b: String, score_b: int) -> String:
	var tail := ""
	if score_a == score_b:
		tail = " Honours even."
	elif score_a > score_b:
		tail = " %s take it." % short_a
	else:
		tail = " %s take it." % short_b
	return "Full time: %s %d-%d %s.%s" % [short_a, score_a, score_b, short_b, tail]

static func penalty_taken(rng, name: String) -> String:
	return _pick(rng, [
		"%s steps up..." % name,
		"%s places the ball. Big moment." % name,
	])

# ------------------------------------------------------------------- live ----

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
			return _variant([
				"%s snap at %s %s." % [on, owner.name, where],
				"%s is hounded %s by %s." % [owner.name, where, on],
				"%s press hard and %s has nowhere to go." % [on, owner.name],
			], i) + tail
		return _variant([
			"%s carries it %s for %s." % [owner.name, where, tn],
			"%s keep it patient %s." % [tn, where],
			"%s build %s through %s." % [tn, where, owner.name],
		], i) + tail
	var tail2 := ""
	if e.clock > 4500.0 and e.score[0] != e.score[1]:
		tail2 = "  %s." % _scoreline(e)
	return _variant([
		"Loose ball %s — both sides scrapping for it." % where,
		"Scrappy stuff %s — nobody in control." % where,
		"It's pinball %s." % where,
	], i) + tail2
