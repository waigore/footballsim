class_name PLSimStats
extends RefCounted


const PLAYER_UPSERT := (
	"INSERT INTO sim_player_stat (player_id, apps, minutes, goals, assists, shots, passes, "
	+ "passes_ok, tackles, saves, yellow, red, rating_sum, updated_at) "
	+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
	+ "ON CONFLICT(player_id) DO UPDATE SET apps = apps + excluded.apps, "
	+ "minutes = minutes + excluded.minutes, goals = goals + excluded.goals, "
	+ "assists = assists + excluded.assists, shots = shots + excluded.shots, "
	+ "passes = passes + excluded.passes, passes_ok = passes_ok + excluded.passes_ok, "
	+ "tackles = tackles + excluded.tackles, saves = saves + excluded.saves, "
	+ "yellow = yellow + excluded.yellow, red = red + excluded.red, "
	+ "rating_sum = rating_sum + excluded.rating_sum, updated_at = excluded.updated_at;"
)

const CLUB_UPSERT := (
	"INSERT INTO sim_club_stat (club_id, played, won, drawn, lost, gf, ga, points, updated_at) "
	+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) "
	+ "ON CONFLICT(club_id) DO UPDATE SET played = played + excluded.played, "
	+ "won = won + excluded.won, drawn = drawn + excluded.drawn, lost = lost + excluded.lost, "
	+ "gf = gf + excluded.gf, ga = ga + excluded.ga, points = points + excluded.points, "
	+ "updated_at = excluded.updated_at;"
)


static func rating(stats: Dictionary) -> float:
	var r := 6.0
	r += float(stats.get("goals", 0)) * 1.2 + float(stats.get("assists", 0)) * 0.7
	r += float(stats.get("shots", 0)) * 0.12 + float(stats.get("passes_ok", 0)) * 0.006
	r += float(stats.get("tackles", 0)) * 0.12 - float(stats.get("fouls", 0)) * 0.05
	return clampf(r, 4.0, 10.0)


static func player_line(player, club_id: String, minutes: int = 90) -> Dictionary:
	var stats: Dictionary = player.stats
	return {
		"player_id": str(player.key),
		"club_id": club_id,
		"minutes": minutes,
		"goals": int(stats.get("goals", 0)),
		"assists": int(stats.get("assists", 0)),
		"shots": int(stats.get("shots", 0)),
		"passes": int(stats.get("passes", 0)),
		"passes_ok": int(stats.get("passes_ok", 0)),
		"tackles": int(stats.get("tackles", 0)),
		"saves": int(stats.get("saves", 0)),
		"yellow": int(player.yellow),
		"red": 1 if player.red else 0,
		"rating": rating(stats),
	}


static func record_match(engine) -> bool:
	var lines: Array = []
	for p in engine.appeared:
		if str(p.key) == "":
			continue
		lines.append(player_line(p, str(engine.teams[p.team]["id"]), 90))
	var ok := record({
		"home": str(engine.teams[0]["id"]),
		"away": str(engine.teams[1]["id"]),
		"score": [engine.score[0], engine.score[1]],
		"players": lines,
	})


	if ok and LeagueSeason.active != null:
		LeagueSeason.engine_finished(engine)
	return ok


static func record(summary: Dictionary) -> bool:
	var players: Array = summary.get("players", [])
	if players.is_empty():
		return false
	var stamp := Time.get_datetime_string_from_system(true, true)
	if not PLDatabase.transaction("BEGIN TRANSACTION;"):
		return false
	for line in players:
		PLDatabase.execute(
			PLAYER_UPSERT,
			[
				str(line.get("player_id", "")), 1, int(line.get("minutes", 90)),
				int(line.get("goals", 0)), int(line.get("assists", 0)), int(line.get("shots", 0)),
				int(line.get("passes", 0)), int(line.get("passes_ok", 0)),
				int(line.get("tackles", 0)), int(line.get("saves", 0)),
				int(line.get("yellow", 0)), int(line.get("red", 0)),
				float(line.get("rating", 6.0)), stamp,
			],
		)
	for side in [[summary.get("home", ""), 0], [summary.get("away", ""), 1]]:
		var club_id := str(side[0])
		var goals := int(summary.get("score", [0, 0])[int(side[1])])
		var other := int(summary.get("score", [0, 0])[1 - int(side[1])])
		PLDatabase.execute(
			CLUB_UPSERT,
			[
				club_id, 1, 1 if goals > other else 0, 1 if goals == other else 0,
				1 if goals < other else 0, goals, other, 3 if goals > other else (1 if goals == other else 0),
				stamp,
			],
		)
	PLDatabase.transaction("COMMIT;")
	PLRepository.shared().invalidate()
	return true


static func clear() -> void:
	PLDatabase.execute("DELETE FROM sim_player_stat;")
	PLDatabase.execute("DELETE FROM sim_club_stat;")
	PLRepository.shared().invalidate()
