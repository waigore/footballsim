class_name LeagueCupPairings
extends RefCounted


static func field(competition_id: String, ctx: Dictionary) -> Dictionary:
	var spec: Dictionary = _spec(competition_id)
	var entrants: Dictionary = LeagueCup.rules(competition_id).get("entrants", {})
	var rounds := {}
	var labels := {}
	for round_id in spec.keys():
		var slots: Array = spec[round_id]
		var target := int(entrants.get(str(round_id), 0))
		var league := _league(slots)
		var places: Array = ctx.places.get(league, [])
		if places.is_empty():
			return {}
		var picks: Array = []
		var notes := {}
		var pending := ""
		for slot in slots:
			var club_id := _club(slot, ctx)
			if club_id == "":
				pending = _missing(slot)
				continue
			if picks.has(club_id):
				pending = _taken(slot)
				continue
			picks.append(club_id)
			notes[club_id] = _slot_label(slot, ctx)
		picks = _top_up(picks, target, places, notes, pending, league, ctx)
		for club_id in picks:
			labels[club_id] = {"round": str(round_id),
				"source": str(notes.get(club_id, place_name(league, ctx, club_id))),
				"kind": "place" if notes.has(club_id) else "fallback"}
		rounds[str(round_id)] = picks
	return {"rounds": rounds, "labels": labels}


static func four(pairings: Dictionary) -> Array:
	var out: Array = []
	var sce: Variant = pairings.get("SCE", {})
	if sce is Dictionary:
		for club_id in (sce as Dictionary).keys():
			out.append(str(club_id))
	return out


static func place_name(league: String, ctx: Dictionary, club_id: String) -> String:
	var places: Array = ctx.places.get(league, [])
	for i in range(places.size()):
		if str(places[i]) == str(club_id):
			return "%s %s" % [str(ctx.names.get(league, league)),
				LeagueEuropeEntries.ordinal(i + 1)]
	return "LIVE LEAGUE"


static func _spec(competition_id: String) -> Dictionary:
	var data: Variant = LeagueCup.rules(competition_id).get("pairing", {})
	return data if data is Dictionary else {}


static func _top_up(picks: Array, target: int, places: Array, notes: Dictionary,
		pending: String, league: String, ctx: Dictionary) -> Array:
	var head := pending
	for club_id in places:
		if picks.size() >= target:
			break
		if picks.has(club_id):
			continue
		picks.append(club_id)
		var place := place_name(league, ctx, club_id)
		notes[club_id] = place if head == "" else head + " · " + place
		head = ""
	return picks


static func _club(slot: Dictionary, ctx: Dictionary) -> String:
	if slot.has("cup"):
		var results: Dictionary = ctx.cups.get(str(slot["cup"]), {})
		return str(results.get(str(slot.get("result", "winner")), ""))
	var places: Array = ctx.places.get(str(slot.get("league", "")), [])
	var place := int(slot.get("place", 0))
	if place < 1 or place > places.size():
		return ""
	return str(places[place - 1])


static func _slot_label(slot: Dictionary, ctx: Dictionary) -> String:
	if slot.has("cup"):
		return _cup_name(slot) + _result_name(slot)
	var league := str(slot.get("league", ""))
	return "%s %s" % [str(ctx.names.get(league, league)), LeagueEuropeEntries.ordinal(
		int(slot.get("place", 0)))]


static func _missing(slot: Dictionary) -> String:
	if not slot.has("cup"):
		return ""
	return _cup_name(slot) + " OFF"


static func _taken(slot: Dictionary) -> String:
	if not slot.has("cup"):
		return ""
	return _cup_name(slot) + _result_name(slot) + " IN"


static func _cup_name(slot: Dictionary) -> String:
	var cup := str(slot.get("cup", ""))
	return str(LeagueEuropeEntries.CUP_NAMES.get(cup, cup))


static func _result_name(slot: Dictionary) -> String:
	return " WINNER" if str(slot.get("result", "winner")) == "winner" else " RUNNER-UP"


static func _league(slots: Array) -> String:
	for slot in slots:
		if (slot as Dictionary).has("league"):
			return str((slot as Dictionary)["league"])
	return ""
