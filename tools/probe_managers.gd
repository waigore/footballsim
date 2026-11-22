extends SceneTree

## Calibration probe for in-match managers. Plays whole matches headless and
## reports the managerial record: tactics changes per side (target ~2–3), the
## substitutions and windows used, and the decision log. Run with:
##   godot --headless --path . --script res://tools/probe_managers.gd

func _init() -> void:
	var seeds := [1001, 1002, 1003]
	for s in seeds:
		var eng := MatchEngine.new(s, "MUN", "MCI")
		var guard := 0
		var max_ticks := int(60.0 * 60.0 * 125.0)
		var started := Time.get_ticks_msec()
		while eng.phase != "full_time" and guard < max_ticks:
			if eng.phase == "half_time":
				eng.begin_second_half()
			eng.tick()
			guard += 1
		var secs := (Time.get_ticks_msec() - started) / 1000.0
		print("=== seed %d: %s %d-%d %s (%.1fs, %d ticks) ===" % [
			s, eng.teams[0]["data"]["short"], eng.score[0], eng.score[1],
			eng.teams[1]["data"]["short"], secs, guard])
		print("  shots %d-%d onTarget %d-%d xG %.2f-%.2f" % [
			int(eng.stats[0]["shots"]), int(eng.stats[1]["shots"]),
			int(eng.stats[0]["on_target"]), int(eng.stats[1]["on_target"]),
			float(eng.stats[0]["xg"]), float(eng.stats[1]["xg"])])
		for t in range(2):
			var tact: int = int(eng.manager.changes[t])
			print("  %s %s: tactics=%d subs=%d/%d windows=%d/%d latest=%s" % [
				eng.teams[t]["data"]["short"], eng.manager.manager_name(t), tact,
				int(eng.teams[t]["subs_made"]), MatchEngine.SUB_LIMIT,
				int(eng.teams[t]["windows_used"]), MatchEngine.SUB_WINDOWS,
				str(eng.manager.tactics_for(t).describe())])
		for d in eng.manager.decisions:
			print("    %2d' %s %s: %s" % [int(d["minute"]), eng.teams[int(d["team"])]["data"]["short"],
				str(d["kind"]), str(d["text"])])
		var snap: Dictionary = eng.to_dict()
		var replay := MatchEngine.new(s, "MUN", "MCI")
		replay.from_dict(snap)
		var same: bool = str(replay.manager.tactics_for(0).to_dict()) == str(eng.manager.tactics_for(0).to_dict())
		print("  snapshot round-trip tactics: %s" % str(same))
	quit()
