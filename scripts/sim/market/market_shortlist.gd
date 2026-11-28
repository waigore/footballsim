class_name MarketShortlist
extends RefCounted


static var _key := ""
static var _pool: Array = []
static var _by_group: Dictionary = {}
static var _position: Dictionary = {}


static func reset() -> void:
	_key = ""
	_pool = []
	_by_group = {}
	_position = {}


static func index(season: LeagueSeason) -> Array:
	var key := _pool_key(season)
	if key == _key and not _pool.is_empty():
		return _pool
	_key = key
	_pool = []
	_by_group = {}
	_position = {}
	for row in PLDatabase.rows(
			"SELECT p.id, p.club_id, p.pos, p.ovr, p.age FROM player p "
			+ "JOIN club c ON c.id = p.club_id WHERE c.stub = 0 AND p.club_id <> '' "
			+ "ORDER BY p.ovr, p.id;"):
		var entry := {
			"id": str(row.get("id", "")), "club_id": str(row.get("club_id", "")),
			"pos": str(row.get("pos", "")),
			"group": MarketNeeds.group_of(str(row.get("pos", ""))),
			"ovr": int(row.get("ovr", 0)), "age": int(row.get("age", 0)),
		}
		_position[str(entry["id"])] = _pool.size()
		_pool.append(entry)
	for i in range(_pool.size()):
		var entry: Dictionary = _pool[i]
		var group := str(entry["group"])
		if not _by_group.has(group):
			_by_group[group] = []
		(_by_group[group] as Array).append(i)
	return _pool


static func move(player_id: String, club_id: String) -> void:
	if player_id == "" or not _position.has(player_id):
		return
	(_pool[int(_position[player_id])] as Dictionary)["club_id"] = club_id


static func rebuild_for(player_id: String, new_club: String) -> void:
	move(player_id, new_club)


static func _pool_key(season: LeagueSeason) -> String:
	if season == null or season.save == null:
		return ""
	return "%s#%d#%s" % [PLDatabase.current_path(), season.save.season_index(),
		str(season.save.meta.get("seed", "0"))]


static func candidates(season: LeagueSeason, date: String, club_id: String, group: String,
		ceiling: int) -> Array:
	if club_id == "" or group == "":
		return []
	index(season)
	if not _by_group.has(group):
		return []
	var profile := MarketNeeds.profile(club_id)
	var median := int(profile.get("median", 0))
	var severity_value := 0.0
	for want in MarketNeeds.wants(profile):
		if str(want.get("group", "")) == group:
			severity_value = float(want.get("severity", 0.0))
	var low := median - 6
	if severity_value >= 0.5:
		low = median - 1
	var highest := maxi(ceiling, low + 1)
	var seed_value := _seed(season)
	var scored: Array = []
	for index_in_pool in _by_group[group]:
		var entry: Dictionary = _pool[int(index_in_pool)]
		if str(entry["club_id"]) == club_id:
			continue
		var ovr := int(entry["ovr"])
		if ovr < low or ovr > highest:
			continue
		var score := absf(float(ovr) - float(median))
		score += MarketSeed.unit(seed_value, "%s|%s|%s" % [date, club_id, str(entry["id"])], 11)
		scored.append({"id": str(entry["id"]), "score": score})
	scored.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	var cap := maxi(MarketRules.count("ai", "shortlist_cap", 50), 1)
	if scored.size() > cap:
		scored.resize(cap)
	var out: Array = []
	for entry in scored:
		out.append(str(entry["id"]))
	return out


static func _seed(season: LeagueSeason) -> int:
	if season == null or season.save == null:
		return 0
	return absi(int(str(season.save.meta.get("seed", "0"))))
