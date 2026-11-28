class_name LeagueShootout
extends RefCounted


static func settle(seed: int, home: String, away: String) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7717
	var score := [0, 0]
	var taken := [0, 0]
	var round_no := 0
	while true:
		var side: int = round_no % 2
		var conversion := conversion(home if side == 0 else away)
		if rng.randf() <= conversion:
			score[side] = int(score[side]) + 1
		taken[side] = int(taken[side]) + 1
		round_no += 1
		if taken[0] < 5 or taken[1] < 5:
			if int(score[0]) > int(score[1]) + (5 - int(taken[1])):
				break
			if int(score[1]) > int(score[0]) + (5 - int(taken[0])):
				break
		elif taken[0] == taken[1] and int(score[0]) != int(score[1]):
			break
	return Vector2i(int(score[0]), int(score[1]))


static func conversion(club_id: String) -> float:
	var team := TeamData.get_team(club_id)
	var best := 0.0
	for p in team.get("starters", []):
		var attrs: Dictionary = p.get("attr", {})
		best = maxf(best, float(attrs.get("sho", p.get("sho", 50))) * 1.4
			+ float(attrs.get("ovr", p.get("ovr", 50))))
	return clampf(0.60 + best / 260.0 * 0.30, 0.55, 0.92)
