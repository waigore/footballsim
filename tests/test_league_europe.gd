extends GdToolsTest


const SEED := 424242


func _season() -> LeagueSeason:
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	return LeagueSeason.create("Europe", "generated", "fixture_days", SEED, ["PL"], false, [], true)


func _settle(season: LeagueSeason, competition_id: String, round_id: String) -> void:
	PLDatabase.execute(
		"UPDATE league_fixture SET status = 'played', home_goals = 2, away_goals = 1 "
		+ "WHERE competition_id = ? AND stage = ?;", [competition_id, round_id])
	if round_id == LeagueUefa.LEAGUE_STAGE:
		season.record.standings.recompute()
	else:
		PLDatabase.execute(
			"UPDATE cup_tie SET home_goals = 2, away_goals = 1, winner_club_id = home_club_id, "
			+ "pens_home = -1, pens_away = -1, extra_time = 0 "
			+ "WHERE competition_id = ? AND round_id = ?;", [competition_id, round_id])
		if LeagueEurope.KO_ROUNDS.has(round_id):
			LeagueUefaKnockout.after_round(season, competition_id, round_id)
	LeagueUefaState.advance(season, competition_id, round_id)


func _run_to(season: LeagueSeason, competition_id: String, last: String) -> void:
	for rid in LeagueUefa.round_ids(competition_id):
		var round_id := str(rid)
		if not LeagueUefa.has_stage(competition_id, round_id):
			continue
		_settle(season, competition_id, round_id)
		if round_id == last:
			return


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
	assert_eq(str(save.current_date()), "2026-07-07", "the shared clock does not open on UEFA Q1")
	assert_eq(LeagueEurope.pending_draws(save).size(), 3, "the first-round draws are not pending")
	LeagueEurope.mark_seen(save, "UCL", "Q1")
	assert_eq(LeagueEurope.pending_draws(save).size(), 2, "a shown draw is still pending")
	assert_eq(str(LeagueEurope.stage_of("UCL")), "Q1", "the UCL stage is not its first round")
	assert_eq(str(LeagueEurope.stage_label("UCL")), "QUALIFYING Q1", "the stage label is not Q1")
	assert_eq(str(LeagueEurope.stage_label("")), "NOT DRAWN", "an empty competition still has a stage")
	assert_eq(str(LeagueEurope.next_night(null)), "", "a missing save still names a UEFA night")
	assert_eq(LeagueEurope.tonight(null), [], "a missing save still lists tonight's ties")
	assert_eq(int(LeagueEurope.alive("")), 0, "an empty competition still has clubs alive")
	var data := LeagueEurope.draw_data(save, "UCL", "Q1")
	assert_true(str(data["title"]).contains("FIRST QUALIFYING ROUND"), "the draw lost its round")
	assert_eq((data["pots"] as Array).size(), 1, "a qualifying draw is not one pool")
	var ties := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'UCL' AND round_id = 'Q1';")
	assert_eq((data["fixtures"] as Array).size(), int(ties["n"]), "the draw lost a tie")
	var first: Dictionary = (data["fixtures"] as Array)[0]
	assert_true(str(first["home_name"]) != "", "a drawn pair has no home name")
	assert_true(str(first["away_name"]) != "", "a drawn pair has no away name")
	assert_true(LeagueEurope.seen(save, "UCL", "Q1"), "a shown round is not marked")
	assert_false(LeagueEurope.seen(save, "UCL", "Q2CH"), "an unseen round reads as shown")
	season.close()


