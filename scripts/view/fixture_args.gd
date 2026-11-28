class_name FixtureArgs
extends RefCounted


static func parse(args: PackedStringArray, known: Array, defaults: Dictionary) -> Dictionary:
	var out := {
		"seed": int(defaults.get("seed", 1000)),
		"home": str(defaults.get("home", "ENG-MUN1")),
		"away": str(defaults.get("away", "ENG-MCI1")),
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
