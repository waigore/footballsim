extends SceneTree

## Validates the expanded squad data: 20 clubs, 11 starters each, a bench keeper,
## and every starter role has a formation slot.

func _init() -> void:
	var ids: Array = TeamData.team_ids()
	ids.sort()
	print("clubs: %d" % ids.size())
	var bad := 0
	for id in ids:
		var t: Dictionary = TeamData.get_team(id)
		var starters: Array = t["starters"]
		var bench: Array = t["bench"]
		var bench_gk := 0
		for b in bench:
			if b["role"] == "GK":
				bench_gk += 1
		var missing_slot := []
		for s in starters:
			var slot: Vector2 = TeamData.formation_slot(t, s["role"])
			if slot == Vector2(0.3, 0.5) and s["role"] != "CM":
				missing_slot.append(s["role"])
		var ok: bool = starters.size() == 11 and bench_gk >= 1 and missing_slot.is_empty()
		if not ok:
			bad += 1
		print("  %-3s %-28s starters=%d bench=%d benchGK=%d %s" % [
			id, t["name"], starters.size(), bench.size(), bench_gk,
			"OK" if ok else "BAD slots=%s" % str(missing_slot)])
	print("bad clubs: %d" % bad)
	quit()
