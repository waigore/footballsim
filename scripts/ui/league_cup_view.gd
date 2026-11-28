class_name LeagueCupView
extends RefCounted


const SEEN_KEY := "cup_draw_seen"


static func stage_name(competition_id: String, round_id: String) -> String:
	if round_id == "":
		return ""
	var rule := LeagueCup.round_rule(competition_id, round_id)
	var label := str(rule.get("name", round_id))
	return label.to_upper() if label != "" else round_id.to_upper()


static func short_name(competition_id: String) -> String:
	var comp := PLRepository.shared().competition(competition_id)
	return str(comp.get("short_name", comp.get("name", competition_id)))


static func long_name(competition_id: String) -> String:
	var comp := PLRepository.shared().competition(competition_id)
	return str(comp.get("name", competition_id))


static func next_date(competition_id: String) -> String:
	var row := PLDatabase.row(
		"SELECT MIN(kickoff) AS d FROM league_fixture WHERE competition_id = ? "
		+ "AND status <> 'played';", [competition_id])
	if row.get("d", null) == null:
		return ""
	return str(row["d"])


static func clubs_left(competition_id: String) -> int:
	if LeagueCupState.winner(competition_id) != "":
		return 1
	var stage := LeagueCupState.stage(competition_id)
	if stage == "":
		return 0
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = ? AND round_id = ?;",
		[competition_id, stage])
	var ties := int(row.get("n", 0))
	if ties > 0:
		return ties * 2
	return LeagueCup.entrants(competition_id, stage).size()


static func draw_seen(save: LeagueSave, competition_id: String, round_id: String) -> bool:
	if save == null or round_id == "":
		return true
	return ("," + str(save.meta.get(SEEN_KEY, "")) + ",").find(
		",%s|%s," % [competition_id, round_id]) >= 0


static func mark_draw_seen(season: LeagueSeason, competition_id: String, round_id: String) -> void:
	if season == null or season.save == null or round_id == "":
		return
	if draw_seen(season.save, competition_id, round_id):
		return
	var seen := str(season.save.meta.get(SEEN_KEY, ""))
	var entry := "%s|%s" % [competition_id, round_id]
	season.save.put_meta(SEEN_KEY, entry if seen == "" else seen + "," + entry)


static func pending_draw(season: LeagueSeason, competition_id: String, round_id: String) -> bool:
	if season == null or round_id == "" or LeagueCupState.winner(competition_id) != "":
		return false
	if not LeagueCup.has_round(competition_id, round_id):
		return false
	return not draw_seen(season.save, competition_id, round_id)


static func card(season: LeagueSeason, competition_id: String) -> Dictionary:
	var stage := LeagueCupState.stage(competition_id)
	var honour := LeagueCupState.honours(competition_id)
	return {
		"id": competition_id, "name": short_name(competition_id),
		"full": long_name(competition_id), "kind": LeagueCup.kind(competition_id),
		"stage": stage, "stage_name": stage_name(competition_id, stage),
		"next_date": next_date(competition_id), "clubs": clubs_left(competition_id),
		"winner": str(honour.get("winner_name", "")),
		"complete": not honour.is_empty(),
		"pending_draw": pending_draw(season, competition_id, stage),
	}


static func cups(season: LeagueSeason) -> Array:
	var out: Array = []
	if season == null or season.save == null:
		return out
	for cid in LeagueCup.active_ids(season.save):
		out.append(card(season, str(cid)))
	return out


