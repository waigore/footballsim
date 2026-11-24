class_name LeagueLedger
extends RefCounted

## The season's own readings, in the shapes the encyclopedia already draws.
##
## A save is a whole universe: its `league_fixture`, `league_table` and
## `league_player_stat` tables are the only honest answer to "what has happened
## here" while that save is bound. The snapshot's `fixture`/`table_row`/
## `sim_player_stat` tables are still in the file — they ship with the seed — but
## they describe the real world on the snapshot date, not the season being
## played. `PLRepository` therefore reads this module whenever `bound()` is true
## (DR-20261125-08), so a club page cannot show 28 points beside a season table
## that says one game played.

## Ordered standings, exactly as `LeagueRecord.table()` orders them: the place
## is the row's position in this list, never a stored column.
const TABLE_SELECT := (
	"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
	+ "FROM league_table t JOIN club c ON c.id = t.club_id "
	+ "ORDER BY t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;"
)

const FIXTURE_SELECT := (
	"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, a.name AS away_name, "
	+ "a.abbr AS away_abbr, 1 AS played "
	+ "FROM league_fixture f JOIN club h ON h.id = f.home_club_id "
	+ "JOIN club a ON a.id = f.away_club_id "
)

## Bound path and its answer, so the sqlite_master probe runs once per
## connection rather than on every page read.
static var _path := ""
static var _bound := false

## True while a league save owns the connection. Its fixture table is the marker:
## the shipped seed has none.
static func bound() -> bool:
	var path := PLDatabase.current_path()
	if path == _path:
		return _bound
	_path = path
	_bound = not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'league_fixture';"
	).is_empty()
	return _bound

## A club's row in the live standings, with its 1-based place.
static func club_record(club_id: String) -> Dictionary:
	var rows := PLDatabase.rows(TABLE_SELECT)
	for i in range(rows.size()):
		rows[i]["position"] = i + 1
		if str(rows[i].get("club_id", "")) == club_id:
			return rows[i]
	return {}

## Played fixtures, newest first, with the same keys `PLRepository.fixtures`
## returns so a page cannot tell which ledger answered. An empty `club_id` reads
## the whole league.
static func fixtures(club_id: String = "", limit: int = 8) -> Array:
	if club_id.is_empty():
		return PLDatabase.rows(
			FIXTURE_SELECT + "WHERE f.status = 'played' "
			+ "ORDER BY f.kickoff DESC, f.kickoff_time DESC, f.id DESC LIMIT ?;", [limit])
	return PLDatabase.rows(
		FIXTURE_SELECT + "WHERE f.status = 'played' "
		+ "AND (f.home_club_id = ? OR f.away_club_id = ?) "
		+ "ORDER BY f.kickoff DESC, f.kickoff_time DESC, f.id DESC LIMIT ?;",
		[club_id, club_id, limit])

## One player's season line: apps, goals, assists and cards. The season keeps
## no per-match shots or rating (the auto path is synthetic), so a page must not
## promise them here.
static func player_line(player_id: String) -> Dictionary:
	var row := PLDatabase.row("SELECT * FROM league_player_stat WHERE player_id = ?;", [player_id])
	if row.is_empty():
		return {}
	return {
		"apps": int(row.get("apps", 0)), "goals": int(row.get("goals", 0)),
		"assists": int(row.get("assists", 0)), "yellow": int(row.get("yellow", 0)),
		"red": int(row.get("red", 0)), "season": true,
	}

## The club's season scorer chart, in `sim_scorers`' shape.
static func scorers(club_id: String, limit: int = 5) -> Array:
	return PLDatabase.rows(
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id "
		+ "FROM league_player_stat s JOIN player p ON p.id = s.player_id "
		+ "WHERE s.club_id = ? AND s.goals > 0 "
		+ "ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;", [club_id, limit])

## League-wide season scorers, in `sim_leaders`' shape.
static func leaders(limit: int = 5) -> Array:
	return PLDatabase.rows(
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id, c.abbr "
		+ "FROM league_player_stat s JOIN player p ON p.id = s.player_id "
		+ "JOIN club c ON c.id = s.club_id WHERE s.goals > 0 "
		+ "ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;", [limit])
