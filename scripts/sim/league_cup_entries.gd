class_name LeagueCupEntries
extends RefCounted


const META := "cup_entries"


static func regenerate(season: LeagueSeason, played_index: int, cups: Dictionary) -> Dictionary:
	var out := {"ok": false, "pairings": {}, "carried": []}
	if season == null or season.save == null or not season.save.ensure_open():
		return out
	var ids := LeagueCup.active_ids(season.save)
	if ids.is_empty() or not _has_spec(ids):
		return out
	var ctx := _context(played_index, cups)
	var carried: Array = []
	var entries := {}
	for cid in ids:
		if _spec(str(cid), "pairing").is_empty():
			continue
		var field := _field(str(cid), ctx)
		if field.is_empty():
			carried.append(str(cid))
			continue
		_write(str(cid), field["rounds"])
		entries[str(cid)] = field["labels"]
		out["pairings"][str(cid)] = field["labels"]
	var four := _four(out["pairings"])
	for cid in ids:
		if _spec(str(cid), "entry").is_empty():
			continue
		var pool := _pool(str(cid), ctx, four)
		if pool.is_empty():
			carried.append(str(cid))
			continue
		_write(str(cid), pool["rounds"])
		entries[str(cid)] = pool["labels"]
	out["ok"] = true
	out["carried"] = carried
	_store(season.save, played_index, entries, carried)
	return out


static func reading(save: LeagueSave, competition_id: String) -> Dictionary:
	var rows: Variant = _stored(save).get("entries", {})
	if not (rows is Dictionary):
		return {}
	var cup: Variant = (rows as Dictionary).get(competition_id, {})
	return cup if cup is Dictionary else {}


static func note(save: LeagueSave, competition_id: String) -> String:
	var labels := reading(save, competition_id)
	if labels.is_empty():
		return ""
	if carried(save).has(competition_id):
		return "CARRIED OVER"
	var parts: Array = []
	for club_id in _ordered(competition_id, labels):
		var row: Dictionary = labels[str(club_id)]
		var source := str(row.get("source", ""))
		if source != "" and not parts.has(source):
			parts.append(source)
	return " · ".join(PackedStringArray(parts))


static func carried(save: LeagueSave) -> Array:
	var list: Variant = _stored(save).get("carried", [])
	return list if list is Array else []


static func _stored(save: LeagueSave) -> Dictionary:
	if save == null:
		return {}
	var parsed: Variant = JSON.parse_string(str(save.meta.get(META, "{}")))
	return parsed if parsed is Dictionary else {}


static func _context(played_index: int, cups: Dictionary) -> Dictionary:
	var ctx := {"places": {}, "ranked": {}, "rank": {}, "names": {},
		"europe": _europe(), "stubs": {}, "cups": cups}
	for row in PLRepository.shared().leagues():
		var cid := str(row.get("id", ""))
		if cid == "":
			continue
		ctx.names[cid] = str(row.get("short_name", cid))
		var current: Array = []
		for club in PLDatabase.rows(
				"SELECT id FROM club WHERE competition_id = ? ORDER BY id;", [cid]):
			current.append(str(club["id"]))
		var places: Array = []
		for line in SeasonArchive.table(played_index, cid):
			places.append(str(line["club_id"]))
		ctx.places[cid] = places
		var rank := {}
		for i in range(places.size()):
			rank[str(places[i])] = i + 1
		ctx.rank[cid] = rank
		var ranked: Array = current.duplicate()
		ranked.sort_custom(_before(rank))
		ctx.ranked[cid] = ranked
	for row in PLDatabase.rows(
			"SELECT id, competition_id, tier FROM club WHERE stub = 1 ORDER BY id;"):
		var cup := str(row["competition_id"])
		if not ctx.stubs.has(cup):
			ctx.stubs[cup] = []
		(ctx.stubs[cup] as Array).append({"id": str(row["id"]), "tier": int(row["tier"])})
	return ctx


static func _before(rank: Dictionary) -> Callable:
	return func(a: Variant, b: Variant) -> bool:
		var pa := int(rank.get(str(a), 999))
		var pb := int(rank.get(str(b), 999))
		if pa != pb:
			return pa < pb
		return str(a) < str(b)


static func _europe() -> Array:
	var out: Array = []
	for cid in LeagueUefa.IDS:
		for round_id in LeagueUefa.round_ids(str(cid)):
			for club_id in LeagueUefa.entrants(str(cid), str(round_id)):
				if not out.has(str(club_id)):
					out.append(str(club_id))
	return out


