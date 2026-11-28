extends RefCounted

## The season verb: create a save, play it out, roll it over, print what the archive holds.
## Only the market's season modules are loaded: no UI, no view, no scenes.


static func run(options: Dictionary) -> Dictionary:
	var seasons := maxi(int(options.get("seasons", "2")), 1)
	var seed_value := int(options.get("seed", "7001"))
	var name := str(options.get("name", "Market Sim"))
	var season := LeagueSeason.create(name, "generated", "fixture_days", seed_value, ["PL"])
	if season == null:
		return {"ok": false, "reason": "the save could not be created"}
	var log: Array = []
	var ok := true
	for i in range(seasons):
		var index := season.save.season_index()
		var finished := _play_out(season)
		if not finished:
			ok = false
			log.append({"season": index, "reason": "the season never finished"})
			break
		var first := _first_fixture(season)
		var settled := SeasonSettle.apply(season)
		var again := SeasonSettle.apply(season)
		var rollover := SeasonRollover.apply(season)
		if not bool(rollover.get("ok", false)):
			ok = false
			log.append({"season": index, "reason": "the rollover refused", "detail": rollover})
			break
		log.append({
			"season": index,
			"first_fixture": first,
			"archived_clubs": int((rollover["archived"] as Dictionary).get("clubs", 0)),
			"archived_players": int((rollover["archived"] as Dictionary).get("players", 0)),
			"retired": int((rollover["aged"] as Dictionary).get("retired", 0)),
			"next_label": str(rollover.get("season_label", "")),
			"next_first_fixture": str(rollover.get("date", "")),
			"settled": not settled.is_empty(),
			"settle_repeat_is_a_no_op": _same(settled, again),
			"archive_fingerprint": _fingerprint(season, index),
		})
		print("season %d: clubs %d, players %d, retired %d, next %s from %s" % [
			index, int((rollover["archived"] as Dictionary).get("clubs", 0)),
			int((rollover["archived"] as Dictionary).get("players", 0)),
			int((rollover["aged"] as Dictionary).get("retired", 0)),
			str(rollover.get("season_label", "")), str(rollover.get("date", ""))])
	print("archive:")
	for row in SeasonArchive.table(0, ""):
		print("  %s %2d %-4s %3d pts  %s" % [str(row["club_id"]), int(row["position"]),
			str(row["competition_id"]), int(row["points"]), str(row["club_name"])])
	season.close()
	return {"ok": ok, "save": name, "seasons": seasons, "seed": seed_value, "log": log}


static func _play_out(season: LeagueSeason) -> bool:
	var guard := 0
	while season.save.status() != "complete" and guard < 900:
		season.advance()
		guard += 1
	return season.save.status() == "complete"


static func _first_fixture(season: LeagueSeason) -> Dictionary:
	var rows := season.record.fixtures.all(-1, str(season.save.actives[0]))
	if rows.is_empty():
		return {}
	var row: Dictionary = rows[0]
	return {"id": str(row["id"]), "kickoff": str(row["kickoff"])}


static func _fingerprint(season: LeagueSeason, season_index: int) -> String:
	var parts: Array = []
	for row in SeasonArchive.table(season_index, ""):
		parts.append("%s|%s|%d|%d" % [str(row["competition_id"]), str(row["club_id"]),
			int(row["position"]), int(row["points"])])
	return str((";".join(parts)).hash())


static func _same(first: Dictionary, second: Dictionary) -> bool:
	return JSON.stringify(first) == JSON.stringify(second)
