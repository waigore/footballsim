class_name LeagueSeason
extends RefCounted

## The god-mode season loop: a save, its regulations, and the day-by-day clock.
##
## A Continue walks the calendar. On a fixture day every game the player left on
## Auto is settled by the Dixon–Coles outcome model and given a synthetic report;
## a game marked Watch holds the clock where it is until the match engine hands
## back a result, so an unfinished watch can never be skipped or double-counted.
## Both paths write the same ledger rows, so a watched and an auto-simmed match
## are both historical reports afterwards.
##
## `active` is the season the scene is currently playing. It is how a finished
## watched match, recorded by PLSimStats from the match controller, finds its way
## back into the save without the controller knowing about leagues.

signal match_recorded(report: Dictionary)
signal state_changed

## Completed gameweeks before the planner starts suggesting watches.
const SUGGEST_AFTER_ROUNDS := 5

static var active: LeagueSeason = null

var save: LeagueSave = null
var record: LeagueRecord = null
var rules: Dictionary = {}
var rng := RandomNumberGenerator.new()
## Fixture the engine is currently playing back, if any.
var watching_fixture := ""
## True while a watch the player left early is being played out on the engine.
var finishing := false
## Live clips captured for the fixture being watched, keyed by the goal's own
## minute and scorer; written when the result comes back at full time.
var captured: Array = []
var last_advance: Dictionary = {}

# ------------------------------------------------------------------ setup ---

## New named save: calendar, strongest XIs, ledger, clock on gameweek one.
static func create(name: String, calendar_mode: String, advance_mode: String, seed: int = 0) -> LeagueSeason:
	var saved_mode := calendar_mode if LeagueRules.CALENDAR_MODES.has(calendar_mode) else "generated"
	var saved_advance := advance_mode if LeagueRules.ADVANCE_MODES.has(advance_mode) else "fixture_days"
	if seed == 0:
		seed = int(Time.get_unix_time_from_system()) % 1000000
	var rules := LeagueRules.defaults(saved_mode, saved_advance)
	var fixtures := FixtureCalendar.build(saved_mode, rules, seed)
	if fixtures.is_empty():
		return null
	rules["season_start"] = str(fixtures[0]["kickoff"])
	rules["season_end"] = str(fixtures[fixtures.size() - 1]["kickoff"])
	var save := LeagueSave.create(name, rules, seed)
	if save == null:
		return null
	var season := LeagueSeason.new()
	season.save = save
	season.record = LeagueRecord.new(save)
	if not season.record.install(fixtures):
		LeagueSave.close()
		return null
	StrongestXI.apply_all()
	save.reload()
	season.rules = save.rules
	season.rng.seed = seed
	active = season
	return season

## Resume a save from disk and put the clock on the next unplayed fixture day.
static func open(slug: String) -> LeagueSeason:
	var save := LeagueSave.open(slug)
	if save == null:
		return null
	var season := LeagueSeason.new()
	season.save = save
	season.record = LeagueRecord.new(save)
	season.rules = save.rules
	season.rng.seed = int(str(save.meta.get("seed", "0")))
	# An older save may predate the home/away columns, and a hand-edited fixture
	# ledger can drift: rebuild the aggregates now so the table (and its full
	# reading) matches the played fixtures (#73).
	season.record.recompute_table()
	season.roll_clock()
	active = season
	return season

static func engine_finished(engine) -> void:
	if active != null:
		active.record_engine(engine)

func close() -> void:
	if active == self:
		active = null
	if save != null:
		LeagueSave.close()

func matches_remaining() -> int:
	return record.unplayed() if record != null else 0

# ------------------------------------------------------------------ state ---

## Everything a screen needs for one frame: the clock, the day's fixtures, the
## table and whether the season is over.
func state() -> Dictionary:
	if save == null:
		return {}
	save.reload()
	rules = save.rules
	var date := save.current_date()
	var fixtures := record.fixtures_on(date)
	var complete := save.status() == "complete"
	return {
		"slug": save.slug,
		"name": save.name(),
		"status": save.status(),
		"date": date,
		"day": FixtureCalendar.day_label(date),
		"matchday": save.matchday(),
		"fixtures": fixtures,
		"pending": record.pending_upto(date),
		"table": record.table(),
		"played": record.played(),
		"total": record.played() + record.unplayed(),
		"rounds": record.completed_matchdays(),
		"can_suggest": record.completed_matchdays() >= SUGGEST_AFTER_ROUNDS,
		"advance_mode": str(rules.get("advance_mode", "fixture_days")),
		"rules": rules.duplicate(true),
		"complete": complete,
		"summary": summary() if complete else {},
	}

## The day's fixtures with the flags the planner draws.
func plan() -> Array:
	if save == null or record == null:
		return []
	var out: Array = []
	for fx in record.fixtures_on(save.current_date()):
		var item: Dictionary = fx.duplicate()
		item["watch"] = int(fx["watched"]) == 1
		item["suggested"] = int(fx["suggested"]) == 1
		out.append(item)
	return out

