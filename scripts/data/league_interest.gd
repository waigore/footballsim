class_name LeagueInterest
extends RefCounted

## The player's Teams of Interest: a shortlist of clubs kept inside one league
## save, and the watch rule that follows from it.
##
## Interest lives in the save's own `save_meta` row as a comma-separated set of
## club ids, so a save written before the feature opens with an empty set and no
## migration step is needed. The rule is one-way and absolute: any pending
## fixture with an interested club on either side is on Watch. Marking a club
## therefore swings all of its unplayed fixtures to Watch, unmarking gives them
## back to Auto unless the opponent is still on the list, and a manual Auto on
## such a fixture is undone by the next sync. Interest never touches the score,
## the seed or the match engine — only the watch flags and the UI state.

## `save_meta` key holding the set.
const META_KEY := "interest"

## The interest set of the season that is open, for surfaces that only have a
## club id in hand (a team name on the HUD, a chip in the encyclopedia).
static var current: LeagueInterest = null

var save: LeagueSave = null
## club_id -> true. Kept in step with the save on every write and reload.
var ids: Dictionary = {}

func _init(owner: LeagueSave) -> void:
	save = owner
	reload()

## Yellow marks the player's shortlisted clubs wherever a name is painted. With
## no league season open every name keeps its usual colour.
static func marked(club_id: String) -> bool:
	return current != null and current.has(club_id)

## Re-read the set from the save. A save with no row keeps an empty set.
func reload() -> void:
	ids.clear()
	if save == null or not save.ensure_open():
		return
	for raw in str(save.meta.get(META_KEY, "")).split(",", false):
		var id := raw.strip_edges()
		if id != "":
			ids[id] = true

## Every interested club id, sorted so a list paints in a stable order.
func all() -> Array:
	var out: Array = ids.keys()
	out.sort()
	return out

func has(club_id: String) -> bool:
	return ids.has(club_id)

func count() -> int:
	return ids.size()

func is_empty() -> bool:
	return ids.is_empty()

## Mark or unmark one club and move that club's unplayed fixtures to the flag
## the rule asks for. An unknown club id is still stored: the league save is the
## only authority, and a stale id simply matches no fixture.
func set_interest(club_id: String, on: bool) -> bool:
	if save == null or club_id == "":
		return false
	if has(club_id) == on:
		sync_watch()
		return true
	if on:
		ids[club_id] = true
	else:
		ids.erase(club_id)
	var joined := _joined()
	save.meta[META_KEY] = joined
	if not save.put_meta(META_KEY, joined):
		return false
	if on:
		_watch_club(club_id)
	else:
		_release_club(club_id)
	return true

func toggle(club_id: String) -> bool:
	return set_interest(club_id, not has(club_id))

## Does this fixture have an interested club on either side?
func forces(fixture: Dictionary) -> bool:
	return has(str(fixture.get("home_club_id", ""))) or has(str(fixture.get("away_club_id", "")))

## The load/refresh half of the rule: every pending fixture with an interested
## club is forced back to Watch. Running it after a save opens is what makes
## interest survive quit and reload, and what undoes a manual Auto.
func sync_watch() -> void:
	if save == null or ids.is_empty() or not save.ensure_open():
		return
	var marks := all()
	var holes: Array = []
	for i in range(marks.size()):
		holes.append("?")
	var places := ", ".join(holes)
	var bindings: Array = marks.duplicate()
	bindings.append_array(marks)
	PLDatabase.execute(
		"UPDATE league_fixture SET watched = 1 WHERE status <> 'played' AND "
		+ "(home_club_id IN (%s) OR away_club_id IN (%s));" % [places, places],
		bindings,
	)

# ---------------------------------------------------------------- watch ---

func _watch_club(club_id: String) -> void:
	PLDatabase.execute(
		"UPDATE league_fixture SET watched = 1 WHERE status <> 'played' "
		+ "AND (home_club_id = ? OR away_club_id = ?);",
		[club_id, club_id],
	)

## Give a club's fixtures back to Auto, except where the opponent is still
## interested: a fixture between two shortlisted clubs stays on Watch for as
## long as either one is marked.
func _release_club(club_id: String) -> void:
	for row in PLDatabase.rows(
		"SELECT id, home_club_id, away_club_id FROM league_fixture "
		+ "WHERE status <> 'played' AND (home_club_id = ? OR away_club_id = ?);",
		[club_id, club_id],
	):
		var home := str(row["home_club_id"])
		var other: String = str(row["away_club_id"]) if home == club_id else home
		if has(other):
			continue
		PLDatabase.execute("UPDATE league_fixture SET watched = 0 WHERE id = ?;", [str(row["id"])])

func _joined() -> String:
	return ",".join(all())
