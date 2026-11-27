class_name HighlightDirector
extends RefCounted


const SNAPSHOT_EVERY := 0.45

const RING := 40

const CAPTURE_WINDOW := 12.0

const MIN_CAPTURE_FRAMES := 4

var host = null
var history: Array = []
var hist_timer := 0.0

var shown: Dictionary = {}

func _init(owner) -> void:
	host = owner


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


func sample() -> void:
	hist_timer += 1.0 / 60.0
	if hist_timer >= SNAPSHOT_EVERY:
		hist_timer = 0.0
		snapshot()


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


func on_event(e: Dictionary) -> void:
	var kind: String = e.get("type", "")
	var key := "%d|%s|%d" % [int(float(e.get("clock", 0.0)) * 60.0), kind, int(e.get("player_id", -1))]


	if kind == "goal" and not shown.has(key):
		capture(e)
	if not extends_window(kind):
		return
	if shown.has(key):
		return
	if host.in_highlight:

		host.highlight_until = maxf(host.highlight_until, host.engine.clock + (5.0 if kind == "goal" else 3.0))
		return
	if not opens_replay(kind):
		return
	shown[key] = true
	if rewind(host.engine.clock):
		host.in_highlight = true
		host.fast_mode = false
		host.highlight_until = host.engine.clock + 12.0
		host.replay_banner = 2.2
		if kind in ["shot", "penalty", "corner"]:
			host.accumulator = 0.0


func extends_window(kind: String) -> bool:
	if host.mode == "goals":
		return kind == "goal"
	if host.mode != "highlights":
		return false
	return kind in ["shot", "goal", "penalty", "penalty_taken", "card", "corner"]


func opens_replay(kind: String) -> bool:
	if host.mode == "goals":
		return kind == "goal"
	if host.mode != "highlights":
		return false
	return kind in ["shot", "goal", "penalty", "corner", "card"]


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
