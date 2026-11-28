class_name HighlightDirector
extends RefCounted


const SNAPSHOT_EVERY := 0.45

const RING := 40

const CAPTURE_WINDOW := 12.0

const MIN_CAPTURE_FRAMES := 4

const LEAD := 6.5

const TAIL := 1.5

var host = null
var history: Array = []
var hist_timer := 0.0

var shown: Dictionary = {}

var pending: Dictionary = {}
var pending_until := -1.0

func _init(owner) -> void:
	host = owner


func restart() -> void:
	history.clear()
	shown.clear()
	pending = {}
	pending_until = -1.0
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
	if not pending.is_empty():
		open_pending()


func waiting() -> bool:
	return not pending.is_empty()


func on_event(e: Dictionary) -> void:
	var kind: String = e.get("type", "")
	var key := "%d|%s|%d" % [int(float(e.get("clock", 0.0)) * 60.0), kind, int(e.get("player_id", -1))]
	if kind == "goal" and not shown.has(key):
		capture(e)
	if not opens_replay(kind):
		return
	if shown.has(key):
		return
	shown[key] = true
	if host.in_highlight or host.replay != null:
		return
	var trigger := float(e.get("clock", host.engine.clock))
	var until := trigger + TAIL
	if pending.is_empty():
		pending = e
		pending_until = until
	elif kind == "goal":
		pending = e
		pending_until = maxf(pending_until, until)


func opens_replay(kind: String) -> bool:
	if host.mode == "goals":
		return kind == "goal"
	if host.mode != "highlights":
		return false
	return kind in ["shot", "goal", "penalty", "corner", "card"]


func open_pending(force: bool = false) -> bool:
	var engine = host.engine
	if engine == null:
		return false
	if not force and float(engine.clock) < pending_until:
		return false
	var e := pending
	pending = {}
	pending_until = -1.0
	var clock := float(engine.clock)
	var from := float(e.get("clock", clock)) - LEAD
	var window: Array = []
	for snap in history:
		var at := float(snap["clock"])
		if at >= from and at <= clock + 0.01:
			window.append(snap)
	if window.size() < MIN_CAPTURE_FRAMES:
		return false
	var pack := GoalHighlight.from_snapshots(window, meta(e, engine))
	if not host.open_live_replay(pack):
		return false
	host.batch_abort = true
	return true


func flush() -> bool:
	if pending.is_empty():
		return false
	if str(host.engine.phase) in ["half_time", "et_break"]:
		return open_pending(true)
	return false


func meta(e: Dictionary, engine: MatchEngine) -> Dictionary:
	var goal: Dictionary = engine.last_goal
	var scorer = engine.by_id.get(int(e.get("player_id", -1)), null)
	var team := clampi(int(e.get("team", 0)), 0, 1)
	var season := LeagueSeason.active
	return {
		"seed": engine.seed_value,
		"fixture_id": season.watching_fixture if season != null else "",
		"home": str(engine.teams[0]["id"]), "away": str(engine.teams[1]["id"]),
		"goal_index": 0, "minute": int(e.get("minute", 0)),
		"club_id": str(engine.teams[team]["id"]),
		"scorer_id": str(scorer.key) if scorer != null else "",
		"scorer_name": str(goal.get("scorer", e.get("player", ""))),
		"assist_id": str(goal.get("assist_key", "")),
		"assist_name": str(goal.get("assist", "")),
		"commentary": str(e.get("text", "")),
		"score_after": [int(engine.score[0]), int(engine.score[1])],
	}


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
	season.capture_goal(GoalHighlight.from_snapshots(window, meta(e, engine)))
