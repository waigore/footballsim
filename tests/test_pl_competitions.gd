extends GdToolsTest

## Competitions in one database: the shipped seed carries one, and a file that
## carries two must give each its own hub, table, club index and fixtures — with
## no page hard-coded to "the" league (#190, parent #185).
##
## The second competition is built here on purpose: the shipped seed is
## Premier-League-only until the La Liga snapshot lands (#186), and the code has
## to be proved against the shape it is being written for, not just the shape it
## happens to ship with.

var CACHE_DIR := TestScratch.dir("cache_test_competitions")

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	_drop_second_competition()
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_seed_carries_one_competition() -> void:
	var all := PLCompetitions.all()
	assert_eq(all.size(), 1, "the shipped seed should carry one competition")
	var pl: Dictionary = all[0]
	assert_eq(str(pl["id"]), "PL", "the seed's competition is not the Premier League")
	assert_eq(str(pl["name"]), "Premier League", "the competition name drifted")
	assert_eq(int(pl["clubs"]), 20, "the Premier League club count is wrong")
	assert_eq(PLCompetitions.default_id(), "PL", "the default competition is not the seed's")
	assert_eq(str(PLCompetitions.one("PL").get("season_label", "")), "2026-27", "season label drifted")
	assert_true(PLCompetitions.one("LL").is_empty(), "an unknown competition resolved")

func test_the_shipped_hub_names_its_competition() -> void:
	var page := WikiModel.league_page()
	assert_eq(str(page["id"]), "PL", "the hub lost its competition id")
	assert_eq(str(page["title"]), "PREMIER LEAGUE", "the hub title is not the competition's")
	assert_true(str(page["subtitle"]).contains("20 CLUBS"), "the hub's club count is hard-coded")
	var index := _chips(page)
	assert_eq(index.size(), 1, "the competition index should hold the one league")
	assert_eq(str(index[0]["text"]), "PREMIER LEAGUE", "the index names the wrong league")
	assert_true((index[0] as Dictionary).get("target", {}).is_empty(),
		"the league you are reading should be a badge, not a door to itself")

func test_a_club_and_its_players_point_at_their_competition() -> void:
	var club := WikiModel.page(WikiModel.TEAM, "MUN")
	var targets := _targets(club)
	assert_true(_has_target(targets, WikiModel.LEAGUE, "PL"), "a club page does not link its league")
	var player := WikiModel.page(WikiModel.PLAYER, "MUN-b-fernandes")
	var player_targets := _targets(player)
	assert_true(_has_target(player_targets, WikiModel.LEAGUE, "PL"),
		"a player page does not link its league")

func test_two_competitions_get_two_hubs() -> void:
	_add_second_competition()
	var all := PLCompetitions.all()
	assert_eq(all.size(), 2, "the second competition was not read")
	assert_eq(PLCompetitions.default_id(), "PL", "the default competition moved")
	assert_eq(PLCompetitions.clubs("LL"), 2, "the second competition's club count is wrong")

	var theirs := WikiModel.page(WikiModel.LEAGUE, "LL")
	assert_eq(str(theirs["title"]), "LA LIGA", "the second hub is not its own competition")
	assert_true(str(theirs["subtitle"]).contains("2 CLUBS"),
		"the second hub kept the first's club count")
	assert_eq(_rows_in(theirs, "LEAGUE TABLE"), 2, "the second hub shows the wrong table")
	var index := _chips(theirs)
	assert_eq(index.size(), 2, "the index does not list both competitions")
	assert_true(_chip_target(index, "PREMIER LEAGUE", "PL"),
		"the second hub does not offer the Premier League")

	var ours := WikiModel.page(WikiModel.LEAGUE, "PL")
	assert_eq(_rows_in(ours, "LEAGUE TABLE"), 20, "the Premier League hub picked up the second league")
	assert_true(_chip_target(_chips(ours), "LA LIGA", "LL"),
		"the Premier League hub does not offer the second league")

	var club := WikiModel.page(WikiModel.TEAM, "RMA")
	assert_eq(str(club["title"]), "REAL MADRID", "the second league's club page is missing")
	var club_targets := _targets(club)
	assert_true(_has_target(club_targets, WikiModel.LEAGUE, "LL"),
		"the club does not link its own league")
	_drop_second_competition()

