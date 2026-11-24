class_name PLRepository
extends RefCounted

## Read API over the cached Premier League seed. One shape per caller:
## `team()` returns exactly the dictionary the match engine and picker already
## consume, `player()` returns the dossier the encyclopedia draws, and the
## league calls return ready-to-draw rows. Everything is memoised per process,
## so opening a dashboard never re-parses the snapshot.

const CANONICAL_ROLES := ["GK", "RB", "RCB", "LCB", "LB", "RDM", "LDM", "RW", "CAM", "LW", "ST"]

static var _shared: PLRepository = null

var _teams := {}
var _players := {}
var _clubs := {}

static func shared() -> PLRepository:
	if _shared == null:
		_shared = PLRepository.new()
	return _shared

## Drop memoised rows after a write (in-sim stats) or a cache rebuild.
func invalidate() -> void:
	_teams.clear()
	_players.clear()
	_clubs.clear()

func meta() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("SELECT key, value FROM metadata;"):
		out[str(row["key"])] = str(row["value"])
	return out

func season_label() -> String:
	return str(meta().get("season_label", ""))

func source_label() -> String:
	var meta_rows := meta()
	return str(meta_rows.get("source", "")) + " · " + str(meta_rows.get("snapshot_date", ""))

func club_ids() -> Array:
	var ids: Array = []
	for row in PLDatabase.rows("SELECT id FROM club ORDER BY name;"):
		ids.append(str(row["id"]))
	return ids

## Club row plus its league table line: what the team dashboard header needs.
func club(club_id: String) -> Dictionary:
	if _clubs.has(club_id):
		return _clubs[club_id]
	var row := PLDatabase.row("SELECT * FROM club WHERE id = ?;", [club_id])
	if row.is_empty():
		return {}
	# A season save owns its own standings, so the header reads the row the
	# season keeps; without one it is the snapshot's reading of the real table.
	var table: Dictionary = LeagueLedger.club_record(club_id) if LeagueLedger.bound() \
		else PLDatabase.row("SELECT * FROM table_row WHERE club_id = ?;", [club_id])
	var style := {}
	for key in ["possession", "tempo", "press", "line", "width", "directness", "crossing", "aggression"]:
		style[key] = float(row.get("style_" + key, 0.5))
	var out := {
		"id": str(row["id"]),
		"name": str(row["name"]),
		"short": str(row["short"]),
		"abbr": str(row["abbr"]),
		"nickname": str(row["nickname"]),
		"manager": str(row["manager"]),
		"stadium": str(row["stadium"]),
		"city": str(row["city"]),
		"capacity": int(row["capacity"]),
		"formation": str(row["formation"]),
		"color": Color(str(row["color"])),
		"color_dark": Color(str(row["color_dark"])),
		"color_light": Color(str(row["color_light"])),
		"shorts": Color(str(row["shorts"])),
		"gk_color": Color(str(row["gk_color"])),
		"text": Color(str(row["text_color"])),
		"style": style,
		"table": table,
	}
	_clubs[club_id] = out
	return out

## The engine-facing team dictionary (the shape TeamData used to serve).
func team(club_id: String) -> Dictionary:
	if _teams.has(club_id):
		return _teams[club_id]
	var base := club(club_id)
	if base.is_empty():
		return {}
	var starters: Array = []
	var bench: Array = []
	for p in squad(club_id):
		var item := {
			"id": p["id"], "name": p["name"], "number": p["number"], "role": p["role"],
			"pos": p["pos"], "ovr": p["ovr"], "pac": p["pac"], "sho": p["sho"],
			"pas": p["pas"], "dri": p["dri"], "def": p["def"], "phy": p["phy"],
			"height": p["height"],
		}
		if str(p["role"]) == "GK":
			item["gk"] = p["gk"]
		if str(p["squad"]) == "bench":
			bench.append(item)
		else:
			starters.append(item)
	var out := base.duplicate()
	out["starters"] = starters
	out["bench"] = bench
	out.erase("table")
	_teams[club_id] = out
	return out

