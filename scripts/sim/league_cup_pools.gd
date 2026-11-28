class_name LeagueCupPools
extends RefCounted


static var _stubs := {}


static func rebuild(season: LeagueSeason, previous_index: int, winners: Dictionary,
		runners: Dictionary) -> Dictionary:
	var out := {"cups": 0, "supercups": 0}
	if season == null or season.save == null:
		return out
	if str(season.save.meta.get("cups", "off")) != "on":
		return out
	var off := str(season.save.meta.get("cups_off", ""))
	_stubs = _stub_roles()
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for country in LeagueCup.countries():
		var name := str(country)
		if _is_off(off, name):
			continue
		var leagues := _leagues(name)
		if leagues.is_empty() or not _active(season.save, leagues):
			continue
		if _places(previous_index, str(leagues[0])).is_empty():
			continue
		var filled := _fill(name, previous_index, winners, runners)
		out["cups"] = int(out["cups"]) + int(filled.get("cups", 0))
		out["supercups"] = int(out["supercups"]) + int(filled.get("supercups", 0))
	PLDatabase.transaction("COMMIT;")
	return out


static func _fill(country: String, previous: int, winners: Dictionary,
		runners: Dictionary) -> Dictionary:
	match country:
		"England":
			return _england(previous, winners, runners)
		"Spain":
			return _spain(previous, winners, runners)
		"Germany":
			return _germany(previous, winners, runners)
		"Italy":
			return _italy(previous, winners, runners)
	return {"cups": 0, "supercups": 0}


static func _england(previous: int, winners: Dictionary,
		runners: Dictionary) -> Dictionary:
	var pl := _tier(previous, "PL")
	var ch := _tier(previous, "CH")
	var l1 := _tier(previous, "L1")
	var l2 := _tier(previous, "L2")
	var nl := _tier(previous, "NL")
	var pr := _tail(l2, _slots("EFLC", "PR"))
	var later := _byes(pl, _slots("EFLC", "R3"))
	_clear("FAC")
	_add("FAC", "R3", pl + ch)
	_add("FAC", "R1", l1 + l2 + nl)
	_clear("EFLC")
	_add("EFLC", "PR", pr)
	_add("EFLC", "R1", ch + l1 + _without(l2, pr))
	_add("EFLC", "R2", _without(pl, later))
	_add("EFLC", "R3", later)
	_clear("CS")
	_add("CS", "F", _duel(_places(previous, "PL"), winners, runners, "FAC"))
	return {"cups": 2, "supercups": 1}


static func _spain(previous: int, winners: Dictionary,
		runners: Dictionary) -> Dictionary:
	var ll := _tier(previous, "LL")
	var four := _supercopa_four(_places(previous, "LL"), winners, runners)
	_clear("SCE")
	_add("SCE", "SF", four)
	_clear("CDR")
	_add("CDR", "R32", four)
	_add("CDR", "R1", _without(ll, four))
	return {"cups": 1, "supercups": 1}


static func _germany(previous: int, winners: Dictionary,
		runners: Dictionary) -> Dictionary:
	var bl := _tier(previous, "BL")
	var bl2 := _tier(previous, "BL2")
	_clear("DFBP")
	_add("DFBP", "R1", bl + bl2)
	_clear("DFLS")
	_add("DFLS", "F", _duel(_places(previous, "BL"), winners, runners, "DFBP"))
	return {"cups": 1, "supercups": 1}


static func _italy(previous: int, winners: Dictionary,
		runners: Dictionary) -> Dictionary:
	var sa := _tier(previous, "SA")
	var sb := _tier(previous, "SB")
	var r16 := _head(sa, _slots("CI", "R16"))
	var pr := _tail(sb, _slots("CI", "PR"))
	_clear("CI")
	_add("CI", "PR", pr)
	_add("CI", "R16", r16)
	_add("CI", "R1", _without(sa, r16) + _without(sb, pr))
	_clear("SCI")
	_add("SCI", "F", _duel(_places(previous, "SA"), winners, runners, "CI"))
	return {"cups": 1, "supercups": 1}


static func _duel(places: Array, winners: Dictionary, runners: Dictionary,
		cup: String) -> Array:
	if places.is_empty():
		return []
	var champion := str(places[0])
	var opponent := str(winners.get(cup, ""))
	if opponent == "" or opponent == champion:
		opponent = str(places[1]) if places.size() > 1 else str(runners.get(cup, ""))
	if opponent == "" or opponent == champion:
		return []
	return [champion, opponent]