func test_qualifying_drops_and_the_bracket_keep_their_reading() -> void:
	var season := _season()
	_run_to(season, "UCL", "KOPO")
	assert_true(LeagueUefa.has_stage("UCL", "KOPO"), "the UCL knockout play-off never opened")
	assert_true(LeagueEurope.pending_draws(season.save).size() >= 1, "the knockout draw is not pending")
	var drops := 0
	for round in LeagueEuropeTies.qualifying("UCL"):
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
	var rounds: Array = LeagueEuropeTies.bracket("UCL")
	assert_gte(rounds.size(), 1, "the bracket has no round")
	var first: Dictionary = rounds[0]
	assert_eq(str(first["id"]), "KOPO", "the bracket does not start at the play-off")
	assert_eq((first["ties"] as Array).size(), 8, "the knockout play-off is not eight ties")
	for tie in first["ties"]:
		assert_eq((tie["legs"] as Array).size(), 2, "a two-legged tie lost a leg")
		assert_true(str(tie["agg"]) != "", "a tie has no aggregate")
		assert_true(str(tie["fixture"]) != "", "a tie has no fixture to watch")
	assert_gte(int(LeagueEurope.alive("UCL")), 16, "the play-off left too few clubs")
	var knockout := LeagueEurope.stage_of("UCL")
	assert_true(LeagueEurope.KO_ROUNDS.has(knockout), "the bracket left the knockout path")
	assert_eq(str(LeagueEurope.stage_label("UCL")), LeagueEurope.badge(knockout),
		"an open knockout stage has the wrong label")
	season.close()
	season = _season()
	_run_to(season, "UCL", "POLP")
	assert_true(str(LeagueEurope.stage_label("UCL")).begins_with("LEAGUE PHASE"),
		"the league phase label is wrong while it runs")
	assert_gte(int(LeagueEurope.alive("UCL")), 30, "the league phase lost its clubs")
	season.close()


func test_a_watched_tie_aggregates_both_legs() -> void:
	var season := _season()
	var tie := PLDatabase.row(
		"SELECT * FROM cup_tie WHERE competition_id = 'UCL' AND round_id = 'Q1' AND tie_index = 0;")
	assert_false(tie.is_empty(), "the UCL Q1 has no first tie")
	var home := str(tie["home_club_id"])
	var away := str(tie["away_club_id"])
	var leg_one := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE id = 'uefa-UCL-Q1-00-1';")
	var leg_two := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE id = 'uefa-UCL-Q1-00-2';")
	assert_false(leg_one.is_empty(), "the UCL Q1 tie has no first leg")
	assert_false(leg_two.is_empty(), "the UCL Q1 tie has no second leg")
	LeagueUefaState.record_engine(season, leg_one, 2, 1)
	var after_one := PLDatabase.row(
		"SELECT * FROM cup_tie WHERE competition_id = 'UCL' AND round_id = 'Q1' AND tie_index = 0;")
	assert_eq(int(after_one["home_goals"]), 2, "the first leg was not added to the aggregate")
	assert_eq(str(after_one["winner_club_id"]), "", "a half-played tie named a winner")
	LeagueUefaState.record_engine(season, leg_two, 0, 1)
	var after_two := PLDatabase.row(
		"SELECT * FROM cup_tie WHERE competition_id = 'UCL' AND round_id = 'Q1' AND tie_index = 0;")
	assert_eq(int(after_two["home_goals"]), 3, "the second leg was added to the wrong side")
	assert_eq(int(after_two["away_goals"]), 1, "the second leg gave the away side the wrong goals")
	assert_eq(str(after_two["winner_club_id"]), home, "the aggregate did not settle the tie")
	assert_true(str(after_two["winner_club_id"]) != away, "the losing side was called the winner")
	season.close()


func test_the_league_phase_seeds_from_the_frozen_bands() -> void:
	var season := _season()
	_run_to(season, "UCL", "POLP")
	var save: LeagueSave = season.save
	assert_true(LeagueUefa.has_stage("UCL", "LP"), "the league phase never drew")
	var seeded := LeagueUefaBands.pot_bands("UCL")
	assert_gte(seeded.size(), 36, "the seed carries no frozen bands")
	var pots := LeagueEurope.pots(save, "UCL", "LP")
	assert_eq(pots.size(), 4, "the league phase is not four pots")
	var last := 0
	for pot in pots:
		for club in pot:
			var band := LeagueUefaBands.band(seeded, str((club as Dictionary)["id"]))
			assert_gte(band, last, "a pot mixes a better band below a worse one")
			last = band
	season.close()


