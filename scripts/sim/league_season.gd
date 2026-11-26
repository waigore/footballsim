class_name LeagueSeason
extends RefCounted

## The god-mode season loop: a save, its regulations, and the day-by-day clock.
##
## A Continue walks one shared calendar. On a fixture day every game the player
## left on Auto — in every active competition — is settled by the Dixon–Coles
## outcome model and given a synthetic report; a game marked Watch holds the
## whole clock where it is until the match engine hands back a result, so an
## unfinished watch can never be skipped or double-counted. Both paths write the
## same ledger rows, so a watched and an auto-simmed match are both historical
## reports afterwards.
##
## `active` is the season the scene is currently playing. It is how a finished
## watched match, recorded by PLSimStats from the match controller, finds its way
## back into the save without the controller knowing about leagues.
##
## Opening a save lives in `LeagueSeasonBoot`; a watched fixture's record path
## lives in `LeagueSeasonWatch`. This file keeps the clock and the narrow API
## screens call.

signal match_recorded(report: Dictionary)
signal state_changed

static var active: LeagueSeason = null

## The order a save keeps its competitions in, whatever order the wizard picked:
## fixtures, hub groups and the podium all read it (#241). `LeagueTiers.order()`
## is the same order and a test pins them together; it is spelled out here so a
## const read needs no call.
const COMPETITION_ORDER: Array = ["PL", "CH", "L1", "L2", "NL", "LL", "BL", "BL2"]

var save: LeagueSave = null
var record: LeagueRecord = null
## The primary competition's regulations (the first active one), kept flat for a
## caller that reads one league. `rules_by` is the full map.
var rules: Dictionary = {}
var rules_by: Dictionary = {}
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
## `competitions` names the leagues to run; the graph closes over the tiers above each.
static func create(name: String, calendar_mode: String, advance_mode: String, seed: int = 0,
		competitions: Array = ["PL"]) -> LeagueSeason:
	return LeagueSeasonBoot.create(name, calendar_mode, advance_mode, seed, competitions)

## Resume a save from disk and put the clock on the next unplayed fixture day.
static func open(slug: String) -> LeagueSeason:
	return LeagueSeasonBoot.open(slug)

static func engine_finished(engine) -> void:
	if active != null:
		active.record_engine(engine)

func close() -> void:
	if active == self:
		active = null
	if save != null:
		LeagueSave.close()

func matches_remaining() -> int:
	return record.fixtures.unplayed() if record != null else 0

## A competition's own calendar, for the UI's per-league tabs.
func fixtures_of(competition_id: String) -> LeagueFixtures:
	return record.fixtures if record != null else null

# ------------------------------------------------------------------ state ---

## Everything a screen needs for one frame: the clock, the day's fixtures, the
## table and whether the season is over. `table` is the first active league's
## table (a single-league caller reads it as before); `tables` and `competitions`
## carry every active league for the multi-league chrome.
func state() -> Dictionary:
	return LeagueSeasonState.build(self)

## The day's fixtures with the flags the planner draws, and the event rows of a
## played one, so the hub can print its side columns without a second read. The
## list is grouped in the save's competition order: PL then La Liga on a mixed day.
func plan() -> Array:
	if save == null or record == null:
		return []
	var out: Array = []
	for fx in record.fixtures.on(save.current_date()):
		var item: Dictionary = fx.duplicate()
		item["watch"] = int(fx["watched"]) == 1
		item["suggested"] = int(fx["suggested"]) == 1
		if str(fx["status"]) == "played":
			item["events"] = record.report.events(str(fx["id"]))
		out.append(item)
	return out

## Mark or unmark a club: the write and the shortlist's Watch sync both happen
## here, so a followed club's games are on Watch before the surface repaints.
## One shortlist across every active league.
func set_interest(club_id: String, follow: bool) -> bool:
	if record == null or not record.interest.has_club(club_id):
		return false
	if not record.interest.set_interest(club_id, follow):
		return false
	state_changed.emit()
	return true

func set_watch(fixture_id: String, watch: bool) -> bool:
	if finishing:
		return false
	# Interest wins: a followed club's game cannot be put back on Auto, or the
	# season would auto-sim a match the player asked to see (#104).
	if not watch and record.interest.holds(fixture_id):
		return false
	var ok := record.fixtures.set_watch(fixture_id, watch)
	if ok:
		state_changed.emit()
	return ok

## After five completed gameweeks, flag the upcoming clashes between clubs in
## the current top six so the planner can point at the games worth watching.
func suggest() -> Array:
	return LeaguePlanner.suggest(self)