## Squad rows in snapshot order: the eleven starters, then the bench.
func squad(club_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows("SELECT * FROM player WHERE club_id = ? ORDER BY ord;", [club_id]):
		out.append(_player_row(row))
	return out

func _player_row(row: Dictionary) -> Dictionary:
	var gk := {}
	if row.get("gk_div") != null:
		gk = {
			"div": int(row["gk_div"]), "han": int(row["gk_han"]), "kic": int(row["gk_kic"]),
			"ref": int(row["gk_ref"]), "spd": int(row["gk_spd"]),
		}
	return {
		"id": str(row["id"]), "club_id": str(row["club_id"]), "name": str(row["name"]),
		"number": int(row["number"]), "role": str(row["role"]), "pos": str(row["pos"]),
		"ovr": int(row["ovr"]), "pac": int(row["pac"]), "sho": int(row["sho"]),
		"pas": int(row["pas"]), "dri": int(row["dri"]), "def": int(row["def"]),
		"phy": int(row["phy"]), "height": int(row["height"]), "gk": gk,
		"squad": str(row["squad"]), "age": int(row["age"]), "nationality": str(row["nationality"]),
		"date_of_birth": str(row["date_of_birth"]), "espn_id": str(row["espn_id"]),
	}

## Full dossier: identity, ratings, the real-world season and career figures.
func player(player_id: String) -> Dictionary:
	if _players.has(player_id):
		return _players[player_id]
	var row := PLDatabase.row("SELECT * FROM player WHERE id = ?;", [player_id])
	if row.is_empty():
		return {}
	var out := _player_row(row)
	var season := PLDatabase.row("SELECT * FROM season_stat WHERE player_id = ?;", [player_id])
	out["season"] = season
	out["career"] = PLDatabase.row("SELECT * FROM career_stat WHERE player_id = ?;", [player_id])
	out["sim"] = sim_player(player_id)
	_players[player_id] = out
	return out

func player_by_name(club_id: String, name: String) -> Dictionary:
	var row := PLDatabase.row("SELECT id FROM player WHERE club_id = ? AND name = ?;", [club_id, name])
	return player(str(row["id"])) if not row.is_empty() else {}

## League table: the save's live standings while a league season owns the
## connection, otherwise the snapshot's table as of its snapshot date.
func table() -> Array:
	if _live_table_exists():
		return _live_table()
	var out: Array = []
	for row in PLDatabase.rows(
		"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
		+ "FROM table_row t JOIN club c ON c.id = t.club_id ORDER BY t.position;"
	):
		out.append(row)
	return out

## A league save adds `league_table` beside the snapshot's `table_row`; when it
## is there, the encyclopedia must show the season the player is actually in.
func _live_table_exists() -> bool:
	return not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'league_table';"
	).is_empty()

func _live_table() -> Array:
	var rows := PLDatabase.rows(
		"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
		+ "FROM league_table t JOIN club c ON c.id = t.club_id "
		+ "ORDER BY t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;"
	)
	for i in range(rows.size()):
		rows[i]["position"] = i + 1
	return rows


## Top scorers from the real-world snapshot; `stat` is goals or assists.
func leaders(limit: int = 6, stat: String = "goals") -> Array:
	var column := "assists" if stat == "assists" else "goals"
	var out: Array = []
	for row in PLDatabase.rows(
		"SELECT s.player_id, s.matches, s.goals, s.assists, p.name, p.pos, c.abbr "
		+ "FROM season_stat s JOIN player p ON p.id = s.player_id JOIN club c ON c.id = p.club_id "
		+ "ORDER BY s.%s DESC, s.assists DESC, p.name LIMIT ?;" % column,
		[limit],
	):
		out.append(row)
	return out