func test_an_unbanded_club_takes_its_association_median_or_pot_three() -> void:
	var season := _season()
	var save: LeagueSave = season.save
	var seeded := LeagueUefaBands.pot_bands("UCL")
	var peers: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = 'UCL' "
			+ "AND member_kind = 'club';"):
		var other := str(row["member_id"])
		if LeagueUefa.association_of(other) == "ENG" and seeded.has(other) and not peers.has(other):
			peers.append(int(seeded[other]))
	assert_gte(peers.size(), 2, "the seed carries no English banded entrants")
	var club := ""
	var spare := ""
	for row in PLDatabase.rows("SELECT id FROM club WHERE country = 'ENG' ORDER BY id;"):
		if seeded.has(str(row["id"])):
			continue
		if club == "":
			club = str(row["id"])
		else:
			spare = str(row["id"])
			break
	assert_true(club != "" and spare != "", "every English club already carries a band")
	var known := LeagueUefaBands.ensure_bands(save, "UCL", [club])
	peers.sort()
	var expected := int(peers[peers.size() / 2])
	assert_eq(int(known[club]), expected, "an unbanded club took no association median")
	assert_eq(int(LeagueUefaBands.saved_bands(save)[club]), expected, "the inherited band did not stick")
	assert_eq(int(LeagueUefaBands.ensure_bands(save, "", [spare])[spare]), 3,
		"a club with no association peers did not take pot three")
	season.close()


func test_a_complete_bracket_keeps_its_table_and_names_three_winners() -> void:
	var season := _season()
	for cid in LeagueUefa.IDS:
		_run_to(season, str(cid), "F")
	var matches := LeagueUefa.league_matches("UCL")
	var knockout := PLDatabase.row(
		"SELECT home_club_id, away_club_id FROM league_fixture "
		+ "WHERE competition_id = 'UCL' AND stage = 'KOPO' LIMIT 1;")
	assert_false(knockout.is_empty(), "the UCL knockout play-off has no fixture")
	PLDatabase.execute(
		"UPDATE league_fixture SET status = 'played', home_goals = 3, away_goals = 0 WHERE id = ?;",
		[str(PLDatabase.row("SELECT id FROM league_fixture WHERE competition_id = 'UCL' "
			+ "AND stage = 'KOPO' LIMIT 1;")["id"])])
	season.record.standings.recompute()
	for row in PLDatabase.rows(
			"SELECT played FROM league_table WHERE competition_id = 'UCL';"):
		assert_eq(int(row["played"]), matches,
			"a knockout leg was counted in the UCL league table")
	var honours: Array = LeagueEurope.honours(season.save)
	assert_eq(honours.size(), 3, "the podium does not name three continental winners")
	for row in honours:
		assert_true(str(row["winner_name"]) != "", "a continental winner has no name")
		assert_true(str(row["runner_up_name"]) != "", "a continental runner-up has no name")
		assert_true(LeagueEurope.score_line(row).contains("–"), "a final has no score line")
		assert_true(str(LeagueEurope.stage_of(str(row["id"]))) == "F",
			"a completed competition is not at its final")
		assert_eq(int(LeagueEurope.alive(str(row["id"]))), 2, "a final does not list two clubs")
		assert_eq(str(LeagueEurope.stage_label(str(row["id"]))), "FINAL · COMPLETE",
			"a finished final has the wrong stage label")
	assert_eq(str(LeagueEurope.next_night(season.save, "UCL")), "",
		"a finished UCL still has a night ahead")
	assert_eq(str(LeagueEurope.stage_label("UCL")), "FINAL · COMPLETE",
		"UCL did not read as a finished final")
	season.close()
