class_name LeagueHighlights
extends RefCounted

## Goal clips for a season: one playback pack per goal on every match report.
##
## A fixture the player left on Auto has no live picture to record, so each goal
## gets a generated clip that ends with the report's own scorer and assist. A
## watched fixture already ran on the pitch, so the clip is cut from the
## viewer's snapshot ring of the goal that really happened. Both paths write the
## same row shape, so a report reads a clip without knowing which path made it.
##
## The store is keyed by `(fixture_id, goal_index)`: the goal's ordinal in that
## fixture's report. Re-settling a fixture therefore replaces its clips instead
## of stacking a second set behind the first.

# --------------------------------------------------------------- auto path ---

## Build and store a clip for every goal of a settled fixture.
static func store_auto(record: LeagueRecord, save_seed: int, fixture_id: String,
		events: Array, home: String, away: String) -> void:
	if record == null:
		return
	var orders := goal_rows(events)
	var score := [0, 0]
	var rows: Array = []
	for i in range(orders.size()):
		var e: Dictionary = orders[i]
		if str(e.get("club_id", "")) == home:
			score[0] += 1
		else:
			score[1] += 1
		rows.append(_generated_row(save_seed, fixture_id, e, i, [int(score[0]), int(score[1])],
			home, away, 0))
	record.clips.add(rows)

## The goal rows of a match report, in the order the report prints them: by
## minute, then by the order the season wrote them.
static func goal_rows(events: Array) -> Array:
	var ordered: Array = []
	for i in range(events.size()):
		var e: Dictionary = events[i]
		if str(e.get("kind", "")) == "goal":
			ordered.append({"i": i, "e": e})
	ordered.sort_custom(func(a, b):
		var ma := int((a["e"] as Dictionary).get("minute", 0))
		var mb := int((b["e"] as Dictionary).get("minute", 0))
		if ma != mb:
			return ma < mb
		return int(a["i"]) < int(b["i"]))
	var out: Array = []
	for item in ordered:
		out.append(item["e"])
	return out

# -------------------------------------------------------------- watch path ---

## Store the clips of a fixture that was just watched. Each goal event row gets
## the live capture that matches it; a goal with no capture (a ring cleared at
## half-time, a fast-forwarded session) falls back to a generated clip so the
## report still offers a ▶.
static func store_watch(record: LeagueRecord, save_seed: int, fixture_id: String,
		captured: Array, home: String, away: String) -> void:
	if record == null or fixture_id == "":
		return
	var score := [0, 0]
	var used := {}
	var rows: Array = []
	var goals: Array = []
	for e in record.report.events(fixture_id):
		if str(e.get("kind", "")) == "goal":
			goals.append(e)
	for i in range(goals.size()):
		var e: Dictionary = goals[i]
		if str(e.get("club_id", "")) == home:
			score[0] += 1
		else:
			score[1] += 1
		var event_id := int(e.get("id", 0))
		var picked := _match_capture(captured, used, int(e.get("minute", 0)), str(e.get("player_id", "")))
		if picked.is_empty():
			rows.append(_generated_row(save_seed, fixture_id, e, i, [int(score[0]), int(score[1])],
				home, away, event_id))
			continue
		var row := _captured_row(picked, fixture_id, e, i, [int(score[0]), int(score[1])])
		row["match_event_id"] = event_id
		rows.append(row)
	record.clips.add(rows)

## The first unused capture of this goal. A capture is stamped with the minute
## and scorer the live engine reported, so the pair identifies it even when two
## goals share a minute.
static func _match_capture(captured: Array, used: Dictionary, minute: int, scorer_id: String) -> Dictionary:
	for i in range(captured.size()):
		if used.has(i):
			continue
		var pack: Dictionary = captured[i]
		if int(pack.get("minute", -1)) != minute:
			continue
		if str(pack.get("scorer_id", "")) != scorer_id:
			continue
		used[i] = true
		return pack
	for i in range(captured.size()):
		if not used.has(i):
			used[i] = true
			return captured[i]
	return {}