## Fixtures for one club (or the whole league), newest first. Only a played game
## is a result: an unplayed one is `upcoming()`'s reading, never a 0 – 0 line.
## A season save answers with the fixtures it has actually played.
func fixtures(club_id: String = "", limit: int = 8) -> Array:
	if LeagueLedger.bound():
		return LeagueLedger.fixtures(club_id, limit)
	var sql := (
		"SELECT f.*, h.abbr AS home_abbr, a.abbr AS away_abbr, h.name AS home_name, "
		+ "a.name AS away_name FROM fixture f JOIN club h ON h.id = f.home_club_id "
		+ "JOIN club a ON a.id = f.away_club_id "
	)
	if club_id.is_empty():
		sql += "WHERE f.played = 1 ORDER BY f.kickoff DESC LIMIT ?;"
		return PLDatabase.rows(sql, [limit])
	sql += "WHERE f.played = 1 AND (f.home_club_id = ? OR f.away_club_id = ?) "
	sql += "ORDER BY f.kickoff DESC, f.id DESC LIMIT ?;"
	return PLDatabase.rows(sql, [club_id, club_id, limit])

## The fixtures still ahead, soonest first: what a page reads as what comes next
## for a club. A season answers with the games its clock still holds; the
## snapshot answers with the remaining schedule it ships.
func upcoming(club_id: String = "", limit: int = 6) -> Array:
	if LeagueLedger.bound():
		return LeagueLedger.upcoming(club_id, limit)
	var sql := (
		"SELECT f.*, h.abbr AS home_abbr, a.abbr AS away_abbr, h.name AS home_name, "
		+ "a.name AS away_name FROM fixture f JOIN club h ON h.id = f.home_club_id "
		+ "JOIN club a ON a.id = f.away_club_id WHERE f.played = 0 "
	)
	if club_id.is_empty():
		return PLDatabase.rows(sql + "ORDER BY f.kickoff ASC, f.id ASC LIMIT ?;", [limit])
	sql += "AND (f.home_club_id = ? OR f.away_club_id = ?) ORDER BY f.kickoff ASC, f.id ASC LIMIT ?;"
	return PLDatabase.rows(sql, [club_id, club_id, limit])

## True while a league save owns the connection (DR-20261125-08): the pages
## label which season their Footballsim readings belong to.
func season_active() -> bool:
	return LeagueLedger.bound()

## One player's Footballsim line. While a season is open it is that season's own
## ledger; without one it is the single-match ledger the cache keeps.
func sim_player(player_id: String) -> Dictionary:
	if LeagueLedger.bound():
		return LeagueLedger.player_line(player_id)
	return PLDatabase.row("SELECT * FROM sim_player_stat WHERE player_id = ?;", [player_id])

## A club's Footballsim record: the season's league row, or the single-match one.
func sim_club(club_id: String) -> Dictionary:
	if LeagueLedger.bound():
		return LeagueLedger.club_record(club_id)
	return PLDatabase.row("SELECT * FROM sim_club_stat WHERE club_id = ?;", [club_id])

## Footballsim scorer chart for a club: the season's, or the single-match one.
func sim_scorers(club_id: String, limit: int = 5) -> Array:
	if LeagueLedger.bound():
		return LeagueLedger.scorers(club_id, limit)
	return PLDatabase.rows(
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id FROM sim_player_stat s "
		+ "JOIN player p ON p.id = s.player_id WHERE p.club_id = ? AND s.goals > 0 "
		+ "ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;",
		[club_id, limit],
	)

## Footballsim top scorers across the league: the season's, or the single-match one.
func sim_leaders(limit: int = 5) -> Array:
	if LeagueLedger.bound():
		return LeagueLedger.leaders(limit)
	return PLDatabase.rows(
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id, c.abbr FROM sim_player_stat s "
		+ "JOIN player p ON p.id = s.player_id JOIN club c ON c.id = p.club_id "
		+ "ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;",
		[limit],
	)
