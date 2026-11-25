class_name LeagueInterest
extends RefCounted

## Teams of Interest inside one save (#104): a persisted shortlist of clubs, and
## the Watch rule that follows from it.
##
## A followed club's unplayed fixtures are always on Watch, so the season can
## never auto-sim a game the player asked to see. Interest is a set of club ids
## in the save, never a second source of fixtures; the ledger's own `watched`
## flag is what the clock reads. Unmarking a club releases its fixtures back to
## Auto unless the opponent is still followed — a fixture between two followed
## clubs stays on Watch until neither side is.

var save: LeagueSave = null

func _init(owner: LeagueSave) -> void:
	save = owner

## The followed clubs in name order. The save owns the list, so it survives a
## quit and never leaks between two seasons.
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

## A club the save knows: interest may only name one of the league's own clubs.
func has_club(club_id: String) -> bool:
	save.ensure_open()
	return not PLDatabase.row("SELECT id FROM club WHERE id = ?;", [club_id]).is_empty()

## Mark or unmark one club. Marking forces its unplayed fixtures onto Watch;
## unmarking releases them unless the opponent is still followed.
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

## Every unplayed fixture that involves a followed club is on Watch. Interest
## always wins, so a hand-edited save or a manual Auto never auto-sims one.
func force_watch() -> bool:
	save.ensure_open()
	return PLDatabase.execute(
		"UPDATE league_fixture SET watched = 1 WHERE status <> 'played' AND watched = 0 "
		+ "AND (home_club_id IN (SELECT club_id FROM league_interest) "
		+ "OR away_club_id IN (SELECT club_id FROM league_interest));")

## Unmarking a club returns that club's unplayed fixtures to Auto, except the
## ones whose other side is still followed — those stay on Watch.
func release_watch(club_id: String) -> bool:
	save.ensure_open()
	return PLDatabase.execute(
		"UPDATE league_fixture SET watched = 0 WHERE status <> 'played' AND watched = 1 "
		+ "AND (home_club_id = ? OR away_club_id = ?) "
		+ "AND home_club_id NOT IN (SELECT club_id FROM league_interest) "
		+ "AND away_club_id NOT IN (SELECT club_id FROM league_interest);",
		[club_id, club_id])

## True when either side of a fixture is followed: its watch flag is the
## interest rule's, not a manual choice, so the planner cannot switch it off.
func holds(fixture_id: String) -> bool:
	save.ensure_open()
	return not PLDatabase.row(
		"SELECT f.id FROM league_fixture f WHERE f.id = ? AND ("
		+ "f.home_club_id IN (SELECT club_id FROM league_interest) OR "
		+ "f.away_club_id IN (SELECT club_id FROM league_interest));", [fixture_id]).is_empty()
