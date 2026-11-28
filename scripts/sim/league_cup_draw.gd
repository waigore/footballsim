class_name LeagueCupDraw
extends RefCounted


static func settle(season: LeagueSeason, competition_id: String, round_id: String,
		pool: Array) -> Array:
	var rule := LeagueCup.round_rule(competition_id, round_id)
	var ids := _unique(pool)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(season, competition_id, round_id)
	_shuffle(ids, rng)
	var pairs: Array = []
	if bool(rule.get("regional", false)):
		var north: Array = []
		var south: Array = []
		for club_id in ids:
			if LeagueCup.region_of(str(club_id)) == "north":
				north.append(str(club_id))
			else:
				south.append(str(club_id))
		_balance(north, south)
		pairs.append_array(_pair(competition_id, round_id, north))
		pairs.append_array(_pair(competition_id, round_id, south))
	else:
		pairs = _pair(competition_id, round_id, ids)
	return pairs


static func _unique(pool: Array) -> Array:
	var seen := {}
	var out: Array = []
	for club_id in pool:
		var key := str(club_id)
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		out.append(key)
	return out


static func _seed(season: LeagueSeason, competition_id: String, round_id: String) -> int:
	var key := "%s|%s" % [competition_id, round_id]
	var h := 0
	for i in range(key.length()):
		h = int((h * 31 + key.unicode_at(i)) % 2147483647)
	var base := 0
	if season != null:
		base = int(season.rng.seed)
	return base + h


static func _shuffle(ids: Array, rng: RandomNumberGenerator) -> void:
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = swap


static func _balance(north: Array, south: Array) -> void:
	if north.size() % 2 == 0:
		return
	if south.size() <= 1:
		return
	var moved: Variant = south.pop_back()
	north.append(moved)


static func _pair(competition_id: String, round_id: String, ids: Array) -> Array:
	var pairs: Array = []
	var i := 0
	while i + 1 < ids.size():
		var a := str(ids[i])
		var b := str(ids[i + 1])
		var order := LeagueCup.host_order(competition_id, round_id, a, b)
		pairs.append({"home": str(order[0]), "away": str(order[1])})
		i += 2
	return pairs
