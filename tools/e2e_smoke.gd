extends SceneTree

## Headless e2e smoke: one sim-only Manchester derby played to full time.
##   godot --headless --path . --script res://tools/e2e_smoke.gd
##
## Proves the engine boots, plays both halves and ends with a score without
## any presentation layer (no pitch, HUD, team select or highlights). Exits 0
## once full time is reached, non-zero if the match never finishes inside the
## wall budget. Any scoreline passes, 0-0 included.

const HOME := "MUN"
const AWAY := "MCI"
const SEED := 1000
## CI gives the e2e-smoke job 4 minutes; the engine must never sit until then.
## A local M-series desktop finishes the match in ~100 s, so 210 s leaves the
## failure message room to print before the job timeout.
const WALL_BUDGET_SEC := 210.0
## Checking the wall clock every simulated half-minute keeps the tick loop hot.
const WALL_CHECK_EVERY := 1800

func _init() -> void:
	var started := Time.get_ticks_msec()
	var eng := MatchEngine.new(SEED, HOME, AWAY)
	eng.verbose = false
	eng.record_trails = false
	print("SMOKE kickoff %s v %s seed=%d" % [HOME, AWAY, SEED])
	var ticks := 0
	while eng.phase != "full_time":
		if eng.phase == "half_time":
			print("SMOKE half time %s %d-%d %s clock=%s" % [
				HOME, eng.score[0], eng.score[1], AWAY, eng.display_clock()])
			eng.begin_second_half()
		eng.tick()
		ticks += 1
		if ticks % WALL_CHECK_EVERY == 0:
			var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
			if elapsed > WALL_BUDGET_SEC:
				_fail("match did not reach full time in %.0fs (phase=%s clock=%s)" % [
					elapsed, eng.phase, eng.display_clock()])
				return
	if eng.half != 2:
		_fail("full time reached without playing the second half")
		return
	var elapsed_total := float(Time.get_ticks_msec() - started) / 1000.0
	print("SMOKE full time %s %d-%d %s clock=%s" % [
		HOME, eng.score[0], eng.score[1], AWAY, eng.display_clock()])
	# The whistle card lists the goals the scoreboard counted (DR-20261125-04):
	# the summary can never disagree with the result it summarises.
	if eng.goal_sheet.size() != eng.score[0] + eng.score[1]:
		_fail("the whistle sheet lists %d goals for a %d-%d score" % [
			eng.goal_sheet.size(), eng.score[0], eng.score[1]])
		return
	# One match names one competition (#209): this match has no league fixture
	# behind it, so the binding every surface reads is a friendly — no matchday,
	# no table, and never a borrowed league name.
	var billing := MatchBilling.new()
	billing.bind_fixture(HOME, {})
	if not billing.friendly or billing.matchday != 0 or billing.chrome_name() != MatchBilling.FRIENDLY:
		_fail("a fixture-less match is not billed as a friendly (%s, matchday %d)" % [
			billing.chrome_name(), billing.matchday])
		return

	print("SMOKE OK %s %d-%d %s seed=%d ticks=%d wall=%.1fs" % [
		HOME, eng.score[0], eng.score[1], AWAY, SEED, ticks, elapsed_total])
	quit(0)

func _fail(reason: String) -> void:
	printerr("SMOKE FAIL " + reason)
	quit(1)