static func _field(competition_id: String, ctx: Dictionary) -> Dictionary:
	var spec := _spec(competition_id, "pairing")
	var entrants: Dictionary = LeagueCup.rules(competition_id).get("entrants", {})
	var rounds := {}
	var labels := {}
	for round_id in spec.keys():
		var slots: Array = spec[round_id]
		var target := int(entrants.get(str(round_id), 0))
		var league := _pair_league(slots)
		var places: Array = ctx.places.get(league, [])
		if places.is_empty():
			return {}
		var picks: Array = []
		var notes := {}
		var pending := ""
		for slot in slots:
			var club_id := _pair_club(slot, ctx)
			if club_id == "":
				pending = _missing(slot, ctx)
				continue
			if picks.has(club_id):
				pending = _taken(slot, ctx)
				continue
			picks.append(club_id)
			notes[club_id] = _pair_label(slot, ctx)
		picks = _top_up(picks, target, places, notes, pending)
		for club_id in picks:
			labels[club_id] = {"round": str(round_id),
				"source": str(notes.get(club_id, place_name(league, ctx, club_id))),
				"kind": "place" if notes.has(club_id) else "fallback"}
		rounds[str(round_id)] = picks
	return {"rounds": rounds, "labels": labels}


static func _top_up(picks: Array, target: int, places: Array, notes: Dictionary,
		pending: String) -> Array:
	var head := pending
	for club_id in places:
		if picks.size() >= target:
			break
		if picks.has(club_id):
			continue
		picks.append(club_id)
		var place := club_id
		for i in range(places.size()):
			if str(places[i]) == str(club_id):
				place = "%s %s" % [place, LeagueEuropeEntries.ordinal(i + 1)]
				break
		notes[club_id] = place if head == "" else head + " · " + place
		head = ""
	return picks


static func _pair_club(slot: Dictionary, ctx: Dictionary) -> String:
	if slot.has("cup"):
		var results: Dictionary = ctx.cups.get(str(slot["cup"]), {})
		return str(results.get(str(slot.get("result", "winner")), ""))
	var places: Array = ctx.places.get(str(slot.get("league", "")), [])
	var place := int(slot.get("place", 0))
	if place < 1 or place > places.size():
		return ""
	return str(places[place - 1])


static func _pair_label(slot: Dictionary, ctx: Dictionary) -> String:
	if slot.has("cup"):
		return _cup_name(slot) + _result_name(slot)
	var league := str(slot.get("league", ""))
	return "%s %s" % [str(ctx.names.get(league, league)), LeagueEuropeEntries.ordinal(
		int(slot.get("place", 0)))]


static func _missing(slot: Dictionary, ctx: Dictionary) -> String:
	if slot.has("cup"):
		return _cup_name(slot) + " OFF"
	return ""


static func _taken(slot: Dictionary, ctx: Dictionary) -> String:
	if slot.has("cup"):
		return _cup_name(slot) + _result_name(slot) + " IN"
	return ""


static func _cup_name(slot: Dictionary) -> String:
	var cup := str(slot.get("cup", ""))
	return str(LeagueEuropeEntries.CUP_NAMES.get(cup, cup))


static func _result_name(slot: Dictionary) -> String:
	return " WINNER" if str(slot.get("result", "winner")) == "winner" else " RUNNER-UP"


static func _pair_league(slots: Array) -> String:
	for slot in slots:
		if (slot as Dictionary).has("league"):
			return str((slot as Dictionary)["league"])
	return ""


static func place_name(league: String, ctx: Dictionary, club_id: String) -> String:
	var places: Array = ctx.places.get(league, [])
	for i in range(places.size()):
		if str(places[i]) == str(club_id):
			return "%s %s" % [str(ctx.names.get(league, league)),
				LeagueEuropeEntries.ordinal(i + 1)]
	return "LIVE LEAGUE"


static func _pool(competition_id: String, ctx: Dictionary, four: Array) -> Dictionary:
	var spec := _spec(competition_id, "entry")
	var entrants: Dictionary = LeagueCup.rules(competition_id).get("entrants", {})
	var rounds: Array = LeagueCup.rounds(competition_id)
	var taken := {}
	var out_rounds := {}
	var labels := {}
	for i in range(rounds.size() - 1, -1, -1):
		var round_id := str((rounds[i] as Dictionary).get("id", ""))
		if not spec.has(round_id):
			continue
		var target := int(entrants.get(round_id, 0))
		var picks: Array = []
		var notes := {}
		for slot in spec[round_id]:
			for club_id in _slot(slot, competition_id, ctx, four, taken):
				if picks.has(club_id):
					continue
				picks.append(club_id)
				notes[club_id] = _label(slot)
		picks = _fill(picks, target, competition_id, ctx, taken)
		for club_id in picks:
			taken[club_id] = round_id
			labels[club_id] = {"round": round_id,
				"source": str(notes.get(club_id, "LEAGUE FILL")),
				"kind": "pool" if notes.has(club_id) else "fallback"}
		out_rounds[round_id] = picks
	return {"rounds": out_rounds, "labels": labels}


static func _fill(picks: Array, target: int, competition_id: String, ctx: Dictionary,
		taken: Dictionary) -> Array:
	if picks.size() > target:
		picks.resize(target)
	for club_id in _reserve(competition_id, ctx):
		if picks.size() >= target:
			break
		if picks.has(club_id) or taken.has(club_id):
			continue
		picks.append(club_id)
	return picks