static func _captured_row(pack: Dictionary, fixture_id: String, event: Dictionary,
		index: int, score_after: Array) -> Dictionary:
	var clip := pack.duplicate(true)
	clip["fixture_id"] = fixture_id
	clip["goal_index"] = index
	clip["score"] = [int(score_after[0]), int(score_after[1])]
	var commentary := str(clip.get("commentary", ""))
	if commentary == "":
		var src := {
			"home": str(clip.get("home", "")), "away": str(clip.get("away", "")),
			"scorer_id": str(clip.get("scorer_id", "")), "scorer": str(clip.get("scorer", "")),
			"assist_id": str(clip.get("assist_id", "")),
			"assist_name": str(clip.get("assist", clip.get("assist_name", ""))),
		}
		commentary = GoalHighlight.commentary(_goal_fields(src, event, fixture_id, index,
			score_after), int(clip.get("seed", 0)))
		clip["commentary"] = commentary
	return {
		"fixture_id": fixture_id, "goal_index": index, "match_event_id": 0,
		"minute": int(clip.get("minute", event.get("minute", 0))),
		"club_id": str(clip.get("club_id", event.get("club_id", ""))),
		"scorer_id": str(clip.get("scorer_id", event.get("player_id", ""))),
		"scorer_name": str(clip.get("scorer", event.get("player_name", ""))),
		"assist_id": str(clip.get("assist_id", "")),
		"assist_name": str(clip.get("assist", "")),
		"commentary": commentary, "source": "watch",
		"codec": str(clip.get("codec", GoalHighlight.CODEC)),
		"version": int(clip.get("version", GoalHighlight.VERSION)),
		"home_club_id": str(clip.get("home", "")), "away_club_id": str(clip.get("away", "")),
		"bytes": GoalHighlight.pack(clip),
	}

# ------------------------------------------------------------------- rows ---

## A generated clip's row: the line and the fields its pack is drawn from, but
## not the pack. A settled gameweek draws a dozen clips nobody opens, and a pack
## is ~10 kB of JSON and gzip apiece — the single largest cost of a settled
## matchday. The row keeps its recipe, and `LeagueClips.pack` draws the picture
## the first time a report asks for it, then caches it in the row.
static func _generated_row(save_seed: int, fixture_id: String, event: Dictionary,
		index: int, score_after: Array, home: String, away: String,
		event_id: int) -> Dictionary:
	var seed := GoalHighlight.seed_for(save_seed, fixture_id, index)
	var fields := _goal_fields({
		"home": home, "away": away, "scorer_id": str(event.get("player_id", "")),
		"scorer": str(event.get("player_name", event.get("detail", ""))),
		"assist_id": str(event.get("assist_id", "")),
		"assist_name": str(event.get("assist_name", "")),
	}, event, fixture_id, index, score_after)
	fields["seed"] = seed
	fields["source"] = "auto"
	fields["commentary"] = GoalHighlight.commentary(fields, seed)
	return {
		"fixture_id": fixture_id, "goal_index": index, "match_event_id": event_id,
		"minute": int(fields["minute"]), "club_id": str(fields["club_id"]),
		"scorer_id": str(fields["player_id"]), "scorer_name": str(fields["player_name"]),
		"assist_id": str(fields["assist_id"]), "assist_name": str(fields["assist_name"]),
		"commentary": str(fields["commentary"]), "source": "auto",
		"codec": GoalHighlight.CODEC, "version": GoalHighlight.VERSION,
		"home_club_id": home, "away_club_id": away,
		"bytes": PackedByteArray(),
	}

## The fields a clip and its line are built from: the report's own scorer,
## assist and minute, plus the club labels the broadcast line names.
static func _goal_fields(source: Dictionary, event: Dictionary, fixture_id: String,
		index: int, score_after: Array) -> Dictionary:
	var home := str(source.get("home", ""))
	var away := str(source.get("away", ""))
	var club := str(event.get("club_id", source.get("club_id", home)))
	var other := away if club == home else home
	return {
		"fixture_id": fixture_id, "goal_index": index,
		"minute": int(event.get("minute", source.get("minute", 0))),
		"home": home, "away": away, "club_id": club,
		"player_id": str(source.get("scorer_id", event.get("player_id", ""))),
		"player_name": str(source.get("scorer", event.get("player_name", ""))),
		"assist_id": str(source.get("assist_id", event.get("assist_id", ""))),
		"assist_name": str(source.get("assist_name", event.get("assist_name", ""))),
		"club_short": short_name(club), "opp_short": short_name(other),
		"score_after": [int(score_after[0]), int(score_after[1])],
	}

## The three-letter label the broadcast line uses for a club.
static func short_name(club_id: String) -> String:
	if club_id == "":
		return ""
	var team := TeamData.get_team(club_id)
	return str(team.get("short", club_id))

## The ledger rows a watched match leaves behind: goals and cards, mapped
## from the engine's own event log to the report's event kinds.
static func engine_events(engine, fixture_id: String) -> Array:
	var rows: Array = []
	for e in engine.events:
		var kind := str(e.get("type", ""))
		if kind != "goal" and kind != "card":
			continue
		var p = engine.by_id.get(int(e.get("player_id", -1)), null)
		if p == null:
			continue
		var mapped := "goal"
		if kind == "card":
			mapped = "red" if p.red else "yellow"
		rows.append({
			"fixture_id": fixture_id,
			"minute": int(e.get("minute", 0)),
			"kind": mapped,
			"player_id": str(p.key),
			"club_id": str(engine.teams[int(e.get("team", 0))]["id"]),
			"detail": str(p.name),
		})
	return rows
