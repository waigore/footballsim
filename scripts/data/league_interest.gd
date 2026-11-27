class_name LeagueInterest
extends RefCounted


var save: LeagueSave = null

func _init(owner: LeagueSave) -> void:
	save = owner


func interests() -> Array:
	save.ensure_open()
	var out: Array = []
	for row in PLDatabase.rows(
		"SELECT i.club_id FROM league_interest i JOIN club c ON c.id = i.club_id ORDER BY c.name;"):
		out.append(str(row["club_id"]))
	return out

func is_interested(club_id: String) -> bool:
	save.ensure_open()
	return not PLDatabase.row(
		"SELECT club_id FROM league_interest WHERE club_id = ?;", [club_id]).is_empty()


func has_club(club_id: String) -> bool:
	save.ensure_open()
	return not PLDatabase.row("SELECT id FROM club WHERE id = ?;", [club_id]).is_empty()


func set_interest(club_id: String, follow: bool) -> bool:
	save.ensure_open()
	if follow:
		if not PLDatabase.execute(
			"INSERT INTO league_interest (club_id) VALUES (?) ON CONFLICT(club_id) DO NOTHING;",
			[club_id],
		):
			return false
		force_watch()
		return true
	PLDatabase.execute("DELETE FROM league_interest WHERE club_id = ?;", [club_id])
	release_watch(club_id)
	return true


func force_watch() -> bool:
	save.ensure_open()
	return PLDatabase.execute(
		"UPDATE league_fixture SET watched = 1 WHERE status <> 'played' AND watched = 0 "
		+ "AND (home_club_id IN (SELECT club_id FROM league_interest) "
		+ "OR away_club_id IN (SELECT club_id FROM league_interest));")


func release_watch(club_id: String) -> bool:
	save.ensure_open()
	return PLDatabase.execute(
		"UPDATE league_fixture SET watched = 0 WHERE status <> 'played' AND watched = 1 "
		+ "AND (home_club_id = ? OR away_club_id = ?) "
		+ "AND home_club_id NOT IN (SELECT club_id FROM league_interest) "
		+ "AND away_club_id NOT IN (SELECT club_id FROM league_interest);",
		[club_id, club_id])


func holds(fixture_id: String) -> bool:
	save.ensure_open()
	return not PLDatabase.row(
		"SELECT f.id FROM league_fixture f WHERE f.id = ? AND ("
		+ "f.home_club_id IN (SELECT club_id FROM league_interest) OR "
		+ "f.away_club_id IN (SELECT club_id FROM league_interest));", [fixture_id]).is_empty()
