class_name CommentaryBench
extends RefCounted

## Bench and touchline lines: injuries, substitutions and tactics tweaks.
## Split from Commentary so the in-play event voice stays inside its size
## budget (RUB-P3-01).

static func _pick(rng: RandomNumberGenerator, lines: Array) -> String:
	return lines[rng.randi_range(0, lines.size() - 1)]


## `continues` is false when the side has no change left to make.
static func injury(rng: RandomNumberGenerator, name: String, continues: bool) -> String:
	if continues:
		return _pick(rng, [
			"%s is down and can't continue — a change is coming." % name,
			"%s pulls up. He signals to the bench." % name,
			"%s looks in trouble — the stretcher is on." % name,
		])
	return _pick(rng, [
		"%s can't continue and there's no change left — they're down to ten." % name,
		"%s hobbles off. No substitutions remaining." % name,
	])


static func substitution(rng: RandomNumberGenerator, team_short: String, on_name: String,
		off_name: String, manager: String = "") -> String:
	if manager != "":
		return _pick(rng, [
			"%s sends on %s for %s." % [manager, on_name, off_name],
			"%s makes his move — %s replaces %s." % [manager, on_name, off_name],
			"%s turns to the bench: %s on for %s." % [manager, on_name, off_name],
		])
	return _pick(rng, [
		"Change for %s: %s on for %s." % [team_short, on_name, off_name],
		"%s make a change — %s replaces %s." % [team_short, on_name, off_name],
	])


## Manager tinkering: one short line naming the manager and what moved.
static func tactics(rng: RandomNumberGenerator, manager: String, _team_short: String,
		changes: Array) -> String:
	var what := _brief(changes)
	return _pick(rng, [
		"%s signals a change — %s." % [manager, what],
		"%s adjusts it: %s." % [manager, what],
		"%s has seen enough — %s." % [manager, what],
		"%s tweaks it from the touchline: %s." % [manager, what],
	])


static func _brief(changes: Array) -> String:
	var out := ""
	for i in range(mini(3, changes.size())):
		out += ("" if out == "" else ", ") + str(changes[i])
	return "a shape change" if out == "" else out