static func cup(season: LeagueSeason, competition_id: String, round_id: String) -> Dictionary:
	var base := {
		"id": competition_id, "name": short_name(competition_id),
		"full": long_name(competition_id), "rounds": [], "ties": [], "chosen": "",
		"stage": "", "stage_name": "", "next_date": "", "clubs": 0, "winner": "",
		"pending_draw": false, "inactive": true, "draw": {}, "field": "",
	}
	var active := LeagueCup.active_ids(season.save) if season != null and season.save != null else []
	if not active.has(competition_id):
		return base
	var rounds := LeagueCupState.bracket(competition_id)
	var stage := LeagueCupState.stage(competition_id)
	var chosen := round_id
	if chosen == "" or LeagueCup.round_index(competition_id, chosen) < 0:
		chosen = stage
	if chosen == "" and not rounds.is_empty():
		chosen = str((rounds[0] as Dictionary).get("id", ""))
	var rail: Array = []
	var ties: Array = []
	for row in rounds:
		var rid := str(row.get("id", ""))
		var legs := fixtures_of(competition_id, rid)
		var decorated: Array = []
		for i in range((row.get("ties", []) as Array).size()):
			var tie: Dictionary = (row["ties"] as Array)[i]
			var slots: Dictionary = legs.get(i, {})
			var copy: Dictionary = tie.duplicate(true)
			copy["index"] = i
			copy["played_fixture"] = str(slots.get("played", ""))
			copy["open_fixture"] = str(slots.get("open", ""))
			decorated.append(copy)
		rail.append({
			"id": rid, "name": stage_name(competition_id, rid), "date": str(row.get("date", "")),
			"count": decorated.size(), "complete": bool(row.get("complete", false)),
			"selected": rid == chosen, "legs": int(row.get("legs", 1)),
			"drawn": LeagueCup.has_round(competition_id, rid), "ties": decorated,
		})
		if rid == chosen:
			ties = decorated
	base["rounds"] = rail
	base["ties"] = ties
	base["chosen"] = chosen
	base["stage"] = stage
	base["stage_name"] = stage_name(competition_id, chosen)
	base["next_date"] = next_date(competition_id)
	base["clubs"] = clubs_left(competition_id)
	base["winner"] = str(LeagueCupState.honours(competition_id).get("winner_name", ""))
	base["pending_draw"] = pending_draw(season, competition_id, chosen)
	base["field"] = LeagueCupPools.field_line(season.save, competition_id)
	base["inactive"] = false
	base["draw"] = draw(season, competition_id, chosen)
	return base


static func draw(season: LeagueSeason, competition_id: String, round_id: String) -> Dictionary:
	var chosen := round_id if round_id != "" else LeagueCupState.stage(competition_id)
	var rule := LeagueCup.round_rule(competition_id, chosen)
	var regional := bool(rule.get("regional", false))
	var pairs: Array = []
	for row in LeagueCupState.bracket(competition_id):
		if str((row as Dictionary).get("id", "")) != chosen:
			continue
		for tie in row.get("ties", []):
			var tie_data: Dictionary = tie
			pairs.append({
				"pot": ("NORTH" if LeagueCup.region_of(str(tie_data["home"])) == "north" else "SOUTH") \
					if regional else "OPEN DRAW",
				"home": str(tie_data["home"]), "away": str(tie_data["away"]),
				"home_name": str(tie_data["home_name"]),
				"away_name": str(tie_data["away_name"]),
				"played": bool(tie_data.get("played", false)),
			})
	return {
		"competition": competition_id, "name": short_name(competition_id),
		"round": chosen, "round_name": stage_name(competition_id, chosen),
		"date": str(rule.get("date", "")), "pairs": pairs,
		"seen": draw_seen(season.save if season != null else null, competition_id, chosen),
		"regional": regional, "legs": int(rule.get("legs", 1)),
	}


static func fixtures_of(competition_id: String, round_id: String) -> Dictionary:
	var out := {}
	for row in PLDatabase.rows(
			"SELECT id, status FROM league_fixture WHERE competition_id = ? AND stage = ? "
			+ "ORDER BY id, leg;", [competition_id, round_id]):
		var index := tie_index(str(row["id"]))
		if index < 0:
			continue
		if not out.has(index):
			out[index] = {"played": "", "open": ""}
		var slot: Dictionary = out[index]
		if str(row.get("status", "")) == "played":
			slot["played"] = str(row["id"])
		elif str(slot["open"]) == "":
			slot["open"] = str(row["id"])
		out[index] = slot
	return out


static func tie_index(fixture_id: String) -> int:
	var parts := fixture_id.split("-")
	if parts.size() < 4:
		return -1
	return int(parts[parts.size() - 2])


static func score_line(tie: Dictionary) -> String:
	if not bool(tie.get("played", false)):
		return ""
	var line := "%d – %d" % [int(tie.get("home_goals", 0)), int(tie.get("away_goals", 0))]
	if int(tie.get("pens_home", -1)) >= 0:
		line += "  (%d–%d PENS)" % [int(tie.get("pens_home", 0)), int(tie.get("pens_away", 0))]
	elif bool(tie.get("extra_time", false)):
		line += "  AET"
	return line
