class_name CommentaryBench
extends RefCounted


static func _pick(rng: Variant, lines: Array) -> String:
	return lines[rng.randi_range(0, lines.size() - 1)]


static func injury(rng: Variant, name: String, continues: bool) -> String:
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


static func substitution(rng: Variant, team_short: String, on_name: String,
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


static func tactics(rng: Variant, manager: String, _team_short: String,
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