func set_watch(fixture_id: String, watch: bool) -> bool:
	if finishing:
		return false
	var ok := record.set_watch(fixture_id, watch)
	if ok:
		state_changed.emit()
	return ok

## After five completed gameweeks, flag the upcoming clashes between clubs in
## the current top six so the planner can point at the games worth watching.
func suggest() -> Array:
	if record.completed_matchdays() < SUGGEST_AFTER_ROUNDS:
		return []
	var top := _top_six()
	var ids: Array = []
	for fx in record.pending_upto(save.current_date()):
		if top.has(str(fx["home_club_id"])) and top.has(str(fx["away_club_id"])):
			ids.append(str(fx["id"]))
	record.suggest(ids)
	state_changed.emit()
	return ids

func _top_six() -> Dictionary:
	var out := {}
	var rows := record.table()
	for i in range(mini(6, rows.size())):
		out[str(rows[i]["club_id"])] = true
	return out

# ------------------------------------------------------------------- clock ---

## Play one step of the season. Auto fixtures due today are settled; watched
## fixtures block the clock until their match is played. Returns what happened
## so the screen can show a roundup.
func advance() -> Dictionary:
	if save == null or record == null:
		return {"ok": false}
	save.reload()
	rules = save.rules
	if save.status() == "complete" or record.unplayed() == 0:
		save.set_status("complete")
		return {"ok": true, "date": save.current_date(), "played": [], "pending": [], "complete": true}
	var date := save.current_date()
	var played: Array = []
	var pending: Array = []
	# One transaction per matchday: a dozen matches mean hundreds of rows, and
	# an fsync per row would make the season crawl.
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for fx in record.pending_upto(date):
		if int(fx["watched"]) == 1:
			pending.append(fx)
		else:
			played.append(_sim_fixture(fx))
	PLDatabase.transaction("COMMIT;")
	if not pending.is_empty():
		last_advance = {"ok": true, "date": date, "played": played, "pending": pending, "complete": false}
		return last_advance
	var next := _next_date(date)
	if next == "":
		save.set_status("complete")
		last_advance = {"ok": true, "date": date, "played": played, "pending": [], "complete": true}
		return last_advance
	save.set_date(next)
	save.set_matchday(_matchday_of(next))
	last_advance = {"ok": true, "date": date, "next_date": next, "played": played, "pending": [], "complete": false}
	return last_advance

## Move the clock past anything already settled (used when a save opens and
## after a watched match hands its result back).
func roll_clock() -> void:
	if save == null or save.status() == "complete":
		return
	if record.unplayed() == 0:
		save.set_status("complete")
		return
	if not record.pending_upto(save.current_date()).is_empty():
		return
	var next := _next_date(save.current_date())
	if next == "":
		save.set_status("complete")
		return
	save.set_date(next)
	save.set_matchday(_matchday_of(next))

func _next_date(date: String) -> String:
	if str(rules.get("advance_mode", "fixture_days")) == "every_day":
		var d := FixtureCalendar.add_days(date, 1)
		if d > str(rules.get("season_end", d)) and record.unplayed() == 0:
			return ""
		return d
	return record.next_date(date)

func _matchday_of(date: String) -> int:
	var rows := record.fixtures_on(date)
	for fx in rows:
		return int(fx["matchday"])
	return save.matchday()

# ---------------------------------------------------------------- outcomes ---

func _sim_fixture(fx: Dictionary) -> Dictionary:
	var fixture_id := str(fx["id"])
	var home := str(fx["home_club_id"])
	var away := str(fx["away_club_id"])
	var seed := _seed_for(fixture_id)
	var model := PoissonModel.new(seed, home, away)
	var score := model.sample()
	var hxi := StrongestXI.pick(TeamData.get_team(home))
	var axi := StrongestXI.pick(TeamData.get_team(away))
	var events: Array = []
	events.append_array(MatchEvents.side(seed + 11, fixture_id, home, hxi, score.x))
	events.append_array(MatchEvents.side(seed + 23, fixture_id, away, axi, score.y))
	record.save_result(fixture_id, score.x, score.y)
	record.add_events(events)
	_add_xi_stats(events, {"home": hxi, "away": axi}, {"home": home, "away": away})
	LeagueHighlights.store_auto(record, int(rng.seed), fixture_id, events,
		{"home": hxi, "away": axi}, home, away)
	return report(fixture_id)

## A side's XI all played 90 minutes; goals, assists and cards come off the
## synthetic event rows, so the season chart reads the same report the player saw.
func _add_xi_stats(events: Array, sides: Dictionary, clubs: Dictionary) -> void:
	var lines := {}
	for side in ["home", "away"]:
		for p in sides[side]:
			lines[str(p["id"])] = {"apps": 1, "goals": 0, "assists": 0, "yellow": 0, "red": 0}
	for e in events:
		var id := str(e.get("player_id", ""))
		if not lines.has(id):
			continue
		var kind := str(e.get("kind", ""))
		if kind == "goal":
			lines[id]["goals"] += 1
		elif kind == "assist":
			lines[id]["assists"] += 1
		elif kind == "yellow":
			lines[id]["yellow"] += 1
		elif kind == "red":
			lines[id]["red"] += 1
	var rows: Array = []
	for side in ["home", "away"]:
		for p in sides[side]:
			var id := str(p["id"])
			rows.append({"player_id": id, "club_id": str(clubs[side]), "line": lines[id]})
	record.add_player_lines(rows)

