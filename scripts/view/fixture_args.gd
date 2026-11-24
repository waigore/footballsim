class_name FixtureArgs
extends RefCounted

## Command-line fixture flags (`--seed=`, `--home=`, `--away=`), parsed away from
## the scene controller so main.gd stays inside its P3 size ratchet.
##
## Unknown club codes are ignored rather than defaulting the fixture: a typo
## should leave the previous side in place, not silently kick off a derby.

static func parse(args: PackedStringArray, known: Array, defaults: Dictionary) -> Dictionary:
	var out := {
		"seed": int(defaults.get("seed", 1000)),
		"home": str(defaults.get("home", "MUN")),
		"away": str(defaults.get("away", "MCI")),
		"given": false,
	}
	for a in args:
		if a.begins_with("--seed="):
			out["seed"] = int(a.substr(7))
		elif a.begins_with("--home="):
			var h := a.substr(7).to_upper()
			if known.has(h):
				out["home"] = h
				out["given"] = true
		elif a.begins_with("--away="):
			var w := a.substr(7).to_upper()
			if known.has(w):
				out["away"] = w
				out["given"] = true
	return out
