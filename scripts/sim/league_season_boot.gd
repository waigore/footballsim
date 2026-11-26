class_name LeagueSeasonBoot
extends RefCounted

## Opening a season: build a new save from the wizard's picks, or resume one from
## disk. Split out of `LeagueSeason` so the clock keeps the day-by-day loop and
## this module owns the one-shot setup that hands it a save.

## New named save: calendar, strongest XIs, ledger, clock on gameweek one.
## `competitions` names the leagues to run; the graph closes over the tiers above each.
static func create(name: String, calendar_mode: String, advance_mode: String, seed: int = 0,
		competitions: Array = ["PL"]) -> LeagueSeason:
	var saved_mode := calendar_mode if LeagueRules.CALENDAR_MODES.has(calendar_mode) else "generated"
	var saved_advance := advance_mode if LeagueRules.ADVANCE_MODES.has(advance_mode) else "fixture_days"
	if seed == 0:
		seed = int(Time.get_unix_time_from_system()) % 1000000
	# Build every active league's calendar from the seed, then hand the whole set
	# to the save: one file, one clock, one fixture table keyed by competition.
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
	# The shared clock opens on the earliest first fixture across the actives.
	save.set_date(first)
	save.set_matchday(season._matchday_of(first))
	StrongestXI.apply_all()
	save.reload()
	season.rules_by = save.rules_by
	season.rules = save.rules
	season.rng.seed = seed
	LeagueSeason.active = season
	return season

## Only competitions the seed carries, in the canonical order — the wizard's
## pick order is not the fixture order — and never none (#241). A lower tier
## closes over every tier above it (#258).
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

## Resume a save from disk and put the clock on the next unplayed fixture day.
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
	# An older save may predate the home/away columns, and a hand-edited fixture
	# ledger can drift: rebuild the aggregates now so the table (and its full
	# reading) matches the played fixtures (#73).
	season.record.standings.recompute()
	# Interest is the save's, so a reopened season re-applies it before the clock
	# rolls: a followed club's game is never left on Auto by a stale flag (#104).
	season.record.interest.force_watch()
	season.roll_clock()
	LeagueSeason.active = season
	return season
