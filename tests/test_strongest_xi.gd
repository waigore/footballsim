extends GdToolsTest

## The save's chosen eleven: best player per formation slot, a keeper in goal,
## no duplicates, and the choice written back so both outcome paths field it.

const SAVE_DIR := "user://saves_test_xi_issue58"
const CACHE_DIR := "user://cache_test_xi_issue58"

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	LeagueSave.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_xi_is_eleven_distinct_players() -> void:
	var xi := StrongestXI.pick(TeamData.get_team("MCI"))
	assert_eq(xi.size(), 11, "the strongest XI is not eleven players")
	var seen := {}
	for p in xi:
		var id := str(p["id"])
		assert_false(seen.has(id), "%s was picked twice" % id)
		seen[id] = true

func test_every_slot_is_filled_by_its_own_line() -> void:
	var team := TeamData.get_team("MUN")
	var xi := StrongestXI.pick(team)
	var slots: Array = TeamData.slots(str(team["formation"])).keys()
	assert_eq(xi.size(), slots.size(), "the XI does not cover the formation")
	for i in range(slots.size()):
		var slot := str(slots[i])
		var role := str(xi[i]["role"])
		if slot == "GK":
			assert_eq(role, "GK", "an outfielder is in goal")
		else:
			assert_true(str(StrongestXI.FAMILY.get(role, role)) == str(StrongestXI.FAMILY.get(slot, slot)),
				"%s is not covered by a %s player" % [slot, role])

func test_the_best_player_in_a_role_starts() -> void:
	var team := TeamData.get_team("LIV")
	var xi := StrongestXI.pick(team)
	var picked := {}
	for p in xi:
		picked[str(p["id"])] = true
	var best_striker := {}
	for p in team["starters"] + team["bench"]:
		if str(p["role"]) == "ST" and (best_striker.is_empty() or int(p["ovr"]) > int(best_striker["ovr"])):
			best_striker = p
	assert_false(best_striker.is_empty(), "the squad has no striker")
	assert_true(picked.has(str(best_striker["id"])), "the best striker did not start")

func test_the_choice_is_written_into_the_save() -> void:
	var season := LeagueSeason.create("XI Season", "generated", "fixture_days", 5)
	assert_not_null(season, "the season was not created")
	var applied := StrongestXI.apply_all()
	assert_eq(applied, 20, "not every club got its XI")
	for club_id in ["MUN", "MCI", "ARS"]:
		var team := TeamData.get_team(club_id)
		assert_eq(team["starters"].size(), 11, "%s does not field eleven" % club_id)
		var xi := StrongestXI.pick(team)
		assert_eq(str(xi[0]["id"]), str(team["starters"][0]["id"]), "%s did not keep its chosen XI" % club_id)
		var rows: Array = PLRepository.shared().squad(club_id)
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var expected := "starters" if i < 11 else "bench"
			assert_eq(str(row["squad"]), expected, "%s does not carry its XI order" % club_id)
	season.close()

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		DirAccess.make_dir_recursive_absolute(folder)
		for name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
