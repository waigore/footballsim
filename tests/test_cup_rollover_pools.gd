extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_cup_pools_506")
var CACHE_DIR := TestScratch.dir("cache_cup_pools_506")
const SEED := 7301
const COMPS := ["PL", "LL", "BL", "SA"]
const TIERS := ["PL", "CH", "L1", "L2", "NL", "LL", "BL", "BL2", "SA", "SB"]

static var shared: LeagueSeason = null
static var opened: Array = []


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func after_all() -> void:
	for season in opened:
		(season as LeagueSeason).close()
	opened.clear()
	shared = null
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _live() -> LeagueSeason:
	if shared != null and LeagueSeason.active == shared:
		return shared
	shared = LeagueSeason.create("Cup Pools", "generated", "fixture_days", SEED, COMPS, true)
	assert_not_null(shared, "the pool save was not created")
	opened.append(shared)
	return shared


func _ids(tier: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT id FROM club WHERE competition_id = ? ORDER BY name;", [tier]):
		out.append(str(row["id"]))
	return out


func _members(competition_id: String, role: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE member_kind = 'club' "
			+ "AND competition_id = ? AND role = ? ORDER BY member_id;", [competition_id, role]):
		out.append(str(row["member_id"]))
	return out


func _seed(index: int) -> void:
	_live()
	PLDatabase.execute("DELETE FROM season_archive;")
	for tier in TIERS:
		var ids := _ids(str(tier))
		for i in range(ids.size()):
			PLDatabase.execute(
				"INSERT OR REPLACE INTO season_archive (season_index, competition_id, club_id, "
				+ "club_name, position) VALUES (?, ?, ?, ?, ?);",
				[index, str(tier), str(ids[i]), str(ids[i]), i + 1])


func _rebuild(winners: Dictionary = {}, runners: Dictionary = {}) -> Dictionary:
	return LeagueCupPools.rebuild(_live(), 0, winners, runners)


func _sorted(ids: Array) -> Array:
	var out: Array = ids.duplicate()
	out.sort()
	return out


func _same(a: Array, b: Array) -> bool:
	return _sorted(a) == _sorted(b)


func _without(ids: Array, remove: Array) -> Array:
	var drop := {}
	for club_id in remove:
		drop[str(club_id)] = true
	var out: Array = []
	for club_id in ids:
		if not drop.has(str(club_id)):
			out.append(str(club_id))
	return out


func _stubs(competition_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT id FROM club WHERE competition_id = ? ORDER BY id;", [competition_id]):
		out.append(str(row["id"]))
	return out


func _stub_roles() -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT m.competition_id, m.role, m.member_id FROM competition_member m "
			+ "JOIN club c ON c.id = m.member_id WHERE m.member_kind = 'club' "
			+ "AND c.competition_id = m.competition_id ORDER BY 1, 2, 3;"):
		out.append("%s|%s|%s" % [str(row["competition_id"]), str(row["role"]),
			str(row["member_id"])])
	return out


func test_the_fa_cup_follows_the_live_tiers() -> void:
	_seed(0)
	var climber := str(_ids("CH")[0])
	PLDatabase.execute("UPDATE club SET competition_id = 'PL' WHERE id = ?;", [climber])
	var pools := _rebuild()
	PLDatabase.execute("UPDATE club SET competition_id = 'CH' WHERE id = ?;", [climber])
	var r3 := _members("FAC", "R3")
	var r1 := _members("FAC", "R1")
	assert_eq(int(pools.get("cups", 0)), 5, "the rebuild named every cup")
	assert_eq(r3.size(), 44, "the FA Cup third round is not the top two tiers")
	assert_true(r3.has(climber), "a promoted club missed the FA Cup third round")
	assert_false(r1.has(climber), "a promoted club stayed in the FA Cup first round")
	assert_true(_same(_without(r1, _stubs("FAC")), _ids("L1") + _ids("L2") + _ids("NL")),
		"the FA Cup first round is not League One, Two and the National League")


func test_the_stubs_keep_their_cup_slots() -> void:
	_seed(0)
	var before := _stub_roles()
	_rebuild()
	assert_false(before.is_empty(), "the seed carries no cup stubs")
	assert_eq(_stub_roles(), before, "a stub left its cup slot")


func test_the_carabao_byes_follow_europe() -> void:
	_seed(0)
	_rebuild()
	var r3 := _members("EFLC", "R3")
	var r2 := _members("EFLC", "R2")
	var pr := _members("EFLC", "PR")
	var europe := {}
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE member_kind = 'club' "
			+ "AND competition_id IN ('UCL', 'UEL', 'UECL');"):
		europe[str(row["member_id"])] = true
	assert_eq(r3.size(), 9, "the Carabao third round is not nine clubs")
	assert_eq(r2.size(), 11, "the Carabao second round is not eleven clubs")
	for club_id in r3:
		assert_true(europe.has(club_id), "%s took a bye without Europe" % club_id)
	assert_true(_same(r3 + r2, _ids("PL")), "the Carabao lost or doubled a Premier League club")
	assert_true(_same(pr, _ids("L2").slice(-4)),
		"the preliminary round is not the lowest four League Two clubs")


