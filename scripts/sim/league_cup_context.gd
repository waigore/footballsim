class_name LeagueCupContext
extends RefCounted


static func build(save: LeagueSave, played_index: int, cups: Dictionary) -> Dictionary:
	var ctx := {"places": {}, "ranked": {}, "rank": {}, "names": {},
		"europe": _europe(save), "stubs": {}, "cups": cups}
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


static func _europe(save: LeagueSave) -> Array:
	var out: Array = []
	if save == null or str(save.meta.get("uefa", "off")) != "on":
		return out
	for cid in LeagueUefa.IDS:
		for round_id in LeagueUefa.round_ids(str(cid)):
			for club_id in LeagueUefa.entrants(str(cid), str(round_id)):
				if not out.has(str(club_id)):
					out.append(str(club_id))
	return out
