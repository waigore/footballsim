class_name Commentary
extends RefCounted


static func _pick(rng, lines: Array, i: int = -1) -> String:
	if i >= 0:
		return lines[i % lines.size()]
	return lines[rng.randi_range(0, lines.size() - 1)]


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
		other_short: String, before_for: int, before_against: int, minute: int,
		penalty: bool = false) -> String:
	var after_for := before_for + 1
	var score := "%s %d-%d %s" % [team_short, after_for, before_against, other_short]
	if own_goal:
		return "OWN GOAL! %s turns it into his own net. %s." % [scorer, score]
	if penalty:
		return "PENALTY! %s scores from the spot — %s." % [scorer, score]
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


static func woodwork(rng, name: String, frame: String) -> String:
	if frame == "bar":
		return _pick(rng, [
			"OFF THE BAR! %s is denied by the woodwork!" % name,
			"%s beats the keeper and the crossbar saves him!" % name,
			"CRASHING OFF THE BAR! %s can't believe it!" % name,
		])
	return _pick(rng, [
		"OFF THE POST! %s is inches away!" % name,
		"%s beats the keeper — and the post!" % name,
		"THE POST! %s is denied by the width of a post!" % name,
	])


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


static func handball(rng, name: String, penalty: bool) -> String:
	if penalty:
		return _pick(rng, [
			"PENALTY! %s handles it in the box!" % name,
			"Spot kick! %s is punished for handball!" % name,
			"PENALTY — %s blocked that with his arm!" % name,
		])
	return _pick(rng, [
		"Handball by %s — free kick." % name,
		"%s handled that. Free kick given." % name,
		"%s's arm got in the way — free kick." % name,
	])
