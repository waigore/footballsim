extends SceneTree

## Market sandbox: godot --headless --path . --script res://tools/market_sim.gd -- season --seasons 3
## One verb per file under tools/market_sim/. Bullet the isolated-run gate for the market theme.

const VERBS := {
	"season": "res://tools/market_sim/season.gd",
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var verb := "season"
	var options := {}
	var i := 0
	if not args.is_empty() and not str(args[0]).begins_with("--"):
		verb = str(args[0])
		i = 1
	while i < args.size():
		var flag := str(args[i])
		if flag.begins_with("--"):
			var key := flag.substr(2)
			var value := "1"
			if i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
				value = str(args[i + 1])
				i += 1
			options[key] = value
		i += 1
	if not VERBS.has(verb):
		print("market_sim: unknown verb '%s' (verbs: %s)" % [verb, ", ".join(VERBS.keys())])
		quit(2)
		return
	var script: Script = load(str(VERBS[verb]))
	var result: Dictionary = script.run(options)
	print("market_sim %s: %s" % [verb, JSON.stringify(result)])
	quit(0 if bool(result.get("ok", false)) else 1)