static func _supercopa_four(ll: Array, winners: Dictionary, runners: Dictionary) -> Array:
	var four: Array = []
	for i in range(mini(2, ll.size())):
		four.append(str(ll[i]))
	for pick in [str(winners.get("CDR", "")), str(runners.get("CDR", ""))]:
		if pick == "" or four.has(pick):
			continue
		four.append(pick)
	for club_id in ll:
		if four.size() >= 4:
			break
		if not four.has(str(club_id)):
			four.append(str(club_id))
	return four.slice(0, 4)


static func _byes(pl: Array, count: int) -> Array:
	if count <= 0:
		return []
	var europe := _european()
	var later: Array = []
	for club_id in pl:
		if later.size() >= count:
			break
		if europe.has(str(club_id)):
			later.append(str(club_id))
	for club_id in pl:
		if later.size() >= count:
			break
		if not later.has(str(club_id)):
			later.append(str(club_id))
	return later


static func _european() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE member_kind = 'club' "
			+ "AND competition_id IN ('UCL', 'UEL', 'UECL');"):
		out[str(row["member_id"])] = true
	return out


static func _tier(previous: int, league: String) -> Array:
	return _order(_places(previous, league), _club_ids(league))


static func _places(previous: int, league: String) -> Array:
	var out: Array = []
	for row in SeasonArchive.table(previous, league):
		out.append(str(row["club_id"]))
	return out


static func _club_ids(league: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT id FROM club WHERE competition_id = ? ORDER BY name;", [league]):
		out.append(str(row["id"]))
	return out


static func _order(places: Array, ids: Array) -> Array:
	var rank := {}
	for i in range(places.size()):
		rank[str(places[i])] = i
	var out: Array = ids.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool: return _before(str(a), str(b), rank))
	return out


static func _before(a: String, b: String, rank: Dictionary) -> bool:
	var ra := int(rank.get(a, 1048576))
	var rb := int(rank.get(b, 1048576))
	if ra != rb:
		return ra < rb
	return a < b


static func _clear(competition_id: String) -> void:
	PLDatabase.execute(
		"DELETE FROM competition_member WHERE member_kind = 'club' AND competition_id = ?;",
		[competition_id])
	var roles := {}
	for club_id in _stubs.get(competition_id, {}):
		var role := str((_stubs[competition_id] as Dictionary)[club_id])
		if not roles.has(role):
			roles[role] = []
		(roles[role] as Array).append(str(club_id))
	for role in roles:
		_add(competition_id, str(role), roles[role])


static func _add(competition_id: String, role: String, ids: Array) -> void:
	if ids.is_empty():
		return
	var marks: Array = []
	var values: Array = []
	for club_id in ids:
		marks.append("(?, 'club', ?, ?)")
		values.append_array([competition_id, str(club_id), role])
	PLDatabase.execute(
		"INSERT OR IGNORE INTO competition_member (competition_id, member_kind, member_id, role) "
		+ "VALUES " + ", ".join(marks) + ";", values)


static func _stub_roles() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows(
			"SELECT m.competition_id, m.role, m.member_id FROM competition_member m "
			+ "JOIN club c ON c.id = m.member_id WHERE m.member_kind = 'club' "
			+ "AND c.competition_id = m.competition_id;"):
		var competition_id := str(row["competition_id"])
		if not out.has(competition_id):
			out[competition_id] = {}
		(out[competition_id] as Dictionary)[str(row["member_id"])] = str(row["role"])
	return out


static func _slots(competition_id: String, round_id: String) -> int:
	var entrants: Variant = LeagueCup.rules(competition_id).get("entrants", {})
	if not entrants is Dictionary:
		return 0
	var total := int((entrants as Dictionary).get(round_id, 0))
	var filled := 0
	for club_id in _stubs.get(competition_id, {}):
		if str((_stubs[competition_id] as Dictionary)[club_id]) == round_id:
			filled += 1
	return maxi(total - filled, 0)


static func _leagues(country: String) -> Array:
	var list: Variant = LeagueCup.COUNTRY_LEAGUES.get(country, [])
	return list if list is Array else []


static func _active(save: LeagueSave, leagues: Array) -> bool:
	for league in leagues:
		if save.actives.has(str(league)):
			return true
	return false


static func _is_off(off: String, country: String) -> bool:
	return off != "" and ("," + off + ",").find("," + country + ",") >= 0


static func _tail(ids: Array, count: int) -> Array:
	if count <= 0 or ids.is_empty():
		return []
	return ids.slice(maxi(ids.size() - count, 0))


static func _head(ids: Array, count: int) -> Array:
	if count <= 0 or ids.is_empty():
		return []
	return ids.slice(0, mini(count, ids.size()))


static func _without(ids: Array, remove: Array) -> Array:
	var drop := {}
	for club_id in remove:
		drop[str(club_id)] = true
	var out: Array = []
	for club_id in ids:
		if not drop.has(str(club_id)):
			out.append(str(club_id))
	return out