func test_an_unknown_competition_is_rejected() -> void:
	assert_false(WikiModel.has_page(WikiModel.LEAGUE, "NOPE"), "a made-up competition resolved")
	assert_eq(WikiModel.label(WikiModel.LEAGUE, ""), "PREMIER LEAGUE",
		"the crumb numbers the wrong league")

# ------------------------------------------------------------------ helpers ---

## Copy one club row under a new id and competition, keeping every column the
## seed requires: the point is that a second league's clubs are ordinary rows.
func _clone_club(source: String, club_id: String, name: String, competition_id: String) -> void:
	var columns: Array = []
	for info in PLDatabase.rows("PRAGMA table_info(club);"):
		columns.append(str(info["name"]))
	var picks: Array = []
	for column in columns:
		match column:
			"id":
				picks.append("'%s'" % club_id)
			"competition_id":
				picks.append("'%s'" % competition_id)
			"name":
				picks.append("'%s'" % name)
			"short", "abbr":
				picks.append("'%s'" % club_id)
			_:
				picks.append(column)
	PLDatabase.execute(
		"INSERT INTO club (%s) SELECT %s FROM club WHERE id = '%s';" % [
			", ".join(columns), ", ".join(picks), source])

func _add_second_competition() -> void:
	PLDatabase.execute(
		"INSERT INTO competition (id, name, short_name, season_label) "
		+ "VALUES ('LL', 'La Liga', 'LA LIGA', '2026-27');")
	_clone_club("MUN", "RMA", "Real Madrid", "LL")
	_clone_club("LIV", "BAR", "Barcelona", "LL")
	PLDatabase.execute(
		"INSERT INTO table_row (club_id, position, played, won, drawn, lost, gf, ga, points) "
		+ "VALUES ('RMA', 1, 1, 1, 0, 0, 2, 0, 3), ('BAR', 2, 1, 0, 0, 1, 0, 2, 0);")
	PLDatabase.execute(
		"INSERT INTO fixture (id, competition_id, matchday, kickoff, home_club_id, "
		+ "away_club_id, home_goals, away_goals, played) "
		+ "VALUES ('ll-1', 'LL', 1, '2026-08-22', 'RMA', 'BAR', 2, 0, 1);")
	PLRepository.shared().invalidate()

func _drop_second_competition() -> void:
	PLDatabase.execute("DELETE FROM fixture WHERE competition_id = 'LL';")
	PLDatabase.execute("DELETE FROM table_row WHERE club_id IN ('RMA', 'BAR');")
	PLDatabase.execute("DELETE FROM club WHERE competition_id = 'LL';")
	PLDatabase.execute("DELETE FROM competition WHERE id = 'LL';")
	PLRepository.shared().invalidate()

## The chips block carrying the competition index: a hub opens with it.
func _chips(page: Dictionary) -> Array:
	for block in page.get("blocks", []):
		if str(block.get("k", "")) == "chips":
			return block.get("items", [])
	return []

## True when the competition index holds a chip for `text` that opens `id`.
func _chip_target(items: Array, text: String, id: String) -> bool:
	for item in items:
		if str(item.get("text", "")) != text:
			continue
		var target: Dictionary = item.get("target", {})
		return str(target.get("page", "")) == WikiModel.LEAGUE and str(target.get("id", "")) == id
	return false

func _has_target(targets: Array, page: String, id: String) -> bool:
	for target in targets:
		if str(target.get("page", "")) == page and str(target.get("id", "")) == id:
			return true
	return false

func _targets(page: Dictionary) -> Array:
	var out: Array = []
	for block in page.get("blocks", []):
		for row in block.get("rows", []):
			if row.has("target"):
				out.append(row["target"])
		for item in block.get("items", []):
			if item is Dictionary and item.has("target"):
				out.append(item["target"])
	return out

func _rows_in(page: Dictionary, section: String) -> int:
	var seen := false
	for block in page.get("blocks", []):
		if str(block.get("k")) == "section" and str(block.get("text")) == section:
			seen = true
			continue
		if seen and str(block.get("k")) == "table":
			return block["rows"].size()
		if seen and str(block.get("k")) == "section":
			return 0
		if seen and str(block.get("k")) != "table":
			return 0
	return 0
