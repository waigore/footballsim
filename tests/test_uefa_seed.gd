extends GdToolsTest


const UEFA := ["UCL", "UEL", "UECL"]


func _count(sql: String, bindings: Array = []) -> int:
	var row := PLDatabase.row(sql, bindings)
	return int(row.get("n", 0))


func test_the_seed_ships_the_three_continental_competitions() -> void:
	var comps := PLRepository.shared().continentals()
	assert_eq(comps.size(), 3, "the seed should ship UCL, UEL and UECL")
	var ids: Array = []
	for row in comps:
		ids.append(str(row["id"]))
	for cid in UEFA:
		assert_true(ids.has(cid), "the seed has no %s" % cid)
		assert_eq(PLRepository.shared().competition_kind(cid), "continental",
			"%s is not continental" % cid)
	assert_eq(PLRepository.shared().leagues().size(), 10, "a continental leaked into the leagues")
	assert_eq(PLRepository.shared().cups().size(), 9, "a continental leaked into the cups")


func test_every_entrant_resolves_to_a_playable_club() -> void:
	for cid in UEFA:
		var members := PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club';", [cid])
		assert_gte(members.size(), 40, "%s has no entrants" % cid)
		for row in members:
			var club := PLRepository.shared().club(str(row["member_id"]))
			assert_false(club.is_empty(), "%s names an unknown club %s" % [cid, row["member_id"]])
			var starters := _count(
				"SELECT COUNT(*) AS n FROM player WHERE club_id = ? AND squad = 'starter';",
				[str(row["member_id"])])
			assert_eq(starters, 11, "%s: %s cannot field eleven" % [cid, row["member_id"]])


func test_the_access_list_counts_match_the_regulations() -> void:
	var expected := {
		"UCL": {"Q1": 28, "Q2CH": 10, "Q2LP": 4, "Q3LP": 6, "POCH": 4, "LP": 29},
		"UEL": {"Q1": 12, "Q2": 12, "Q3MP": 3, "PO": 5, "LP": 13},
		"UECL": {"Q1": 52, "Q2MP": 54, "POMP": 5},
	}
	for cid in expected:
		var seen := {}
		for row in PLDatabase.rows(
				"SELECT role, COUNT(*) AS n FROM competition_member WHERE competition_id = ? "
				+ "GROUP BY role;", [cid]):
			seen[str(row["role"])] = int(row["n"])
		for role in expected[cid]:
			assert_eq(int(seen.get(role, 0)), int(expected[cid][role]),
				"%s %s entry list drifted" % [cid, role])


func test_the_shipped_associations_enter_real_clubs() -> void:
	var real := _count(
		"SELECT COUNT(*) AS n FROM competition_member m JOIN club c ON c.id = m.member_id "
		+ "WHERE m.competition_id IN ('UCL','UEL','UECL') AND c.stub = 0;")
	assert_eq(real, 31, "the four shipped associations should enter 31 real clubs")
	var stubs := _count(
		"SELECT COUNT(*) AS n FROM competition_member m JOIN club c ON c.id = m.member_id "
		+ "WHERE m.competition_id IN ('UCL','UEL','UECL') AND c.stub = 1;")
	assert_eq(stubs, 206, "every other association should enter one stub per place")


func test_a_stub_carries_its_own_association() -> void:
	var row := PLDatabase.row("SELECT id, country FROM club WHERE name = 'Paris Saint-Germain';")
	assert_false(row.is_empty(), "the seed has no Paris Saint-Germain stub")
	assert_true(str(row["id"]).begins_with("FRA-"), "a French stub is not a FRA id")
	assert_eq(str(row["country"]), "FRA", "a French stub does not carry FRA")
	var eng := PLDatabase.row(
		"SELECT c.id FROM competition_member m JOIN club c ON c.id = m.member_id "
		+ "WHERE m.competition_id = 'UCL' AND c.name = 'Arsenal';")
	assert_eq(str(eng.get("id", "")), "ENG-ARS1", "Arsenal should be the seeded PL club")


func test_the_league_phase_shape_is_frozen() -> void:
	for cid in UEFA:
		var row := PLDatabase.row("SELECT rules FROM competition WHERE id = ?;", [cid])
		var rules: Variant = JSON.parse_string(str(row.get("rules", "{}")))
		assert_true(rules is Dictionary, "%s rules are not JSON" % cid)
		var phase: Dictionary = (rules as Dictionary).get("league_phase", {})
		assert_eq(int(phase.get("clubs", 0)), 36, "%s league phase is not 36 clubs" % cid)
		var matches := 6 if cid == "UECL" else 8
		assert_eq(int(phase.get("matches", 0)), matches, "%s match count drifted" % cid)
		var rounds: Array = (rules as Dictionary).get("rounds", [])
		assert_gte(rounds.size(), 10, "%s has no stage list" % cid)
