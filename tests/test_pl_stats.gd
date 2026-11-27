extends GdToolsTest


var CACHE_DIR := TestScratch.dir("cache_test_stats")

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	PLSimStats.clear()

func after_all() -> void:
	PLSimStats.clear()
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_rating_uses_the_player_card_weights() -> void:
	var plain := PLSimStats.rating({})
	assert_almost_eq(plain, 6.0, 0.001, "an empty match line should rate six")
	var scorer := PLSimStats.rating({"goals": 1, "assists": 1})
	assert_almost_eq(scorer, 7.9, 0.001, "goals and assists no longer carry their weight")
	assert_lte(PLSimStats.rating({"fouls": 40}), 6.0, "fouls should cost rating")

func test_a_finished_match_updates_players_and_clubs() -> void:
	PLSimStats.clear()
	var ok := PLSimStats.record(_summary(["MUN-b-fernandes", "MUN-b-mbeumo"], [2, 1]))
	assert_true(ok, "the match was not recorded")
	var fernandes := PLRepository.shared().sim_player("MUN-b-fernandes")
	assert_eq(int(fernandes["apps"]), 1, "the appearance did not land")
	assert_eq(int(fernandes["goals"]), 2, "the goals did not land")
	assert_eq(int(fernandes["passes_ok"]), 18, "the passing line did not land")
	var home := PLRepository.shared().sim_club("MUN")
	assert_eq(int(home["played"]), 1, "the club record did not land")
	assert_eq(int(home["won"]), 1, "a 2-1 win was not a win")
	assert_eq(int(home["points"]), 3, "a win is worth three points")
	assert_eq(int(home["gf"]), 2, "goals for did not land")
	var away := PLRepository.shared().sim_club("MCI")
	assert_eq(int(away["lost"]), 1, "the away side did not take the loss")
	assert_eq(int(away["points"]), 0, "the away side took a point it did not earn")

func test_a_second_match_accumulates() -> void:
	PLSimStats.clear()
	PLSimStats.record(_summary(["MUN-b-fernandes"], [1, 0]))
	PLSimStats.record(_summary(["MUN-b-fernandes"], [1, 3]))
	var p := PLRepository.shared().sim_player("MUN-b-fernandes")
	assert_eq(int(p["apps"]), 2, "appearances do not accumulate")
	assert_eq(int(p["goals"]), 2, "goals do not accumulate")
	var club := PLRepository.shared().sim_club("MUN")
	assert_eq(int(club["played"]), 2, "the club record does not accumulate")
	assert_eq(int(club["won"]), 1, "a win was lost in accumulation")
	assert_eq(int(club["lost"]), 1, "a loss was lost in accumulation")
	assert_eq(int(club["points"]), 3, "points do not accumulate")

func test_the_dashboards_see_the_ledger() -> void:
	PLSimStats.clear()
	PLSimStats.record(_summary(["MUN-b-fernandes"], [2, 0]))
	var page := WikiModel.page(WikiModel.TEAM, "MUN")
	var text := _flatten(page)
	assert_true(text.contains("IN FOOTBALLSIM"), "the club page does not show the sim ledger")
	assert_true(text.contains("MUN-b-fernandes") or text.contains("B. Fernandes"), "the scorer chart is empty")
	var league := _flatten(WikiModel.page(WikiModel.LEAGUE, ""))
	assert_true(league.contains("IN-SIM"), "the league page does not show in-sim scorers")
	var player := _flatten(WikiModel.page(WikiModel.PLAYER, "MUN-b-fernandes"))
	assert_true(player.contains("IN FOOTBALLSIM"), "the player page does not show its sim line")

func test_a_seed_version_bump_drops_the_ledger() -> void:
	PLSimStats.clear()
	PLSimStats.record(_summary(["MUN-b-fernandes"], [1, 0]))
	assert_eq(int(PLRepository.shared().sim_club("MUN")["played"]), 1, "no ledger to flush")

	var stale := CACHE_DIR.path_join("pl_seed_v%d.sqlite" % PLDatabase.seed_version())
	assert_true(FileAccess.file_exists(stale), "the current cache copy is missing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stale))
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	assert_true(PLRepository.shared().sim_club("MUN").is_empty(), "an old ledger survived a cache flush")

func _summary(player_ids: Array, score: Array) -> Dictionary:
	var lines: Array = []
	for id in player_ids:
		lines.append({
			"player_id": str(id), "minutes": 90, "goals": int(score[0]),
			"assists": 1, "shots": 4, "passes": 24, "passes_ok": 18,
			"tackles": 2, "saves": 0, "yellow": 0, "red": 0, "rating": 8.2,
		})
	return {"home": "MUN", "away": "MCI", "score": score, "players": lines}

func _flatten(page: Dictionary) -> String:
	var text := "%s %s" % [page.get("title", ""), page.get("subtitle", "")]
	for block in page.get("blocks", []):
		text += " " + str(block.get("text", ""))
		for row in block.get("rows", []):
			text += " " + " ".join(PackedStringArray(row.get("cells", [])))
		for item in block.get("items", []):
			text += " " + str(item)
	return text
