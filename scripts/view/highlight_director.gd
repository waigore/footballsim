class_name HighlightDirector
extends RefCounted

## The broadcast ring: engine snapshots, the rewind that turns a shot into a
## live replay, and the goal captures a watched fixture stores for its report.
##
## Split out of the play scene so the scene keeps its size budget and so the
## capture path lives next to the ring it reads. The host owns the clock and the
## flags this class drives; every decision about *what* to replay is here.
##
## Snapshots are full engine states — they only live for the length of a match.
## What a watched fixture stores afterwards is not a snapshot but a playback
## pack (see `GoalHighlight`), cut from the ring when a goal lands.

## Seconds of match time between snapshots: ~18 seconds of picture in the ring.
const SNAPSHOT_EVERY := 0.45
## Ring length. Forty snapshots is every highlight window the viewer can rewind.
const RING := 40
## Match seconds of picture kept for one stored goal clip.
const CAPTURE_WINDOW := 12.0
## A capture needs enough frames to show a build-up, not just the net bulge.
const MIN_CAPTURE_FRAMES := 4

var host = null
var history: Array = []
var hist_timer := 0.0
## Triggers already replayed, so one shot never rewinds twice.
var shown: Dictionary = {}

func _init(owner) -> void:
	host = owner

## Start a fresh match: empty ring, one snapshot of kick-off.
func restart() -> void:
	history.clear()
	shown.clear()
	hist_timer = 0.0
	snapshot()

func snapshot() -> void:
	if host.engine == null:
		return
	history.append(host.engine.to_dict())
	if history.size() > RING:
		history.pop_front()

## One sim tick has run: feed the ring at its fixed cadence.
func sample() -> void:
	hist_timer += 1.0 / 60.0
	if hist_timer >= SNAPSHOT_EVERY:
		hist_timer = 0.0
		snapshot()

## Rewind the live match to a window before `trigger_clock`. The engine state is
## restored in place, so the viewer carries on from the replay's end.
func rewind(trigger_clock: float) -> bool:
	if history.is_empty():
		return false
	var target := trigger_clock - 7.0
	var best: Dictionary = history[0]
	for s in history:
		if float(s["clock"]) <= target:
			best = s
		else:
			break
	if float(best["clock"]) > trigger_clock - 1.0:
		best = history[0]
	var trimmed := []
	for s2 in history:
		if float(s2["clock"]) <= float(best["clock"]) + 0.01:
			trimmed.append(s2)
	history = trimmed
	host.engine.from_dict(best)
	host.actors.ball_trail.clear()
	host.batch_abort = true
	return true

## Every engine event lands here. Capture first — the ring still holds the
## build-up the report clip needs — then decide whether to replay it live.
func on_event(e: Dictionary) -> void:
	var kind: String = e.get("type", "")
	if kind == "goal":
		capture(e)
	if host.mode != "highlights":
		return
	var key := "%d|%s|%d" % [int(float(e.get("clock", 0.0)) * 60.0), kind, int(e.get("player_id", -1))]
	if shown.has(key):
		return
	var important: bool = kind in ["shot", "goal", "penalty", "penalty_taken", "card", "corner"]
	if not important:
		return
	if host.in_highlight:
		# extend the live window around goals and late chances
		host.highlight_until = maxf(host.highlight_until, host.engine.clock + (5.0 if kind == "goal" else 3.0))
		return
	if kind in ["shot", "penalty", "corner", "goal", "card"]:
		shown[key] = true
		if rewind(host.engine.clock):
			host.in_highlight = true
			host.fast_mode = false
			host.highlight_until = host.engine.clock + 12.0
			host.replay_banner = 2.2
			if kind in ["shot", "penalty", "corner"]:
				host.accumulator = 0.0

# ---------------------------------------------------------------- capture ---

## A goal landed while a league fixture was being watched: cut the ring's
## window into a playback pack and hand it to the season, which stores it when
## the match result comes back.
func capture(e: Dictionary) -> void:
	var season := LeagueSeason.active
	if season == null or season.watching_fixture == "":
		return
	var engine = host.engine
	if engine == null:
		return
	var clock := float(e.get("clock", engine.clock))
	var window: Array = []
	for snap in history:
		var at := float(snap["clock"])
		if at >= clock - CAPTURE_WINDOW and at <= clock + 0.01:
			window.append(snap)
	if window.size() < MIN_CAPTURE_FRAMES:
		return
	var scorer = engine.by_id.get(int(e.get("player_id", -1)), null)
	var team := int(e.get("team", 0))
	var goal: Dictionary = engine.last_goal
	var pack := GoalHighlight.from_snapshots(window, {
		"seed": engine.seed_value, "fixture_id": season.watching_fixture,
		"home": str(engine.teams[0]["id"]), "away": str(engine.teams[1]["id"]),
		"goal_index": 0, "minute": int(e.get("minute", 0)),
		"club_id": str(engine.teams[team]["id"]),
		"scorer_id": str(scorer.key) if scorer != null else "",
		"scorer_name": str(goal.get("scorer", e.get("player", ""))),
		"assist_id": "", "assist_name": str(goal.get("assist", "")),
		"commentary": str(e.get("text", "")),
		"score_after": [int(engine.score[0]), int(engine.score[1])],
	})
	season.capture_goal(pack)
