extends SceneTree

## Headless e2e smoke leg 2: a season with every competition the seed carries,
## auto-simmed for 21 calendar days.
##   godot --headless --path . --script res://tools/smoke/all_leagues.gd
##
## Proves the multi-league season create (one save, one clock, every calendar),
## the Continue/auto settlement across competitions, and a multi-week calendar
## advance — none of which the derby leg touches. No pitch, HUD, team select or
## watched matches: every fixture stays on Auto, so one Continue settles every
## league due that day.
##
## Exits 0 once the clock is at least 21 days past day one and every fixture due
## in that window is played in every selected league; non-zero otherwise.

const SEED := 1200
const WINDOW_DAYS := 21
## The e2e-smoke job gives this leg its own wall allotment; exceeding it fails
## here with a readable message instead of at the job timeout.
const WALL_BUDGET_SEC := 120.0
const MAX_STEPS := 400

var started := 0
var save_dir := ""
var cache_dir := ""
var failed := false

func _init() -> void:
	started = Time.get_ticks_msec()
	# A private user:// folder per run: every checkout shares one Godot user
	# directory, so fixed names let concurrent runs delete each other's saves.
	save_dir = "user://smoke_all_leagues_saves_%d" % OS.get_process_id()
	cache_dir = "user://smoke_all_leagues_cache_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(save_dir)
	DirAccess.make_dir_recursive_absolute(cache_dir)
	LeagueSave.dir = save_dir
	PLDatabase.cache_dir = cache_dir
	PLDatabase.reset()
	PLRepository.shared().invalidate()

	var wanted: Array = PLCompetitions.active_ids()
	print("SMOKE2 competitions=%s" % [",".join(PackedStringArray(wanted))])
	if wanted.size() < 2:
		_fail("the seed carries %d competition(s); a multi-league smoke needs 2+" % wanted.size())
		return
	var season := LeagueSeason.create("Smoke All Leagues", "generated", "fixture_days", SEED, wanted)
	if season == null:
		_fail("the all-league season was not created (%s)" % LeagueSave.last_error)
		return
	var selected: Array = season.save.competition_ids()
	if selected.size() != wanted.size():
		_fail("the save runs %d of %d selected competitions" % [selected.size(), wanted.size()])
		season.close()
		return

	var start: String = season.save.current_date()
	var target := FixtureCalendar.add_days(start, WINDOW_DAYS)
	print("SMOKE2 season created date=%s target=%s fixtures=%d create=%.1fs" % [
		start, target, season.record.fixtures.unplayed(),
		float(Time.get_ticks_msec() - started) / 1000.0])
	var steps := 0
	# The window is the shared clock, from day one to the day it stands on. It
	# opens on the earliest first fixture, so a league whose season starts a week
	# later (the Bundesliga) has nothing due at 21 days: the loop keeps Continues
	# coming until every selected league has played too, so the per-league
	# assertion below is never vacuous.
	while not _window_closed(season, selected, start):
		if _wall_exceeded():
			season.close()
			return
		var step := season.advance()
		if not bool(step.get("ok", false)):
			_fail("Continue refused at %s" % season.save.current_date())
			season.close()
			return
		var pending: Array = step.get("pending", [])
		if not pending.is_empty():
			_fail("%d fixture(s) waited for a watch; every fixture must stay on Auto" % pending.size())
			season.close()
			return
		if bool(step.get("complete", false)):
			_fail("the season finished on %s, before the %d-day window closed" % [
				season.save.current_date(), WINDOW_DAYS])
			season.close()
			return
		steps += 1
		print("SMOKE2 continue %d date=%s played=%d wall=%.1fs" % [
			steps, season.save.current_date(), (step.get("played", []) as Array).size(),
			float(Time.get_ticks_msec() - started) / 1000.0])
		if steps > MAX_STEPS:
			_fail("the clock did not advance %d days in %d Continues" % [WINDOW_DAYS, MAX_STEPS])
			season.close()
			return

	var end: String = season.save.current_date()
	var advanced := FixtureCalendar.days_from(end) - FixtureCalendar.days_from(start)
	if advanced < WINDOW_DAYS:
		_fail("the clock moved %d calendar days, not %d" % [advanced, WINDOW_DAYS])
		season.close()
		return

	var late_total := 0
	var census: Array = []
	for cid in selected:
		var due := 0
		for fx in season.record.fixtures.all(-1, str(cid)):
			var kickoff := str(fx["kickoff"])
			if kickoff < start or kickoff >= end:
				continue
			due += 1
			if str(fx["status"]) != "played":
				printerr("SMOKE2 unplayed %s %s %s v %s" % [
					cid, kickoff, fx["home_club_id"], fx["away_club_id"]])
				late_total += 1
		if due == 0:
			_fail("%s had no fixture due in the window — the scenario proves nothing" % cid)
			season.close()
			return
		census.append("%s=%d" % [cid, due])
	if late_total > 0:
		_fail("%d due match(es) went unplayed across %d leagues" % [late_total, selected.size()])
		season.close()
		return

	var state := season.state()
	var tables: Dictionary = state.get("tables", {})
	var short_form := 0
	for cid in selected:
		for row in tables.get(str(cid), []):
			var marks: Array = (row as Dictionary).get("form", [])
			var expected: int = mini(int(row.get("played", 0)), LeagueFormGuide.LAST)
			if marks.size() != expected:
				short_form += 1
	if short_form > 0:
		_fail("%d table row(s) read a form that is not their played count (max %d)" % [
			short_form, LeagueFormGuide.LAST])
		season.close()
		return

	var played := 0
	for cid in selected:
		played += season.record.fixtures.played(str(cid))
	var wall := float(Time.get_ticks_msec() - started) / 1000.0
	print("SMOKE2 OK leagues=%d start=%s end=%s days=%d steps=%d played=%d due=%s wall=%.1fs" % [
		selected.size(), start, end, advanced, steps, played,
		",".join(PackedStringArray(census)), wall])
	season.close()
	_clean()
	quit(0)

## True once the window can be judged: the clock is at least WINDOW_DAYS past day
## one, and every selected league has played (a league kicking off later than the
## rest would otherwise make its own assertion vacuous).
func _window_closed(season: LeagueSeason, selected: Array, start: String) -> bool:
	var days := FixtureCalendar.days_from(season.save.current_date()) \
		- FixtureCalendar.days_from(start)
	if days < WINDOW_DAYS:
		return false
	for cid in selected:
		if season.record.fixtures.played(str(cid)) == 0:
			return false
	return true

## True when the leg has spent its wall allotment; prints and returns so the
## caller can stop before the job timeout cuts the message off.
func _wall_exceeded() -> bool:
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	if elapsed <= WALL_BUDGET_SEC:
		return false
	_fail("the 21-day window did not close in %.0fs" % elapsed)
	return true

## Report a failed leg and leave with a non-zero code — the tree never stops on
## its own, so every failure path must quit here.
func _fail(reason: String) -> void:
	if failed:
		return
	failed = true
	printerr("SMOKE2 FAIL " + reason)
	_clean()
	quit(1)

func _clean() -> void:
	LeagueSaveBoot.close()
	PLDatabase.reset()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	for folder in [save_dir, cache_dir]:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
