extends SceneTree

## Per-club reading of the manager `patience` lever: for each shipped club, the
## wait its own profile buys and the mean tactics changes a side makes over the
## same seeded timelines the managers suite replays.
##
##   godot --headless --path . --script res://tools/patience_clubs.gd

const SEEDS := 40

func _init() -> void:
	var rows: Array = []
	for id in TeamData.team_ids():
		var prof: Dictionary = ManagerData.profile(id)
		var total := 0
		for i in range(SEEDS):
			total += int(_replay(i + 1, id))
		rows.append([str(id), float(prof.get("patience", 0.52)),
			MatchCadence.tactics_gap(prof), float(total) / float(SEEDS * 2)])
	for r in rows:
		print("%-5s patience=%.2f gap=%4.0fs changes/side=%.2f" % [r[0], r[1], r[2], r[3]])
	var sum := 0.0
	for r in rows:
		sum += float(r[3])
	print("LEAGUE mean changes/side = %.2f  (league mean gap %.0fs)" % [
		sum / float(rows.size()), _league_gap_mean(rows)])
	quit()

func _league_gap_mean(rows: Array) -> float:
	var s := 0.0
	for r in rows:
		s += float(r[2])
	return s / float(rows.size())

## Replay the managers suite's timeline with both sides carrying `club_id`'s
## profile, and return the total changes across both sides.
func _replay(seed_in: int, club_id: String) -> int:
	var eng := MatchEngine.new(seed_in)
	eng.phase = "play"
	for t in range(2):
		eng.manager.profiles[t] = ManagerData.profile(club_id)
	var goals := [0, 0]
	var r := RandomNumberGenerator.new()
	r.seed = seed_in
	var minute := 9
	for i in range(18):
		eng.clock = float(minute) * 60.0
		var t := r.randi_range(0, 1)
		if r.randf() < 0.60:
			goals[t] += 1
			eng.score[0] = int(goals[0])
			eng.score[1] = int(goals[1])
			eng.manager.on_event("goal", {"team": t})
		else:
			eng.manager.on_event("card", {"team": t, "red": r.randf() < 0.12})
		eng.manager.tick(60.0)
		minute += r.randi_range(3, 8)
	return int(eng.manager.changes[0]) + int(eng.manager.changes[1])
