class_name LeagueUefaBands
extends RefCounted


const KEY := "uefa_bands"


static func ensure(season: LeagueSeason) -> bool:
	if season == null or season.save == null:
		return false
	if str(season.save.meta.get(KEY, "")) != "":
		return false
	var ids := LeagueUefa.active_ids(season.save)
	if ids.is_empty():
		return false
	var store := {}
	for competition_id in ids:
		var bands := _seed_bands(str(competition_id))
		if not bands.is_empty():
			store[str(competition_id)] = bands
	if store.is_empty():
		return false
	season.save.put_meta(KEY, JSON.stringify(store))
	return true


static func store(save: LeagueSave) -> Dictionary:
	if save == null:
		return {}
	var raw := str(save.meta.get(KEY, ""))
	if raw == "":
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func bands_of(save: LeagueSave, competition_id: String) -> Dictionary:
	var row: Variant = store(save).get(competition_id, {})
	return row if row is Dictionary else {}


static func band(save: LeagueSave, competition_id: String, club_id: String) -> int:
	var stored := bands_of(save, competition_id)
	if stored.has(club_id):
		return int(stored[club_id])
	var peers := _association_bands(save, competition_id, club_id, stored)
	if not peers.is_empty():
		peers.sort()
		return int(peers[peers.size() / 2])
	return LeagueUefa.pots(competition_id) / 2 + 1


static func pots(save: LeagueSave, competition_id: String, clubs: Array) -> Array:
	var count := maxi(LeagueUefa.pots(competition_id), 1)
	var size := int(ceil(float(clubs.size()) / float(count)))
	var rows: Array = []
	for club_id in clubs:
		rows.append({"id": str(club_id), "band": band(save, competition_id, str(club_id))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["band"]) == int(b["band"]):
			return str(a["id"]) < str(b["id"])
		return int(a["band"]) < int(b["band"]))
	var out: Array = []
	for p in range(count):
		var slice := rows.slice(p * size, mini((p + 1) * size, rows.size()))
		var ids: Array = []
		for row in slice:
			ids.append(str((row as Dictionary)["id"]))
		if not ids.is_empty():
			out.append(ids)
	return out


static func _seed_bands(competition_id: String) -> Dictionary:
	var ranked: Array = []
	for row in PLDatabase.rows(
			"SELECT DISTINCT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club';", [competition_id]):
		var club_id := str(row["member_id"])
		ranked.append({"id": club_id, "rank": LeagueUefa.club_rank(club_id)})
	if ranked.is_empty():
		return {}
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["rank"]), float(b["rank"])):
			return str(a["id"]) < str(b["id"])
		return float(a["rank"]) > float(b["rank"]))
	var count := maxi(LeagueUefa.pots(competition_id), 1)
	var size := maxi(int(ceil(float(ranked.size()) / float(count))), 1)
	var out := {}
	for i in range(ranked.size()):
		out[str((ranked[i] as Dictionary)["id"])] = mini(i / size + 1, count)
	return out


static func _association_bands(save: LeagueSave, competition_id: String, club_id: String,
		stored: Dictionary) -> Array:
	var association := LeagueUefa.association_of(club_id)
	var out: Array = []
	if association == "":
		return out
	for row in PLDatabase.rows(
			"SELECT DISTINCT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club';", [competition_id]):
		var peer := str(row["member_id"])
		if not stored.has(peer):
			continue
		if LeagueUefa.association_of(peer) == association:
			out.append(int(stored[peer]))
	return out