## Change the shared clock policy mid-season; persisted for the next Continue.
func set_advance_mode(mode: String) -> bool:
	if save == null:
		return false
	var ok := save.set_advance_mode(mode)
	if ok:
		rules_by = save.rules_by
		rules = save.rules
		state_changed.emit()
	return ok

# ------------------------------------------------------------------- clock ---

## Play one step of the season. Auto fixtures due today — across every active
## league — are settled; watched fixtures block the clock until their match is
## played. Returns what happened so the screen can show a roundup.
func advance() -> Dictionary:
	if save == null or record == null:
		return {"ok": false}
	save.reload()
	rules_by = save.rules_by
	rules = save.rules
	if save.status() == "complete" or record.fixtures.unplayed() == 0:
		save.set_status("complete")
		return {"ok": true, "date": save.current_date(), "played": [], "pending": [], "complete": true}
	var date := save.current_date()
	var played: Array = []
	var pending: Array = []
	# One transaction per matchday: a dozen or two matches mean hundreds of
	# rows, and an fsync per row would make the season crawl.
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for fx in record.fixtures.pending_upto(date):
		if int(fx["watched"]) == 1:
			pending.append(fx)
		else:
			played.append(LeagueSeasonSim.fixture(self, fx))
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
	SeasonAvailability.month_tick(date, next)
	last_advance = {"ok": true, "date": date, "next_date": next, "played": played, "pending": [], "complete": false}
	return last_advance

## Move the clock past anything already settled (used when a save opens and
## after a watched match hands its result back).
func roll_clock() -> void:
	if save == null or save.status() == "complete":
		return
	if record.fixtures.unplayed() == 0:
		save.set_status("complete")
		return
	if not record.fixtures.pending_upto(save.current_date()).is_empty():
		return
	var next := _next_date(save.current_date())
	if next == "":
		save.set_status("complete")
		return
	var crossed := save.current_date()
	save.set_date(next)
	save.set_matchday(_matchday_of(next))
	SeasonAvailability.month_tick(crossed, next)

func _next_date(date: String) -> String:
	if str(rules.get("advance_mode", "fixture_days")) == "every_day":
		var d := FixtureCalendar.add_days(date, 1)
		if d > str(rules.get("season_end", d)) and record.fixtures.unplayed() == 0:
			return ""
		return d
	return record.fixtures.next_date(date)

func _matchday_of(date: String) -> int:
	var rows := record.fixtures.on(date)
	var gw := 0
	for fx in rows:
		gw = maxi(gw, int(fx["matchday"]))
	if gw > 0:
		return gw
	return save.matchday()

## A saved fixture as a report: score, synthetic or engine events, played flag.
func report(fixture_id: String) -> Dictionary:
	if record == null or fixture_id == "":
		return {}
	var fx := record.fixtures.one(fixture_id)
	if fx.is_empty():
		return {}
	return {
		"fixture": fx, "score": [int(fx["home_goals"]), int(fx["away_goals"])],
		"events": record.report.events(fixture_id), "highlights": record.report.clips.list(fixture_id),
		"played": str(fx["status"]) == "played",
	}

## One stored goal clip, decoded and ready for the match viewer.
func goal_clip(fixture_id: String, goal_index: int) -> Dictionary:
	if record == null or fixture_id == "":
		return {}
	return record.report.clips.pack(fixture_id, goal_index)

# ------------------------------------------------------------------ watch ---

## Hand one fixture to the match viewer. The screen starts the engine with these
## clubs; when it reaches full time, `engine_finished` records the result here.
func start_watch(fixture_id: String) -> Dictionary:
	return LeagueSeasonWatch.start(self, fixture_id)

## Back out of a pre-match briefing: the fixture never kicked off, so the season
## stops waiting for it. The fixture keeps its Watch flag and the clock stays on
## the day, so the next Continue offers the same game again.
func cancel_watch() -> void:
	LeagueSeasonWatch.cancel(self)

## The viewer's ring caught a goal during a watched fixture: hold the clip here
## until full time, when it is written beside the report it belongs to.
func capture_goal(pack: Dictionary) -> void:
	LeagueSeasonWatch.capture(self, pack)

func record_engine(engine) -> void:
	LeagueSeasonWatch.record_engine(self, engine)

# ------------------------------------------------------------ season end ---

## Champion, runner-up, European places and the drop per active competition,
## read from that league's saved regulations. Empty until every active
## competition has played out its calendar. The reading itself lives in
## `LeagueSeasonSummary`.
func summary() -> Dictionary:
	return LeagueSeasonSummary.build(self)
