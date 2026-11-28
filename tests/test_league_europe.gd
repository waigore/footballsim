extends GdToolsTest


const SEED := 424242


func _season() -> LeagueSeason:
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	return LeagueSeason.create("Europe", "generated", "fixture_days", SEED, ["PL"], false, true)


func _advance_until(season: LeagueSeason, done: Callable, cap: int = 120) -> bool:
	var guard := 0
	while guard < cap:
		if bool(done.call()):
			return true
		var result := season.advance()
		if bool(result.get("complete", false)):
			return bool(done.call())
		guard += 1
	return bool(done.call())


func test_the_hub_reads_three_competitions_and_their_pending_draws() -> void:
	var season := _season()
	var save: LeagueSave = season.save
	var cards: Array = []
	for cid in LeagueEurope.active_ids(save):
		cards.append(LeagueEurope.card(save, str(cid)))
	assert_eq(cards.size(), 3, "Europe did not read three competitions")
	for card in cards:
		assert_true(str(card["stage"]).begins_with("QUALIFYING"), "a card has no qualifying stage")
		assert_gte(int(card["alive"]), 2, "a competition has no clubs alive")
		assert_true(str(card["next"]) != "", "a competition has no next UEFA night")
	assert_eq(LeagueEurope.pending_draws(save).size(), 3, "the first-round draws are not pending")
	LeagueEurope.mark_seen(save, "UCL", "Q1")
	assert_eq(LeagueEurope.pending_draws(save).size(), 2, "a shown draw is still pending")
	assert_eq(str(LeagueEurope.stage_of("UCL")), "Q1", "the UCL stage is not its first round")
	assert_eq(str(LeagueEurope.stage_label("UCL")), "QUALIFYING Q1", "the stage label is not Q1")
	season.close()


func test_the_draw_reads_the_settled_pairs_before_it_is_shown() -> void:
	var season := _season()
	var save: LeagueSave = season.save
	var data := LeagueEurope.draw_data(save, "UCL", "Q1")
	assert_true(str(data["title"]).contains("FIRST QUALIFYING ROUND"), "the draw title lost its round")
	assert_eq((data["pots"] as Array).size(), 1, "a qualifying draw is not one pool")
	var ties := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'UCL' AND round_id = 'Q1';")
	assert_eq((data["fixtures"] as Array).size(), int(ties["n"]), "the draw lost a tie")
	var first: Dictionary = (data["fixtures"] as Array)[0]
	assert_true(str(first["home_name"]) != "", "a drawn pair has no home name")
	assert_true(str(first["away_name"]) != "", "a drawn pair has no away name")
	LeagueEurope.mark_seen(save, "UCL", "Q1")
	assert_false(LeagueEurope.seen(save, "UCL", "Q2CH"), "an unseen round reads as shown")
	assert_true(LeagueEurope.seen(save, "UCL", "Q1"), "a shown round is not marked")
	season.close()


func test_qualifying_shows_the_drop_and_the_arrival() -> void:
	var season := _season()
	var drawn := _advance_until(season, func() -> bool:
		return LeagueUefa.has_stage("UEL", "Q3CH")
	)
	assert_true(drawn, "the UEL Q3 champions path never opened")
	var rounds: Array = LeagueEuropeTies.qualifying("UCL")
	var drops := 0
	for round in rounds:
		for tie in round["ties"]:
			if not (tie["drop"] as Dictionary).is_empty():
				drops += 1
				assert_true(LeagueEuropeTies.drop_label(tie["drop"]).begins_with("↓"),
					"a drop badge has no arrow")
	assert_gte(drops, 1, "no UCL tie carries a drop badge")
	var arrivals := LeagueEuropeTies.arrivals("UEL", "Q3CH")
	assert_false(arrivals.is_empty(), "nothing arrived in the UEL Q3 champions path")
	for club_id in arrivals:
		var label := LeagueEuropeTies.arrival_label(arrivals[club_id])
		assert_true(label.begins_with("←"), "an arrival badge has no arrow")
		assert_true(label.contains("UCL"), "an arrival does not name its source")
	season.close()


func test_the_bracket_keeps_both_legs_and_the_aggregate() -> void:
	var season := _season()
	var drawn := _advance_until(season, func() -> bool:
		return LeagueUefa.has_stage("UCL", "KOPO")
	)
	assert_true(drawn, "the UCL knockout play-off never opened")
	var rounds: Array = LeagueEuropeTies.bracket("UCL")
	assert_gte(rounds.size(), 1, "the bracket has no round")
	var first: Dictionary = rounds[0]
	assert_eq(str(first["id"]), "KOPO", "the bracket does not start at the play-off")
	var ties: Array = first["ties"]
	assert_eq(ties.size(), 8, "the knockout play-off is not eight ties")
	for tie in ties:
		assert_eq((tie["legs"] as Array).size(), 2, "a two-legged tie lost a leg")
		assert_true(str(tie["agg"]) != "", "a tie has no aggregate")
	assert_gte(int(LeagueEurope.alive("UCL")), 16, "the play-off left too few clubs")
	season.close()


func test_the_league_table_counts_only_league_phase_matches() -> void:
	var season := _season()
	var played_knockout := _advance_until(season, func() -> bool:
		var row := PLDatabase.row(
			"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'UCL' AND round_id = 'KOPO' "
			+ "AND winner_club_id <> '';")
		return int(row["n"]) > 0
	)
	assert_true(played_knockout, "no knockout tie was played")
	var matches := LeagueUefa.league_matches("UCL")
	var rows: Array = PLDatabase.rows(
		"SELECT club_id, played FROM league_table WHERE competition_id = 'UCL';")
	assert_eq(rows.size(), 36, "the league phase lost a club")
	for row in rows:
		assert_lte(int(row["played"]), matches,
			"a knockout leg was counted in the UCL league table")
	assert_eq(int(LeagueEurope.league_matchday("UCL")), matches,
		"the league phase is not complete at the knockouts")
	season.close()


func test_a_complete_season_names_three_continental_honours() -> void:
	var season := _season()
	var done := _advance_until(season, func() -> bool:
		return season.save.status() == "complete"
	, 400)
	assert_true(done, "the season never completed")
	var honours: Array = LeagueEurope.honours(season.save)
	assert_eq(honours.size(), 3, "the podium does not name three continental winners")
	for row in honours:
		assert_true(str(row["winner_name"]) != "", "a continental winner has no name")
		assert_true(str(row["runner_up_name"]) != "", "a continental runner-up has no name")
		assert_true(LeagueEurope.score_line(row).contains("–"), "a final has no score line")
		assert_true(str(LeagueEurope.stage_of(str(row["id"]))) == "F",
			"a completed competition is not at its final")
		assert_eq(int(LeagueEurope.alive(str(row["id"]))), 2, "a final does not list two clubs")
	season.close()
