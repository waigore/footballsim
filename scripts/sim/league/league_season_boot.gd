class_name LeagueSeasonBoot
extends RefCounted


static func create(name: String, calendar_mode: String, advance_mode: String, seed: int = 0,
		competitions: Array = ["PL"], cups: bool = false,
		cup_countries: Array = [], uefa: bool = false) -> LeagueSeason:
	var saved_mode := calendar_mode if LeagueRules.CALENDAR_MODES.has(calendar_mode) else "generated"
	var saved_advance := advance_mode if LeagueRules.ADVANCE_MODES.has(advance_mode) else "fixture_days"
	if seed == 0:
		seed = int(Time.get_unix_time_from_system()) % 1000000


	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	var wanted: Array = known_competitions(competitions)
	var built: Array = []
	var rules_map := {}
	var first := ""
	for i in range(wanted.size()):
		var cid := str(wanted[i])
		var comp_rules := LeagueRules.defaults(saved_mode, saved_advance, cid)
		var fixtures := FixtureCalendar.build(saved_mode, comp_rules, seed + i * 97, cid)
		if fixtures.is_empty():
			return null
		comp_rules["season_start"] = str(fixtures[0]["kickoff"])
		comp_rules["season_end"] = str(fixtures[fixtures.size() - 1]["kickoff"])
		if first == "" or str(fixtures[0]["kickoff"]) < first:
			first = str(fixtures[0]["kickoff"])
		built.append({"competition_id": cid, "fixtures": fixtures})
		rules_map[cid] = comp_rules
	var save := LeagueSave.create(name, rules_map, seed, wanted)
	if save == null:
		return null
	var season := LeagueSeason.new()
	season.save = save
	season.record = LeagueRecord.new(save)
	season.record.fixtures.clear()
	for i in range(built.size()):
		var entry: Dictionary = built[i]
		if not season.record.fixtures.install(entry["fixtures"], str(entry["competition_id"]), i == 0):
			LeagueSave.close()
			return null
	save.reload()
	season.rules_by = save.rules_by
	season.rules = save.rules

	save.set_date(first)
	save.set_matchday(season.matchday_of(first))
	StrongestXI.apply_all()
	save.reload()
	season.rules_by = save.rules_by
	season.rules = save.rules
	season.rng.seed = seed
	save.put_meta("cups", "on" if cups else "off")
	save.put_meta("cups_off", ",".join(PackedStringArray(_off_countries(cup_countries))))
	save.put_meta("uefa", "on" if uefa else "off")
	LeagueCupState.start(season)
	save.reload()
	season.rules_by = save.rules_by
	season.rules = save.rules
	LeagueUefaState.start(season)
	save.reload()
	season.rules_by = save.rules_by
	season.rules = save.rules
	SquadList.bootstrap(season.save)
	if uefa:
		var earliest := PLDatabase.row(
			"SELECT MIN(kickoff) AS d FROM league_fixture WHERE status <> 'played';")
		if earliest.get("d", null) != null and str(earliest["d"]) < save.current_date():
			save.set_date(str(earliest["d"]))
			save.set_matchday(season.matchday_of(str(earliest["d"])))
	LeagueSeason.active = season
	return season


static func _off_countries(cup_countries: Array) -> Array:
	var off: Array = []
	if cup_countries.is_empty():
		return off
	for country in LeagueCup.countries():
		if not cup_countries.has(country):
			off.append(str(country))
	return off


static func known_competitions(wanted: Array) -> Array:
	var known: Array = []
	for row in PLDatabase.rows("SELECT id FROM competition ORDER BY rowid;"):
		known.append(str(row["id"]))
	var closed := LeagueTiers.close_up(wanted)
	var out: Array = []
	for cid in LeagueSeason.COMPETITION_ORDER:
		if closed.has(cid) and known.has(cid):
			out.append(cid)
	for cid in closed:
		if known.has(str(cid)) and not out.has(str(cid)):
			out.append(str(cid))
	if out.is_empty() and not known.is_empty():
		out.append(str(known[0]))
	return out


static func open(slug: String) -> LeagueSeason:
	var save := LeagueSave.open(slug)
	if save == null:
		return null
	var season := LeagueSeason.new()
	season.save = save
	season.record = LeagueRecord.new(save)
	season.rules_by = save.rules_by
	season.rules = save.rules
	season.rng.seed = int(str(save.meta.get("seed", "0")))


	season.record.standings.recompute()


	season.record.interest.force_watch()
	LeagueCupState.start(season)
	LeagueUefaState.start(season)
	season.roll_clock()
	LeagueSeason.active = season
	return season
