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
##
## A save can run more than one competition. Every league-wide read takes an
## optional competition id: one league's readings when it is named, every active
## league (the index pages) when it is not. A club belongs to exactly one
## domestic league, so its own page never needs to name one.

## Ordered standings for one competition: the place is the row's position in
## this list, never a stored column.
const TABLE_SELECT := (
	"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
	+ "FROM league_table t JOIN club c ON c.id = t.club_id "
)

const FIXTURE_SELECT := (
	"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, a.name AS away_name, "
	+ "a.abbr AS away_abbr, 1 AS played "
	+ "FROM league_fixture f JOIN club h ON h.id = f.home_club_id "
	+ "JOIN club a ON a.id = f.away_club_id "
)

## The unplayed half of the ledger: same keys as FIXTURE_SELECT, with `played`
## 0 so a page cannot read a fixture ahead as a 0 – 0 result.
const UPCOMING_SELECT := (
	"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, a.name AS away_name, "
	+ "a.abbr AS away_abbr, 0 AS played "
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

## A club's own competition: the league its page's table belongs to.
static func competition_of(club_id: String) -> String:
	var row := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	return str(row.get("competition_id", ""))

## The active competitions this ledger holds, in the save's order.
static func competition_ids() -> Array:
	var out: Array = []
	for row in PLDatabase.rows("SELECT DISTINCT competition_id FROM league_fixture;"):
		out.append(str(row["competition_id"]))
	return out

## A club's row in the live standings, with its 1-based place.
static func club_record(club_id: String) -> Dictionary:
	var comp := competition_of(club_id)
	var rows := table(comp)
	for row in rows:
		if str(row.get("club_id", "")) == club_id:
			return row
	return {}

## One competition's standings with 1-based places; every active league when no
## competition is named, each numbered from one.
static func table(competition_id: String = "") -> Array:
	var sql := TABLE_SELECT
	var bindings: Array = []
	if competition_id == "":
		sql += "ORDER BY t.competition_id, t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;"
	else:
		sql += ("WHERE t.competition_id = ? "
			+ "ORDER BY t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;")
		bindings.append(competition_id)
	var rows := PLDatabase.rows(sql, bindings)
	var place := 0
	var last := ""
	for i in range(rows.size()):
		var comp := str(rows[i].get("competition_id", ""))
		place = 1 if comp != last else place + 1
		last = comp
		rows[i]["position"] = place
	return rows

## Played fixtures, newest first, with the same keys `PLRepository.fixtures`
## returns so a page cannot tell which ledger answered. An empty `club_id` reads
## the whole league; an empty competition id reads every active league.
static func fixtures(club_id: String = "", limit: int = 8, competition_id: String = "") -> Array:
	var sql := FIXTURE_SELECT + "WHERE f.status = 'played'"
	var bindings: Array = []
	if club_id != "":
		sql += " AND (f.home_club_id = ? OR f.away_club_id = ?)"
		bindings.append_array([club_id, club_id])
	if competition_id != "":
		sql += " AND f.competition_id = ?"
		bindings.append(competition_id)
	sql += " ORDER BY f.kickoff DESC, f.kickoff_time DESC, f.id DESC LIMIT ?;"
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)

## The fixtures the clock still holds, soonest first — what a club faces next.
## Same keys as `fixtures()`, so the page draws both readings the same way.
static func upcoming(club_id: String = "", limit: int = 6, competition_id: String = "") -> Array:
	var sql := UPCOMING_SELECT + "WHERE f.status <> 'played'"
	var bindings: Array = []
	if club_id != "":
		sql += " AND (f.home_club_id = ? OR f.away_club_id = ?)"
		bindings.append_array([club_id, club_id])
	if competition_id != "":
		sql += " AND f.competition_id = ?"
		bindings.append(competition_id)
	sql += " ORDER BY f.kickoff ASC, f.kickoff_time ASC, f.id ASC LIMIT ?;"
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)

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

## League-wide season scorers, in `sim_leaders`' shape. One competition's when
## named, every active league's when not. `teams` narrows the chart to those
## clubs (the STATS filter); empty reads every side.
static func leaders(limit: int = 5, competition_id: String = "", stat: String = "goals",
		teams: Array = []) -> Array:
	var column := "assists" if stat == "assists" else "goals"
	var sql := (
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id, c.abbr, "
		+ "c.id AS club_id, s.competition_id FROM league_player_stat s "
		+ "JOIN player p ON p.id = s.player_id "
		+ "JOIN club c ON c.id = s.club_id WHERE s.%s > 0" % column
	)
	var bindings: Array = []
	if competition_id != "":
		sql += " AND s.competition_id = ?"
		bindings.append(competition_id)
	if not teams.is_empty():
		sql += " AND c.id IN (" + ",".join(_placeholders(teams.size())) + ")"
		bindings.append_array(teams)
	sql += " ORDER BY s.%s DESC, s.assists DESC, p.name LIMIT ?;" % column
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)

static func _placeholders(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(count):
		out.append("?")
	return out
