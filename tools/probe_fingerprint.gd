extends SceneTree

## Throwaway probe: a behaviour fingerprint for seeded matches, plus wall clock.
## Compare with `diff` against an earlier run to prove a perf pass changed
## nothing but the clock.

const SEEDS := [1000, 1001, 1002]

func _init() -> void:
	for seed_in in SEEDS:
		var t0 := Time.get_ticks_msec()
		var eng := MatchEngine.new(seed_in, "MUN", "MCI")
		var guard := 0
		while eng.phase != "full_time" and guard < 60 * 60 * 400:
			if eng.phase == "half_time":
				eng.begin_second_half()
			eng.tick()
			guard += 1
		var ms := Time.get_ticks_msec() - t0
		var events: Array = []
		for e in eng.events:
			events.append("%s|%d|%s" % [str(e.get("kind", "")), int(e.get("minute", 0)), str(e.get("text", ""))])
		var stats := []
		for t in range(2):
			var side: Dictionary = eng.stats[t]
			var keys: Array = side.keys()
			keys.sort()
			var bits: Array = []
			for k in keys:
				bits.append("%s=%s" % [k, str(side[k])])
			stats.append(",".join(bits))
		var per_player: Array = []
		for p in eng.players:
			per_player.append("%s:%s:%s" % [p.key, str(p.stamina), str(p.stats)])
		print("SEED %d ms=%d score=%d-%d ticks=%d events=%d" % [seed_in, ms, eng.score[0], eng.score[1], guard, events.size()])
		print("  added=%s" % str(eng.added))
		print("  stats0=%s" % stats[0])
		print("  stats1=%s" % stats[1])
		print("  events=%s" % " ~ ".join(events))
		print("  players=%s" % " ~ ".join(per_player))
	quit()
