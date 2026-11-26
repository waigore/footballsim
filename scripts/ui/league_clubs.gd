class_name LeagueClubs
extends RefCounted

## Club rows for the Teams of Interest list and its search. Reads the save the
## game is bound to, so the list always names clubs in the league being simmed.

static func rows(ids: Array) -> Array:
	var out: Array = []
	for raw in ids:
		var club := PLRepository.shared().club(str(raw))
		if club.is_empty():
			continue
		out.append({
			"id": str(club["id"]), "name": str(club["name"]), "abbr": str(club["abbr"]),
			"color": club.get("color", UiChrome.C_GOLD),
		})
	return out

## Autocomplete over the league's clubs. Clubs already on the shortlist never
## come back as an "add", and five suggestions is what fits above the list.
static func search(query: String, exclude: Array) -> Array:
	var q := query.strip_edges().to_lower()
	if q == "":
		return []
	var found: Array = []
	var ids: Array = []
	for comp_id in PLCompetitions.active_ids():
		ids.append_array(PLRepository.shared().club_ids(str(comp_id)))
	for id in ids:
		if exclude.has(str(id)):
			continue
		var club := PLRepository.shared().club(str(id))
		var hay := "%s %s %s" % [str(club.get("name", "")), str(club.get("abbr", "")),
			str(club.get("short", ""))]
		if hay.to_lower().find(q) < 0:
			continue
		found.append({
			"id": str(club["id"]), "name": str(club["name"]), "abbr": str(club["abbr"]),
			"color": club.get("color", UiChrome.C_GOLD),
		})
		if found.size() >= 5:
			break
	return found