static func _reserve(competition_id: String, ctx: Dictionary) -> Array:
	var country := str(PLRepository.shared().competition(competition_id).get("country", ""))
	var leagues: Array = LeagueCup.COUNTRY_LEAGUES.get(country, [])
	var out: Array = []
	for i in range(leagues.size()):
		var league := str(leagues[i])
		if i == 0:
			out.append_array(ctx.places.get(league, []))
			continue
		out.append_array(ctx.ranked.get(league, []))
	return out


static func _slot(slot: Dictionary, competition_id: String, ctx: Dictionary,
		four: Array, taken: Dictionary) -> Array:
	if slot.has("stubs"):
		return _stubs(competition_id, ctx, slot["stubs"], taken)
	var league := str(slot.get("league", ""))
	var ranked: Array = ctx.ranked.get(league, [])
	var out: Array = []
	var only := str(slot.get("only", ""))
	var without := str(slot.get("without", ""))
	for club_id in ranked:
		var club := str(club_id)
		if taken.has(club):
			continue
		var place := int((ctx.rank.get(league, {}) as Dictionary).get(club, 999))
		if slot.has("to") and place > int(slot["to"]):
			continue
		if slot.has("from") and place < int(slot["from"]):
			continue
		if only == "supercopa" and not four.has(club):
			continue
		if without == "supercopa" and four.has(club):
			continue
		if slot.has("europe") and bool(ctx.europe.has(club)) != bool(slot["europe"]):
			continue
		out.append(club)
	return out


static func _stubs(competition_id: String, ctx: Dictionary, rule: Variant,
		taken: Dictionary) -> Array:
	var spec: Dictionary = rule if rule is Dictionary else {}
	var out: Array = []
	for row in ctx.stubs.get(competition_id, []):
		var club: Dictionary = row
		var club_id := str(club.get("id", ""))
		if taken.has(club_id) or not _tier_ok(int(club.get("tier", 0)), spec):
			continue
		out.append(club_id)
	return out


static func _tier_ok(tier: int, spec: Dictionary) -> bool:
	if spec.has("tier") and tier != int(spec["tier"]):
		return false
	if spec.has("min_tier") and tier < int(spec["min_tier"]):
		return false
	if spec.has("max_tier") and tier > int(spec["max_tier"]):
		return false
	return true


static func _label(slot: Dictionary) -> String:
	if slot.has("stubs"):
		return "STUB SLOT"
	var league := str(slot.get("league", ""))
	if slot.has("europe"):
		return "%s %s" % [league, "IN EUROPE" if bool(slot["europe"]) else "NO EUROPE"]
	if slot.has("only"):
		return "SUPERCOPA FIELD"
	if slot.has("from") or slot.has("to"):
		return "%s %s" % [league, _band(slot)]
	return "%s CLUBS" % league


static func _band(slot: Dictionary) -> String:
	if slot.has("to") and slot.has("from"):
		return "%d-%d" % [int(slot["from"]), int(slot["to"])]
	if slot.has("to"):
		return "TOP %d" % int(slot["to"])
	return "%d DOWN" % int(slot["from"])


static func _four(pairings: Dictionary) -> Array:
	var out: Array = []
	var sce: Variant = pairings.get("SCE", {})
	if sce is Dictionary:
		for club_id in (sce as Dictionary).keys():
			out.append(str(club_id))
	return out


static func _has_spec(ids: Array) -> bool:
	for cid in ids:
		if not _spec(str(cid), "entry").is_empty():
			return true
		if not _spec(str(cid), "pairing").is_empty():
			return true
	return false


static func _spec(competition_id: String, key: String) -> Dictionary:
	var data: Variant = LeagueCup.rules(competition_id).get(key, {})
	return data if data is Dictionary else {}


static func _ordered(competition_id: String, labels: Dictionary) -> Array:
	var out: Array = []
	for row in LeagueCup.rounds(competition_id):
		var round_id := str((row as Dictionary).get("id", ""))
		for club_id in LeagueCup.entrants(competition_id, round_id):
			if labels.has(club_id):
				out.append(club_id)
	return out


static func _write(competition_id: String, rounds: Dictionary) -> void:
	PLDatabase.execute(
		"DELETE FROM competition_member WHERE competition_id = ? AND member_kind = 'club';",
		[competition_id])
	for round_id in rounds.keys():
		for club_id in rounds[round_id]:
			PLDatabase.execute(
				"INSERT OR IGNORE INTO competition_member (competition_id, member_kind, "
				+ "member_id, role) VALUES (?, 'club', ?, ?);",
				[competition_id, str(club_id), str(round_id)])


static func _store(save: LeagueSave, played_index: int, entries: Dictionary,
		carried_ids: Array) -> void:
	save.put_meta(META, JSON.stringify({"season": played_index, "carried": carried_ids,
		"entries": entries}))
	save.reload()
