class_name LeagueSeason
extends RefCounted


signal match_recorded(report: Dictionary)
signal state_changed

static var active: LeagueSeason = null


const COMPETITION_ORDER: Array = ["PL", "CH", "L1", "L2", "NL", "LL", "BL", "BL2", "SA", "SB"]

var save: LeagueSave = null
var record: LeagueRecord = null


var rules: Dictionary = {}
var rules_by: Dictionary = {}
var rng := RandomNumberGenerator.new()

var watching_fixture := ""

var finishing := false


var captured: Array = []
var last_advance: Dictionary = {}


static func create(name: String, calendar_mode: String, advance_mode: String, seed: int = 0,
		competitions: Array = ["PL"], cups: bool = false,
		cup_countries: Array = [], uefa: bool = false) -> LeagueSeason:
	return LeagueSeasonBoot.create(name, calendar_mode, advance_mode, seed, competitions, cups,
		cup_countries, uefa)


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


func fixtures_of(competition_id: String) -> LeagueFixtures:
	return record.fixtures if record != null else null


func state() -> Dictionary:
	return LeagueSeasonState.build(self)


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


	if not watch and record.interest.holds(fixture_id):
		return false
	var ok := record.fixtures.set_watch(fixture_id, watch)
	if ok:
		state_changed.emit()
	return ok


func suggest() -> Array:
	return LeaguePlanner.suggest(self)


func set_advance_mode(mode: String) -> bool:
	if save == null:
		return false
	var ok := save.set_advance_mode(mode)
	if ok:
		rules_by = save.rules_by
		rules = save.rules
		state_changed.emit()
	return ok


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


func goal_clip(fixture_id: String, goal_index: int) -> Dictionary:
	if record == null or fixture_id == "":
		return {}
	return record.report.clips.pack(fixture_id, goal_index)


func start_watch(fixture_id: String) -> Dictionary:
	return LeagueSeasonWatch.start(self, fixture_id)


func cancel_watch() -> void:
	LeagueSeasonWatch.cancel(self)


func capture_goal(pack: Dictionary) -> void:
	LeagueSeasonWatch.capture(self, pack)

func record_engine(engine) -> void:
	LeagueSeasonWatch.record_engine(self, engine)


func summary() -> Dictionary:
	return LeagueSeasonSummary.build(self)