func _seed_for(fixture_id: String) -> int:
	var h := 0
	for i in range(fixture_id.length()):
		h = int((h * 31 + fixture_id.unicode_at(i)) % 2147483647)
	return int(rng.seed) + h

## A saved fixture as a report: score, synthetic or engine events, played flag.
func report(fixture_id: String) -> Dictionary:
	if record == null or fixture_id == "":
		return {}
	var fx := record.fixture(fixture_id)
	if fx.is_empty():
		return {}
	return {
		"fixture": fx, "score": [int(fx["home_goals"]), int(fx["away_goals"])],
		"events": record.events(fixture_id), "highlights": record.clips.list(fixture_id),
		"played": str(fx["status"]) == "played",
	}

## One stored goal clip, decoded and ready for the match viewer.
func goal_clip(fixture_id: String, goal_index: int) -> Dictionary:
	if record == null or fixture_id == "":
		return {}
	return record.clips.pack(fixture_id, goal_index)

# ------------------------------------------------------------------ watch ---

## Hand one fixture to the match viewer. The screen starts the engine with these
## clubs; when it reaches full time, `engine_finished` records the result here.
func start_watch(fixture_id: String) -> Dictionary:
	if record == null or fixture_id == "" or finishing:
		return {}
	var fx := record.fixture(fixture_id)
	if fx.is_empty():
		return {}
	watching_fixture = fixture_id
	captured = []
	return {
		"fixture_id": fixture_id,
		"home": str(fx["home_club_id"]), "away": str(fx["away_club_id"]),
	}

## The viewer's ring caught a goal during a watched fixture: hold the clip here
## until full time, when it is written beside the report it belongs to.
func capture_goal(pack: Dictionary) -> void:
	if watching_fixture == "" or pack.is_empty():
		return
	captured.append(pack)

func record_engine(engine) -> void:
	var fixture_id := watching_fixture
	if fixture_id == "":
		return
	watching_fixture = ""
	finishing = false
	var fx := record.fixture(fixture_id)
	if fx.is_empty():
		return
	var home := int(engine.score[0])
	var away := int(engine.score[1])
	PLDatabase.transaction("BEGIN TRANSACTION;")
	record.save_result(fixture_id, home, away)
	record.add_events(LeagueHighlights.engine_events(engine, fixture_id))
	var lines: Array = []
	for p in engine.players:
		lines.append({
			"player_id": str(p.key), "club_id": str(engine.teams[p.team]["id"]),
			"line": {
				"apps": 1, "goals": int(p.stats.get("goals", 0)),
				"assists": int(p.stats.get("assists", 0)), "yellow": int(p.yellow),
				"red": 1 if p.red else 0,
			},
		})
	record.add_player_lines(lines)
	var sides := {"home": [], "away": []}
	for p in engine.players:
		var side := "home" if int(p.team) == 0 else "away"
		sides[side].append({"id": str(p.key), "role": str(p.role)})
	LeagueHighlights.store_watch(record, int(rng.seed), fixture_id, captured, sides,
		str(fx["home_club_id"]), str(fx["away_club_id"]))
	captured = []
	PLDatabase.transaction("COMMIT;")
	# The clock stays on the day just played so the hub can show its result, and
	# the next Continue moves on (#124); `open()` still rolls a played day forward.
	state_changed.emit()
	match_recorded.emit(report(fixture_id))

# ------------------------------------------------------------ season end ---

## Champion, runner-up, European places and the drop, read from the saved
## regulations. Empty until every fixture is played.
func summary() -> Dictionary:
	if save == null or record == null or record.unplayed() > 0:
		return {}
	var rows := record.table()
	if rows.size() < 20:
		return {}
	var places := LeagueRules.places(rules)
	var europe: Array = []
	for i in range(mini(int(places["europe"]), rows.size())):
		europe.append({"position": i + 1, "club": str(rows[i]["club_name"]), "zone": str(rows[i]["club_id"])})
	var relegated: Array = []
	for i in range(rows.size() - int(places["relegation"]), rows.size()):
		relegated.append({"position": i + 1, "club": str(rows[i]["club_name"]), "club_id": str(rows[i]["club_id"])})
	return {
		"champion": {"club": str(rows[0]["club_name"]), "club_id": str(rows[0]["club_id"]), "points": int(rows[0]["points"])},
		"runner_up": {"club": str(rows[1]["club_name"]), "club_id": str(rows[1]["club_id"]), "points": int(rows[1]["points"])},
		"europe": europe,
		"relegated": relegated,
		"places": places,
		"top_scorers": record.top_scorers(5),
	}
