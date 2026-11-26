class_name MatchRestarts
extends RefCounted

## Dead-ball judgement: how long a restart is held and when play comes back.
##
## The taker only kicks once most of his side is roughly on its slot; how long
## he is willing to hold play up depends on how well he reads the game and on
## whether the clock is on his side. Pure reads over live engine state (state,
## clock, score, live style), so the engine can hold the decision without the
## match loop growing a branch per rule.

## A player counts as set this close to his slot, and only once he has stopped
## sprinting: still moving fast means he is not ready for the ball.
const READY_RADIUS := 8.5   # metres from a target that counts as set
const SETTLED_SPEED := 3.0  # m/s; still sprinting = not set
const WAIT_STEP := 0.3      # seconds per re-read while play is held up

## The taker's picture of his side: x = share of nearby outfield team-mates
## roughly on their slot and no longer sprinting, y = their mean distance from
## it. Players far from the restart are not part of this picture — nobody holds
## a throw-in up for a centre-back 50m away.
static func picture(eng, team: int, taker, pos: Vector2) -> Vector2:
	var set_count := 0
	var outfield := 0
	var err_sum := 0.0
	for q in eng.players:
		if q.team != team or q.sent_off or q.is_gk:
			continue
		if taker != null and q.id == taker.id:
			continue
		if q.pos.distance_to(pos) > 42.0:
			continue
		var err: float = q.pos.distance_to(q.target)
		err_sum += err
		outfield += 1
		if err <= READY_RADIUS and q.vel.length() <= SETTLED_SPEED:
			set_count += 1
	if outfield == 0:
		return Vector2(1.0, 0.0)
	return Vector2(float(set_count) / float(outfield), err_sum / float(outfield))

## How well this player reads a dead-ball picture (0..1, home composure included).
static func read(eng, taker) -> float:
	if taker == null:
		return 0.5
	var pas: float = float(taker.attr.get("pas", 60)) / 100.0
	var ovr: float = float(taker.attr.get("ovr", 60)) / 100.0
	return clampf((pas * 0.6 + ovr * 0.4) * eng.home_factor(taker), 0.0, 1.0)

## Share of his side the taker wants set before he plays it: a better reader
## waits for a cleaner picture.
static func ready_needed(eng, taker) -> float:
	return 0.45 + read(eng, taker) * 0.35

## Seconds of extra waiting the taker will tolerate. A good reader and a side
## protecting a lead will hold play up; a chase or a quick restart won't.
static func patience(eng, taker, kind: String, team: int) -> float:
	if taker == null:
		return 0.0
	var want: float = 0.8 + read(eng, taker) * 2.8
	match kind:
		"throw_in":
			want *= 0.35
		"goal_kick":
			want *= 0.7
		"corner":
			want *= 1.2
	if eng.clock > 4200.0:
		var margin: int = eng.score[team] - eng.score[1 - team]
		if margin < 0:
			want *= 0.5
		elif margin > 0:
			want *= 1.6 + float(eng.style_of(team)["time_wasting"]) * 0.9
	var limit := 0.0
	match eng.half:
		1:
			limit = 2700.0 + float(eng.added[0])
		2:
			limit = 5400.0 + float(eng.added[1])
		3:
			limit = 6300.0 + float(eng.added[2])
		_:
			limit = 7200.0 + float(eng.added[3])
	return clampf(minf(want, limit - eng.clock - 1.5), 0.0, 4.5)

## Hold the ball up or take it now, given how set the side already looks.
static func should_wait(eng, restart: Dictionary, ready: float, taker) -> bool:
	var kind: String = str(restart.get("type", ""))
	if kind == "kickoff" or kind == "penalty":
		return false
	if taker == null or taker.sent_off:
		return false
	if float(restart.get("wait", 0.0)) >= float(restart.get("patience", 0.0)):
		return false
	if ready >= ready_needed(eng, taker):
		return false
	# A picture that has stopped improving is as good as it is going to get:
	# the taker gets on with it rather than burning his whole patience.
	if float(restart.get("still", 0.0)) >= 1.2:
		return false
	return true

## Track how long the picture has gone without improving, so the wait ends when
## the side has settled even if it never hits the ideal shape.
static func note_picture(restart: Dictionary, pic: Vector2) -> void:
	restart["ready"] = pic.x
	var err: float = pic.y
	var shrinking: bool = err < float(restart.get("err", 999.0)) - 0.08
	if pic.x > float(restart.get("best_ready", 0.0)) + 0.01 or shrinking:
		restart["best_ready"] = maxf(float(restart.get("best_ready", 0.0)), pic.x)
		restart["still"] = 0.0
	else:
		restart["still"] = float(restart.get("still", 0.0)) + WAIT_STEP
	restart["err"] = err
