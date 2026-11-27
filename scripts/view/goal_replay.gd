class_name GoalReplay
extends RefCounted


const RATE := 1.0

var host = null
var pack: Dictionary = {}
var frames: Array = []
var keys: Array = []
var engine = null
var bound: Dictionary = {}
var t := 0.0
var length := 0.0
var goal_shown := false
var on_done := Callable()


static func open(host_in, clip: Dictionary, done := Callable()) -> GoalReplay:
	if clip.is_empty() or host_in == null:
		return null
	var replay := GoalReplay.new()
	replay.host = host_in
	replay.pack = clip
	replay.frames = clip.get("frames", [])
	replay.keys = clip.get("keys", [])
	replay.on_done = done
	if replay.frames.size() < 2:
		return null
	replay.length = float(replay.frames[replay.frames.size() - 1].get("t", 0.0))
	host_in.home_id = str(clip.get("home", host_in.home_id))
	host_in.away_id = str(clip.get("away", host_in.away_id))
	host_in.new_match(int(clip.get("seed", host_in.seeded)))
	host_in.result_recorded = true
	host_in.paused = false
	host_in.mode = "highlights"
	host_in.fast_mode = false
	host_in.replay_banner = 9.9
	replay.engine = host_in.engine
	for player in replay.engine.players:
		replay.bound[str(player.key)] = player
	replay.apply(true)
	return replay


func step(delta: float) -> bool:
	if host == null or engine == null:
		return true
	if not bool(host.paused):
		t += delta * maxf(float(host.speed), 0.25) * RATE
	apply(false)
	if t >= length:
		finish(true)
		return true
	return false


func finish(notify: bool = true) -> void:
	if host != null:
		host.replay_banner = 0.0
	var done := on_done
	on_done = Callable()
	engine = null
	if notify and done.is_valid():
		done.call()


func apply(first: bool) -> void:
	if engine == null:
		return
	var at := _frame_index(t)
	var a: Dictionary = frames[at]
	var b: Dictionary = frames[mini(at + 1, frames.size() - 1)]
	var span := maxf(float(b.get("t", 0.0)) - float(a.get("t", 0.0)), 0.001)
	var alpha := clampf((t - float(a.get("t", 0.0))) / span, 0.0, 1.0)
	var pose := GoalHighlight.blend(a, b, alpha)
	var flat: Array = pose.get("p", [])


	var dt := maxf(span, 0.001)
	for i in range(keys.size()):
		var player = bound.get(str(keys[i]), null)
		if player == null:
			continue
		var pos: Vector2 = player.pos
		if i * 2 + 1 < flat.size():
			pos = Vector2(float(flat[i * 2]), float(flat[i * 2 + 1]))
		var vel: Vector2 = (pos - player.pos) / dt
		player.pos = pos
		player.target = pos
		player.vel = Vector2.ZERO if first else vel
		if vel.length() > 0.35:
			player.facing = vel.normalized()
		player.celebrate = 1.0 if int(a.get("g", 0)) == 1 else 0.0
	var ball: Array = pose.get("b", [0.0, 0.0, 0.0])
	var bp := Vector2(float(ball[0]), float(ball[1]))
	engine.ball.vel = (bp - engine.ball.pos) / dt
	engine.ball.pos = bp
	engine.ball.z = float(ball[2])
	engine.ball.owner_id = -1
	engine.clock = float(a.get("c", engine.clock))
	engine.half = 1 if engine.clock < 2700.0 else 2
	engine.phase = "play"
	set_score(int(a["s"][0]) if a.has("s") else 0, int(a["s"][1]) if a.has("s") else 0)
	if first:
		host.actors.ball_trail.clear()
	if int(a.get("g", 0)) == 1 and not goal_shown:
		goal_shown = true
		_show_line(a)

	engine.referee.pos = engine.referee.pos.lerp(bp + Vector2(-9.0, 7.0), 0.12)
	engine.referee.facing = (bp - engine.referee.pos).normalized()

func set_score(home: int, away: int) -> void:
	engine.score = [home, away]
	engine.teams[0]["score"] = home
	engine.teams[1]["score"] = away


func _show_line(frame: Dictionary) -> void:
	var text := str(pack.get("commentary", ""))
	if text == "":
		text = "%s — %s" % [str(pack.get("scorer", "")), str(pack.get("minute", ""))]
	engine.events = [{
		"id": 1, "type": "goal", "text": text, "team": -1, "player": str(pack.get("scorer", "")),
		"player_id": -1, "minute": int(pack.get("minute", 0)), "clock": float(frame.get("c", 0.0)),
		"pos": Vector2.ZERO,
	}]


func _frame_index(at_seconds: float) -> int:
	var lo := 0
	var hi := frames.size() - 1
	while lo < hi:
		var mid := int((lo + hi + 1) / 2)
		if float(frames[mid].get("t", 0.0)) <= at_seconds:
			lo = mid
		else:
			hi = mid - 1
	return lo
