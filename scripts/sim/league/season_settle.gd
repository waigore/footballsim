class_name SeasonSettle
extends RefCounted


const LINKED_KEY := "linked_end"


static func apply(season: LeagueSeason) -> Dictionary:
	if not settled(season):
		return {}
	var stored := stored_payload(season)
	if not stored.is_empty():
		return stored
	var payload := build(season)
	if payload.is_empty():
		return {}
	if payload.has("pyramid"):
		LeaguePyramid.apply(season, payload["pyramid"])
	if payload.has("promotion"):
		LeaguePromotion.apply(season, payload["promotion"])
	season.save.put_meta(LINKED_KEY, JSON.stringify(payload))
	return payload


static func settled(season: LeagueSeason) -> bool:
	if season == null or season.save == null or season.record == null:
		return false
	if not season.save.ensure_open():
		return false
	return season.record.fixtures.unplayed() == 0


static func stored_payload(season: LeagueSeason) -> Dictionary:
	if season == null or season.save == null:
		return {}
	var stored: Variant = season.save.meta.get(LINKED_KEY, "")
	if stored is String and str(stored) != "":
		var parsed: Variant = JSON.parse_string(str(stored))
		if parsed is Dictionary:
			return parsed
	return {}


static func read(season: LeagueSeason) -> Dictionary:
	var stored := stored_payload(season)
	if not stored.is_empty():
		return stored
	return build(season)


static func build(season: LeagueSeason) -> Dictionary:
	if not settled(season):
		return {}
	var payload := {}
	var brackets := LeaguePlayoffs.build_all(season)
	if not brackets.is_empty():
		payload["playoffs"] = brackets
		var pyramid := LeaguePyramid.movers(season, brackets)
		if not pyramid.is_empty():
			payload["pyramid"] = pyramid
	var playouts := LeagueSerieB.playouts(season)
	if not playouts.is_empty():
		payload["playout"] = playouts
	var tie := LeagueRelegation.build(season)
	if not tie.is_empty():
		payload["relegation"] = tie
		var movers := LeaguePromotion.movers(season, tie)
		if not movers.is_empty():
			payload["promotion"] = movers
	return payload
