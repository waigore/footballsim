class_name LeagueClips
extends RefCounted

## The goal clips of a season save: one playback pack per goal on every match
## report, keyed by `(fixture_id, goal_index)` — the goal's ordinal in that
## fixture's report, so a row and its clip always agree. Re-settling a fixture
## replaces its clips instead of stacking a second set behind the first.
##
## Split out of `LeagueRecord` so the ledger of results and the store of
## pictures stay one concern each; both talk to the same bound save.

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
			+ "codec, version, home_club_id, away_club_id, bytes) "
			+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
			+ "ON CONFLICT(fixture_id, goal_index) DO UPDATE SET "
			+ "match_event_id = excluded.match_event_id, minute = excluded.minute, "
			+ "club_id = excluded.club_id, scorer_id = excluded.scorer_id, "
			+ "scorer_name = excluded.scorer_name, assist_id = excluded.assist_id, "
			+ "assist_name = excluded.assist_name, commentary = excluded.commentary, "
			+ "source = excluded.source, codec = excluded.codec, version = excluded.version, "
			+ "home_club_id = excluded.home_club_id, away_club_id = excluded.away_club_id, "
			+ "bytes = excluded.bytes;",
			[
				fixture_id, int(row.get("goal_index", 0)), int(row.get("match_event_id", 0)),
				int(row.get("minute", 0)), str(row.get("club_id", "")),
				str(row.get("scorer_id", "")), str(row.get("scorer_name", "")),
				str(row.get("assist_id", "")), str(row.get("assist_name", "")),
				str(row.get("commentary", "")), str(row.get("source", "auto")),
				str(row.get("codec", "")), int(row.get("version", 0)),
				str(row.get("home_club_id", "")), str(row.get("away_club_id", "")),
				row.get("bytes", PackedByteArray()),
			],
		)

## Clip metadata for a fixture's report: everything the rows paint, without
## inflating the blobs.
func list(fixture_id: String) -> Array:
	save.ensure_open()
	return PLDatabase.rows(
		"SELECT fixture_id, goal_index, match_event_id, minute, club_id, scorer_id, "
		+ "scorer_name, assist_id, assist_name, commentary, source, codec, version "
		+ "FROM goal_highlight WHERE fixture_id = ? ORDER BY goal_index;",
		[fixture_id],
	)

## One stored clip, decoded. Empty when the row or its blob is missing.
func pack(fixture_id: String, goal_index: int) -> Dictionary:
	save.ensure_open()
	var row := PLDatabase.row(
		"SELECT bytes FROM goal_highlight WHERE fixture_id = ? AND goal_index = ?;",
		[fixture_id, goal_index],
	)
	if row.is_empty():
		return {}
	var bytes = row.get("bytes", PackedByteArray())
	if not bytes is PackedByteArray:
		return {}
	return GoalHighlight.unpack(bytes)

## Drop a fixture's clips (a re-settled fixture rewrites its own report).
func clear(fixture_id: String) -> void:
	save.ensure_open()
	PLDatabase.execute("DELETE FROM goal_highlight WHERE fixture_id = ?;", [fixture_id])
