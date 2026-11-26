class_name LeagueClips
extends RefCounted

## The goal clips of a season save: one playback pack per goal on every match
## report, keyed by `(fixture_id, goal_index)` — the goal's ordinal in that
## fixture's report, so a row and its clip always agree. Re-settling a fixture
## replaces its clips instead of stacking a second set behind the first.
##
## Owned by `LeagueReport`, thin beside the event rows it belongs to: the
## ledger of results and the store of pictures stay one concern each; both talk
## to the same bound save.

var save: LeagueSave = null

func _init(owner: LeagueSave) -> void:
	save = owner

## Store a fixture's clips. `rows` carry the commentary line and the packed
## frames, so reopening a save reads the same words beside the same pitch.
func add(rows: Array) -> void:
	save.ensure_open()
	for row in rows:
		var fixture_id := str(row.get("fixture_id", ""))
		if fixture_id == "":
			continue
		PLDatabase.execute(
			"INSERT INTO goal_highlight (fixture_id, goal_index, match_event_id, minute, "
			+ "club_id, scorer_id, scorer_name, assist_id, assist_name, commentary, source, "
			+ "codec, version, home_club_id, away_club_id, bytes, penalty) "
			+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
			+ "ON CONFLICT(fixture_id, goal_index) DO UPDATE SET "
			+ "match_event_id = excluded.match_event_id, minute = excluded.minute, "
			+ "club_id = excluded.club_id, scorer_id = excluded.scorer_id, "
			+ "scorer_name = excluded.scorer_name, assist_id = excluded.assist_id, "
			+ "assist_name = excluded.assist_name, commentary = excluded.commentary, "
			+ "source = excluded.source, codec = excluded.codec, version = excluded.version, "
			+ "home_club_id = excluded.home_club_id, away_club_id = excluded.away_club_id, "
			+ "bytes = excluded.bytes, penalty = excluded.penalty;",
			[
				fixture_id, int(row.get("goal_index", 0)), int(row.get("match_event_id", 0)),
				int(row.get("minute", 0)), str(row.get("club_id", "")),
				str(row.get("scorer_id", "")), str(row.get("scorer_name", "")),
				str(row.get("assist_id", "")), str(row.get("assist_name", "")),
				str(row.get("commentary", "")), str(row.get("source", "auto")),
				str(row.get("codec", "")), int(row.get("version", 0)),
				str(row.get("home_club_id", "")), str(row.get("away_club_id", "")),
				row.get("bytes", PackedByteArray()),
				1 if bool(row.get("penalty", false)) else 0,
			],
		)

## Clip metadata for a fixture's report: everything the rows paint, without
## inflating the blobs.
func list(fixture_id: String) -> Array:
	save.ensure_open()
	return PLDatabase.rows(
		"SELECT fixture_id, goal_index, match_event_id, minute, club_id, scorer_id, "
		+ "scorer_name, assist_id, assist_name, commentary, source, codec, version, penalty "
		+ "FROM goal_highlight WHERE fixture_id = ? ORDER BY goal_index;",
		[fixture_id],
	)

## One stored clip, decoded. Empty when the row is missing.
##
## An auto-settled goal keeps its recipe, not its picture (see
## `LeagueHighlights._generated_row`): the pack is drawn here, on the first
## report that asks for it, and cached in the row so reopening it is one read.
func pack(fixture_id: String, goal_index: int) -> Dictionary:
	save.ensure_open()
	var row := PLDatabase.row(
		"SELECT * FROM goal_highlight WHERE fixture_id = ? AND goal_index = ?;",
		[fixture_id, goal_index],
	)
	if row.is_empty():
		return {}
	var bytes = row.get("bytes", PackedByteArray())
	if bytes is PackedByteArray and not (bytes as PackedByteArray).is_empty():
		return GoalHighlight.unpack(bytes)
	var drawn := _draw(row)
	if drawn.is_empty():
		return {}
	PLDatabase.execute(
		"UPDATE goal_highlight SET bytes = ? WHERE fixture_id = ? AND goal_index = ?;",
		[drawn, fixture_id, goal_index],
	)
	return GoalHighlight.unpack(drawn)

## Draw one recipe row's pack from what the save itself remembers: the club ids
## pick the XI, the fixture's own goal rows give the scoreline at that goal, and
## the save seed plus the goal's index give the clip its seed back. Everything
## here is what the settling pass would have used, so the clip is the same one.
func _draw(row: Dictionary) -> PackedByteArray:
	var fixture_id := str(row.get("fixture_id", ""))
	var index := int(row.get("goal_index", 0))
	var home := str(row.get("home_club_id", ""))
	var away := str(row.get("away_club_id", ""))
	if fixture_id == "" or home == "" or away == "":
		return PackedByteArray()
	var club := str(row.get("club_id", home))
	var fields := {
		"fixture_id": fixture_id, "goal_index": index,
		"minute": int(row.get("minute", 0)), "home": home, "away": away, "club_id": club,
		"player_id": str(row.get("scorer_id", "")),
		"player_name": str(row.get("scorer_name", "")),
		"assist_id": str(row.get("assist_id", "")),
		"assist_name": str(row.get("assist_name", "")),
		"club_short": LeagueHighlights.short_name(club),
		"opp_short": LeagueHighlights.short_name(away if club == home else home),
		"score_after": _score_after(fixture_id, index, home, club),
		"source": str(row.get("source", "auto")),
		"commentary": str(row.get("commentary", "")),
		"penalty": int(row.get("penalty", 0)) == 1,
	}
	var sides := {
		"home": StrongestXI.pick(TeamData.get_team(home)),
		"away": StrongestXI.pick(TeamData.get_team(away)),
	}
	var seed := GoalHighlight.seed_for(int(str(save.meta.get("seed", "0"))), fixture_id, index)
	return GoalHighlight.pack(GoalHighlight.build(fields, sides, seed))

## The scoreline a goal stood at, from the fixture's own goal rows in the order
## the report prints them: the goal's own club's tally includes the goal.
func _score_after(fixture_id: String, index: int, home: String, club: String) -> Array:
	var score := [0, 0]
	for row in PLDatabase.rows(
		"SELECT goal_index, club_id FROM goal_highlight WHERE fixture_id = ? ORDER BY goal_index;",
		[fixture_id],
	):
		if str(row.get("club_id", "")) == home:
			score[0] += 1
		else:
			score[1] += 1
		if int(row.get("goal_index", -1)) >= index:
			break
	return [int(score[0]), int(score[1])]

## Drop a fixture's clips (a re-settled fixture rewrites its own report).
func clear(fixture_id: String) -> void:
	save.ensure_open()
	PLDatabase.execute("DELETE FROM goal_highlight WHERE fixture_id = ?;", [fixture_id])
