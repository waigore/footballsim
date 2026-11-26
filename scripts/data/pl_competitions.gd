class_name PLCompetitions
extends RefCounted

## The competitions one database can carry: the seed ships the Premier League,
## and a multi-competition seed (PL + La Liga, #185) is the same shape with
## more rows. Read from the bound file — the seed, or an open save's own copy —
## so a season and the encyclopedia never disagree about what exists.
##
## Nothing here is hard-coded to a league: `default_id()` prefers `PL` only
## because the shipped seed's one competition is the Premier League, and falls
## back to whatever the file actually holds.

## Ids of the competitions a season can run: the open save's actives, or every
## league the file carries when no season is bound.
static func active_ids() -> Array:
	var out: Array = []
	for row in active():
		out.append(str(row["id"]))
	return out

## Competitions a player can actually pick: the open save's active leagues, or
## every league the file carries when no season is bound.
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

## Every competition with the club count its hub needs, in name order.
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

## One competition, or an empty dictionary when the file does not carry it.
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

## Clubs filed under one competition.
static func clubs(competition_id: String) -> int:
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM club WHERE competition_id = ?;", [competition_id])
	return int(row.get("n", 0))

## The competition a page opens on when none is named: the Premier League when
## the file carries it, otherwise the first competition by name.
static func default_id() -> String:
	if exists("PL"):
		return "PL"
	var row := PLDatabase.row("SELECT id FROM competition ORDER BY name LIMIT 1;")
	return str(row.get("id", ""))

## True while the open season's ledger holds clubs of this competition, i.e. it
## is one of the competitions the save is playing. An inactive competition in
## the same file (or any competition when no season is open) reads the snapshot.
## An empty id asks about the file's default competition. The table row answers,
## not the club: after a season's membership swap the finished table still
## belongs to the competition it was played in.
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
