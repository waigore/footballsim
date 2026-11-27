extends GdToolsTest


const CLUBS := 20

func test_every_club_has_a_full_squad() -> void:
	for competition_id in ["PL", "LL"]:
		var ids: Array = TeamData.team_ids(competition_id)
		assert_eq(ids.size(), CLUBS, "%s does not hold twenty clubs" % competition_id)
		var names := {}
		for id in ids:
			var team: Dictionary = TeamData.get_team(id)
			assert_false(team.is_empty(), "%s resolves to no squad" % id)
			assert_false(str(team["name"]) == "", "%s has no club name" % id)
			assert_false(str(team["short"]) == "", "%s has no short name" % id)
			assert_false(str(team["manager"]) == "", "%s has no manager" % id)
			assert_eq(str(team["competition_id"]), competition_id,
				"%s is filed under the wrong competition" % id)
			names[str(team["name"])] = true
			assert_eq((team["starters"] as Array).size(), 11, "%s does not field eleven starters" % id)
			assert_gte((team["bench"] as Array).size(), 7, "%s bench is too short to make five changes" % id)
			assert_true(TeamData.FORMATIONS.has(str(team["formation"])), "%s lines up in an unknown formation" % id)
		assert_eq(names.size(), CLUBS, "%s has two clubs sharing a name" % competition_id)

func test_starters_cover_every_role_in_their_formation() -> void:
	for id in TeamData.team_ids():
		var team: Dictionary = TeamData.get_team(id)
		var played := {}
		for pd in team["starters"]:
			var role := str(pd["role"])
			assert_false(played.has(role), "%s starts two %s" % [id, role])
			played[role] = true
			var slot: Vector2 = TeamData.formation_slot(team, role)
			assert_between(slot.x, 0.0, 1.0, "%s %s slot x is off the pitch" % [id, role])
			assert_between(slot.y, 0.0, 1.0, "%s %s slot y is off the pitch" % [id, role])
		assert_eq(played.size(), 11, "%s does not field eleven distinct roles" % id)
		assert_true(played.has("GK"), "%s starts without a keeper" % id)

func test_formation_slots_are_inside_the_pitch_for_every_shape() -> void:
	for formation in TeamData.FORMATIONS.keys():
		var slots: Dictionary = TeamData.slots(formation)
		assert_eq(slots.size(), 11, "%s does not place eleven players" % formation)
		for role in slots.keys():
			var slot: Vector2 = slots[role]
			assert_between(slot.x, 0.0, 1.0, "%s %s slot x is off the pitch" % [formation, role])
			assert_between(slot.y, 0.0, 1.0, "%s %s slot y is off the pitch" % [formation, role])

func test_unknown_formation_falls_back_to_the_default_shape() -> void:
	var fallback: Dictionary = TeamData.slots("9-9-9")
	assert_eq(fallback.size(), 11, "an unknown formation does not fall back to a legal shape")
	assert_eq(fallback, TeamData.FORMATIONS["4-2-3-1"], "the fallback is not the default shape")

func test_bench_roles_fall_back_to_a_sensible_line() -> void:


	var cb: Vector2 = TeamData.formation_slot_for("4-2-3-1", "CB")
	var cdm: Vector2 = TeamData.formation_slot_for("4-2-3-1", "CDM")
	var cm: Vector2 = TeamData.formation_slot_for("4-2-3-1", "CM")
	var st: Vector2 = TeamData.formation_slot_for("4-2-3-1", "ST")
	var gk: Vector2 = TeamData.formation_slot_for("4-2-3-1", "GK")
	assert_lt(cb.x, cdm.x, "the centre-back fallback stands ahead of the holding mid")
	assert_lt(cdm.x, cm.x, "the holding mid fallback stands ahead of the centre-mid")
	assert_lt(cm.x, st.x, "the centre-mid fallback stands ahead of the striker")
	assert_lt(gk.x, cb.x, "the keeper fallback does not stand deepest")
	for role in ["CB", "CDM", "CM", "LM", "RM", "LW", "RW", "CAM", "ST", "GK"]:
		var slot: Vector2 = TeamData.formation_slot_for("4-2-3-1", role)
		assert_between(slot.x, 0.0, 1.0, "%s fallback x is off the pitch" % role)
		assert_between(slot.y, 0.0, 1.0, "%s fallback y is off the pitch" % role)
	var unknown: Vector2 = TeamData.formation_slot_for("4-2-3-1", "SWEEPER")
	assert_between(unknown.x, 0.0, 1.0, "an unknown role has no fallback slot")
	assert_between(unknown.y, 0.0, 1.0, "an unknown role has no fallback slot")

func test_named_slot_wins_over_the_fallback() -> void:
	var slot: Vector2 = TeamData.formation_slot_for("4-2-3-1", "ST")
	assert_eq(slot, (TeamData.FORMATIONS["4-2-3-1"] as Dictionary)["ST"],
		"a formation's own slot was ignored in favour of the fallback")

func test_other_club_is_the_fixture_opponent() -> void:
	assert_eq(TeamData.other("MUN"), "MCI", "Manchester United's opponent is not City")
	assert_eq(TeamData.other("MCI"), "MUN", "Manchester City's opponent is not United")
	assert_true(TeamData.team_ids().has(TeamData.other("MUN")), "the opponent is not in the league")

func test_incomplete_profile_is_rejected() -> void:
	assert_false(ManagerData.has_full_profile({}), "an empty profile reads as complete")
	var partial: Dictionary = ManagerData.DEFAULT.duplicate(true)
	partial.erase("patience")
	assert_false(ManagerData.has_full_profile(partial), "a profile missing a lever reads as complete")
	assert_true(ManagerData.has_full_profile(ManagerData.profile("MUN")),
		"a real club profile does not read as complete")

func test_trait_line_reads_off_the_profile() -> void:
	for id in TeamData.team_ids():
		var line: String = ManagerData.trait_line(id)
		assert_false(line == "", "%s has no trait line for the overlay" % id)
		assert_eq(line, str(ManagerData.profile(id)["trait"]), "%s trait line drifted from its profile" % id)
