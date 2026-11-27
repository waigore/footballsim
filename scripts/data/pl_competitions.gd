class_name PLCompetitions
extends RefCounted


static func active_ids() -> Array:
	var out: Array = []
	for row in active():
		out.append(str(row["id"]))
	return out


static func active() -> Array:
	var all := PLRepository.shared().competitions()
	if not LeagueLedger.bound():
		return all
	var actives: Array = LeagueLedger.competition_ids()
	var out: Array = []
	for row in all:
		if actives.has(str(row["id"])):
			out.append(row)
	return out if not out.is_empty() else all


static func all() -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
		"SELECT id, name, short_name, season_label FROM competition ORDER BY name;"
	):
		out.append({
			"id": str(row["id"]),
			"name": str(row["name"]),
			"short_name": str(row["short_name"]),
			"season_label": str(row["season_label"]),
			"clubs": clubs(row["id"]),
		})
	return out


static func one(competition_id: String) -> Dictionary:
	if competition_id == "":
		return {}
	var row := PLDatabase.row(
		"SELECT id, name, short_name, season_label FROM competition WHERE id = ?;",
		[competition_id],
	)
	if row.is_empty():
		return {}
	row["id"] = str(row["id"])
	row["clubs"] = clubs(row["id"])
	return row

static func exists(competition_id: String) -> bool:
	return not one(competition_id).is_empty()


static func clubs(competition_id: String) -> int:
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM club WHERE competition_id = ?;", [competition_id])
	return int(row.get("n", 0))


static func default_id() -> String:
	if exists("PL"):
		return "PL"
	var row := PLDatabase.row("SELECT id FROM competition ORDER BY name LIMIT 1;")
	return str(row.get("id", ""))


static func season_owns(competition_id: String) -> bool:
	if not LeagueLedger.bound():
		return false
	var id := competition_id if competition_id != "" else default_id()
	if id == "":
		return false
	return not PLDatabase.row(
		"SELECT t.club_id FROM league_table t "
		+ "WHERE t.competition_id = ? LIMIT 1;",
		[id],
	).is_empty()