func test_the_community_shield_names_the_cup_winner() -> void:
	_seed(0)
	var pl := _ids("PL")
	_rebuild({"FAC": str(pl[2])})
	assert_true(_same(_members("CS", "F"), [str(pl[0]), str(pl[2])]),
		"the Community Shield is not last season's champion v the FA Cup winner")


func test_a_double_sends_the_league_runner_up() -> void:
	_seed(0)
	var pl := _ids("PL")
	_rebuild({"FAC": str(pl[0])})
	assert_true(_same(_members("CS", "F"), [str(pl[0]), str(pl[1])]),
		"a league and cup double did not send the runner-up")


func test_a_missing_cup_winner_falls_back_to_the_league() -> void:
	_seed(0)
	var pl := _ids("PL")
	_rebuild()
	assert_true(_same(_members("CS", "F"), [str(pl[0]), str(pl[1])]),
		"a missing cup winner did not fall back to the league place")


func test_the_supercopa_fills_overlaps_from_the_table() -> void:
	_seed(0)
	var ll := _ids("LL")
	_rebuild({"CDR": str(ll[5])}, {"CDR": str(ll[0])})
	var four := [str(ll[0]), str(ll[1]), str(ll[5]), str(ll[2])]
	assert_true(_same(_members("SCE", "SF"), four),
		"the Supercopa four did not fill the overlap from the table")
	assert_true(_same(_members("CDR", "R32"), four),
		"the Copa round of 32 is not the Supercopa four")
	assert_true(_same(_without(_members("CDR", "R1"), _stubs("CDR")), _without(ll, four)),
		"the Copa first round still holds a Supercopa club")


func test_the_coppa_seeds_the_top_eight() -> void:
	_seed(0)
	_rebuild()
	var sa := _ids("SA")
	var sb := _ids("SB")
	assert_true(_same(_members("CI", "R16"), sa.slice(0, 8)),
		"the Coppa round of 16 is not the top eight of Serie A")
	assert_true(_same(_without(_members("CI", "PR"), _stubs("CI")), sb.slice(sb.size() - 4)),
		"the Coppa preliminary round is not the lowest four of Serie B")
	assert_true(_same(_without(_members("CI", "R1"), _stubs("CI")),
			sa.slice(8) + sb.slice(0, sb.size() - 4)),
		"the Coppa first round is not the rest of Serie A and Serie B")


func test_the_dfp_pokal_takes_both_bundesligas() -> void:
	_seed(0)
	_rebuild()
	var r1 := _without(_members("DFBP", "R1"), _stubs("DFBP"))
	assert_eq(r1.size(), 36, "the DFB-Pokal first round is not the two Bundesligas")
	assert_true(_same(r1, _ids("BL") + _ids("BL2")),
		"the DFB-Pokal first round lost a Bundesliga club")


func test_cups_off_write_nothing() -> void:
	var plain := LeagueSeason.create("Cup Pools Off", "generated", "fixture_days", 8102,
		["PL"], false)
	assert_not_null(plain, "the cup-less save was not created")
	opened.append(plain)
	var before := _members("FAC", "R1")
	var pools := LeagueCupPools.rebuild(plain, 0, {}, {})
	assert_eq(int(pools.get("cups", -1)), 0, "a cup-less save rebuilt a cup pool")
	assert_eq(int(pools.get("supercups", -1)), 0, "a cup-less save rebuilt a supercup")
	assert_eq(_members("FAC", "R1"), before, "a cup-less save rewrote the FA Cup pool")


func test_the_rollover_refills_the_cups_from_the_pyramid() -> void:
	var season := LeagueSeason.create("Cup Pools Rollover", "generated", "fixture_days", 9203,
		["PL", "CH", "L1"], true)
	assert_not_null(season, "the rollover save was not created")
	opened.append(season)
	PLDatabase.execute(
		"UPDATE league_fixture SET status = 'played', home_goals = 3, away_goals = 1 "
		+ "WHERE status <> 'played';")
	season.record.standings.recompute()
	season.save.set_status("complete")
	season.save.reload()
	var lower := {}
	for row in PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'L1';"):
		lower[str(row["id"])] = true
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	var climbed: Array = []
	for row in PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'CH';"):
		if lower.has(str(row["id"])):
			climbed.append(str(row["id"]))
	assert_false(climbed.is_empty(), "the pyramid promoted nobody")
	var r3 := LeagueCup.entrants("FAC", "R3")
	var r1 := LeagueCup.entrants("FAC", "R1")
	for club_id in climbed:
		assert_true(r3.has(club_id), "a promoted club missed the FA Cup third round")
		assert_false(r1.has(club_id), "a promoted club stayed in the FA Cup first round")
	assert_eq(int((result["pools"] as Dictionary).get("cups", 0)), 2,
		"the rollover rebuilt no English cup pool")
	var champion := str(SeasonArchive.table(0, "PL")[0]["club_id"])
	var shield := LeagueCup.entrants("CS", "F")
	assert_eq(shield.size(), 2, "the Community Shield has no pair")
	assert_true(shield.has(champion), "the Community Shield lost the champion")
