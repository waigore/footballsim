class_name LeagueUefaBands
extends RefCounted


const BANDS_KEY := "uefa_bands"


static func pot_bands(competition_id: String) -> Dictionary:
	var data: Variant = LeagueUefa.rules(competition_id).get("pot_bands", {})
	return data if data is Dictionary else {}


static func saved_bands(save: LeagueSave) -> Dictionary:
	if save == null:
		return {}
	var parsed: Variant = JSON.parse_string(str(save.meta.get(BANDS_KEY, "{}")))
	return parsed if parsed is Dictionary else {}


static func ensure_bands(save: LeagueSave, competition_id: String, clubs: Array) -> Dictionary:
	var known: Dictionary = pot_bands(competition_id).duplicate()
	known.merge(saved_bands(save), true)
	var missing: Array = []
	for club in clubs:
		if not known.has(str(club)):
			missing.append(str(club))
	if missing.is_empty():
		return known
	var members: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club';", [competition_id]):
		members.append(str(row["member_id"]))
	var stored := saved_bands(save)
	for club in missing:
		var iso := LeagueUefa.association_of(str(club))
		var peers: Array = []
		for other in members:
			if str(other) == str(club) or LeagueUefa.association_of(str(other)) != iso:
				continue
			if known.has(str(other)):
				peers.append(int(known[str(other)]))
		stored[str(club)] = _median(peers)
		known[str(club)] = int(stored[str(club)])
	if save != null:
		save.put_meta(BANDS_KEY, JSON.stringify(stored))
	return known


static func band(known: Dictionary, club_id: String) -> int:
	return int(known.get(club_id, 3))


static func ranked(known: Dictionary, clubs: Array) -> Array:
	var out: Array = []
	for club_id in clubs:
		out.append(str(club_id))
	out.sort_custom(func(a: String, b: String) -> bool:
		var left := band(known, a)
		var right := band(known, b)
		if left != right:
			return left < right
		var left_name := LeagueUefa.club_name(a)
		var right_name := LeagueUefa.club_name(b)
		if left_name != right_name:
			return left_name < right_name
		return a < b
	)
	return out


static func _median(peers: Array) -> int:
	if peers.is_empty():
		return 3
	var sorted := peers.duplicate()
	sorted.sort()
	var mid := int(sorted.size() / 2)
	if sorted.size() % 2 == 1:
		return int(sorted[mid])
	return int(round((float(sorted[mid - 1]) + float(sorted[mid])) / 2.0))
