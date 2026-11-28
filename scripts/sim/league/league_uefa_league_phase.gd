class_name LeagueUefaLeaguePhase
extends RefCounted


static func field(competition_id: String) -> Array:
	var out: Array = []
	for club_id in LeagueUefa.entrants(competition_id, LeagueUefa.LEAGUE_STAGE):
		out.append(str(club_id))
	for row in PLDatabase.rows(
			"SELECT winner_club_id FROM cup_tie WHERE competition_id = ? "
			+ "ORDER BY winner_club_id;", [competition_id]):
		out.append(str(row["winner_club_id"]))
	return out


static func draw(season: LeagueSeason, competition_id: String) -> bool:
	if season == null or season.save == null:
		return false
	var clubs := LeagueCupDraw.unique(field(competition_id))
	var need := LeagueUefa.league_clubs(competition_id)
	if clubs.size() < need:
		return false
	clubs = clubs.slice(0, need)
	var ranked := _by_rank(season, competition_id, clubs)
	var pots := _pots(ranked, LeagueUefa.pots(competition_id))
	var matches := LeagueUefa.league_matches(competition_id)
	var pairs := _schedule(season, competition_id, pots, matches)
	if pairs.is_empty():
		return false
	_install_table(competition_id, clubs, season.save.season_index())
	_install_fixtures(competition_id, ranked, pairs, matches, season.save.season_index())
	season.save.set_status("in_progress")
	return true


static func _by_rank(season: LeagueSeason, competition_id: String, clubs: Array) -> Array:
	return LeagueUefaBands.ranked(LeagueUefaBands.ensure_bands(season.save, competition_id, clubs), clubs)


static func _pots(ranked: Array, count: int) -> Array:
	var pots: Array = []
	var size := int(ceil(float(ranked.size()) / float(maxi(count, 1))))
	for p in range(count):
		var start := p * size
		if start >= ranked.size():
			break
		pots.append(ranked.slice(start, mini(start + size, ranked.size())))
	return pots


static func _schedule(season: LeagueSeason, competition_id: String, pots: Array,
		matches: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(season, competition_id)
	var sized: Array = []
	for pot in pots:
		var pool: Array = (pot as Array).duplicate()
		_shuffle(pool, rng)
		sized.append(pool)
	var pairs: Array = []
	var count := 2
	for p in range(sized.size()):
		pairs.append_array(_cycle_pairs(sized[p], count))
		for q in range(p + 1, sized.size()):
			if not _faces(matches, p, q, sized.size()):
				continue
			pairs.append_array(_bipartite_pairs(sized[p], sized[q], count))
	_repair_associations(pairs)
	return pairs


static func _faces(matches: int, p: int, q: int, pots: int) -> bool:
	if matches >= pots * 2:
		return true
	return q == p + 1 or (p == 0 and q == pots - 1)


static func _cycle_pairs(pool: Array, count: int) -> Array:
	var out: Array = []
	var n := pool.size()
	if n < 3 or count < 2:
		return out
	for i in range(n):
		var j := (i + 1) % n
		var home_first := i % 2 == 0
		out.append({
			"home": str(pool[i]) if home_first else str(pool[j]),
			"away": str(pool[j]) if home_first else str(pool[i]),
		})
	return out


static func _bipartite_pairs(left: Array, right: Array, count: int) -> Array:
	var out: Array = []
	var n := mini(left.size(), right.size())
	for offset in range(1, count + 1):
		for i in range(n):
			var a := str(left[i])
			var b := str(right[(i + offset) % n])
			var home_first := (i + offset) % 2 == 0
			out.append({"home": a if home_first else b, "away": b if home_first else a})
	return out


static func _repair_associations(pairs: Array) -> void:
	for i in range(pairs.size()):
		var pair: Dictionary = pairs[i]
		var home := str(pair["home"])
		var away := str(pair["away"])
		if LeagueUefa.association_of(home) != LeagueUefa.association_of(away):
			continue
		for j in range(pairs.size()):
			if j == i:
				continue
			var other: Dictionary = pairs[j]
			var a := str(other["home"])
			var b := str(other["away"])
			if LeagueUefa.association_of(home) == LeagueUefa.association_of(a) \
					or LeagueUefa.association_of(away) == LeagueUefa.association_of(b):
				continue
			if _clashes(pairs, i, j, home, b) or _clashes(pairs, i, j, a, away):
				continue
			pairs[i] = {"home": home, "away": b}
			pairs[j] = {"home": a, "away": away}
			break


static func _clashes(pairs: Array, i: int, j: int, a: String, b: String) -> bool:
	for k in range(pairs.size()):
		if k == i or k == j:
			continue
		var row: Dictionary = pairs[k]
		if (str(row["home"]) == a and str(row["away"]) == b) \
				or (str(row["home"]) == b and str(row["away"]) == a):
			return true
	return false


static func _shuffle(ids: Array, rng: RandomNumberGenerator) -> void:
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = swap


static func _seed(season: LeagueSeason, competition_id: String) -> int:
	var key := "lp|" + competition_id
	var h := 0
	for i in range(key.length()):
		h = int((h * 31 + key.unicode_at(i)) % 2147483647)
	var base := int(season.rng.seed) if season != null else 0
	return base + h


static func _install_table(competition_id: String, clubs: Array, season_index: int) -> void:
	PLDatabase.execute(
		"DELETE FROM league_table WHERE competition_id = ?;", [competition_id])
	for club_id in clubs:
		PLDatabase.execute(
			"INSERT OR IGNORE INTO league_table (club_id, competition_id, season_index) "
			+ "VALUES (?, ?, ?);",
			[str(club_id), competition_id, season_index])


static func _install_fixtures(competition_id: String, ranked: Array, pairs: Array,
		matches: int, season_index: int) -> void:
	PLDatabase.execute(
		"DELETE FROM league_fixture WHERE competition_id = ? AND stage = ?;",
		[competition_id, LeagueUefa.LEAGUE_STAGE])
	var anchor := str(LeagueUefa.round_rule(competition_id, LeagueUefa.LEAGUE_STAGE).get("date", ""))
	var dates := _matchdays(matches, anchor)
	var per := maxi(int(ceil(float(pairs.size()) / float(maxi(matches, 1)))), 1)
	for i in range(pairs.size()):
		var pair: Dictionary = pairs[i]
		var matchday := mini(i / per + 1, matches)
		var date: String = dates[mini(matchday - 1, dates.size() - 1)]
		PLDatabase.execute(
			"INSERT OR REPLACE INTO league_fixture (id, competition_id, matchday, kickoff, "
			+ "kickoff_time, home_club_id, away_club_id, status, watched, suggested, stage, "
			+ "leg, season_index) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, 0, ?, 0, ?);",
			["uefa-%s-lp-%03d" % [competition_id, i], competition_id, matchday, date,
			 FixtureCalendar.KICKOFF_TIMES[i % FixtureCalendar.KICKOFF_TIMES.size()],
			 str(pair["home"]), str(pair["away"]), LeagueUefa.LEAGUE_STAGE, season_index])


static func _matchdays(matches: int, anchor: String) -> Array:
	var out: Array = []
	var day := FixtureCalendar.days_from(anchor if anchor != "" else "2026-09-15")
	for i in range(matches):
		out.append(FixtureCalendar.date_from(day + i * 28))
	return out


static func table(competition_id: String) -> Array:
	return PLRepository.shared().table(competition_id)


static func zone(position: int) -> String:
	if position <= 8:
		return "r16"
	if position <= 24:
		return "kopo"
	return "out"
