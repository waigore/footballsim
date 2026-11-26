class_name GoalVignette
extends RefCounted

## AUTO report clips: a bounded physics simulation of one chance.
##
## Bodies steer with an acceleration and a top speed; the ball is dribbled,
## passed and struck with the engine's own gravity, drag, bounce and swerve; the
## keeper dives on a seeded reaction delay. Only the decisions come from the
## seed — the run, the pass, the aim, the corner — so no two goals share a shape,
## and the chance always finishes with the report's own scorer and assist: the
## strike is aimed at the goal mouth and solved against the very flight it is
## then flown through, and a planned strike is never intercepted (the engine's
## `planned_goal` rule). World space is the attacking frame; an away goal is
## mirrored once at sampling, like the engine's own direction switch.
##
## This file is the chance's state and its tick order. The cast and their
## steering live in `GoalVignetteCast`, where each body is heading in
## `GoalVignetteAI`, the ball's own physics in `GoalVignetteFlight`, and the spot
## kick layout in `GoalVignettePenalty`.
const L := 105.0
const W := 68.0
const CENTRE := W * 0.5
const POST := 3.66
const BAR := 2.44
const LENGTH := 10.0
## Two sim ticks per stored pose, so a pack is exactly twelve poses a second.
const DT := 1.0 / 24.0
## Sub-steps of the free ball inside one tick; the shot solver uses the same.
const SUB := 16
const GRAVITY := 9.81
const NEAR := 1.7

class Sim:
	var rng := RandomNumberGenerator.new()
	var bodies: Array = []
	var carrier := 0
	var shooter := 0
	var keeper := 0
	var mirror := false
	var ball := Vector3.ZERO
	var bvel := Vector3.ZERO
	var spin := 0.0
	var owner := 0
	var pass_at := 2.3
	var strike_at := 5.0
	var carry_to := Vector2.ZERO
	var meet := Vector2.ZERO
	var strike_from := Vector2.ZERO
	var goal_at := 6.0
	var dive_y := 0.0
	var react_at := 99.0
	var shot := false
	var scored := false
	var score_before: Array = [0, 0]
	var score_after: Array = [0, 0]
	var minute := 1
	var t := 0.0
	var frames: Array = []

	func _init(sides: Dictionary, goal: Dictionary, count: int, seed: int,
			scoring_home: bool) -> void:
		rng.seed = seed
		mirror = not scoring_home
		minute = int(goal.get("minute", 1))
		var score: Array = goal.get("score_after", [0, 0])
		score_before = [int(score[0]), int(score[1])]
		score_after = score_before.duplicate()
		var side := 0 if scoring_home else 1
		score_before[side] = maxi(int(score_before[side]) - 1, 0)
		GoalVignetteCast.dress(self, sides, goal, scoring_home)
		if bool(goal.get("penalty", false)):
			GoalVignettePenalty.lay_out(self, shooter, keeper, rng)

	## Play the chance out: one tick of physics, then every other tick a pose.
	func run() -> void:
		for i in range(int(round(LENGTH / DT)) + 1):
			if i > 0:
				_tick(DT)
			if i % 2 == 0:
				_sample()

	func _tick(dt: float) -> void:
		t += dt
		GoalVignetteAI.decide(self)
		for b in bodies:
			(b as GoalVignetteCast.Body).steer(dt)
		if not shot:
			if owner == carrier and t >= pass_at:
				GoalVignetteFlight.through_ball(self)
			var reach := t >= pass_at and ball.z < 1.7 and \
				Vector2(ball.x, ball.y).distance_to(bodies[shooter].pos) < NEAR
			if owner < 0 and reach:
				owner = shooter
			# The strike is a decision with a deadline, never a hope: a finisher
			# takes the chance he has and never lets the ball run into the net.
			if not shot and (ball.x > L - 8.0 or t >= strike_at + 0.5 or \
					(owner == shooter and t >= strike_at)):
				GoalVignetteFlight.strike(self)
		if owner >= 0:
			GoalVignetteFlight.carry(self, dt)
		else:
			GoalVignetteFlight.step(self, dt)

	func _sample() -> void:
		var flat := PackedFloat32Array()
		flat.resize(bodies.size() * 2)
		for i in range(bodies.size()):
			var p: Vector2 = bodies[i].pos
			flat[i * 2] = snappedf(p.x if not mirror else L - p.x, 0.01)
			flat[i * 2 + 1] = snappedf(p.y, 0.01)
		var shown: Array = score_after if scored else score_before
		var bx := L - ball.x if mirror else ball.x
		frames.append({
			"t": snappedf(t, 0.01),
			# The clip's clock meets the report's minute exactly at the finish.
			"c": snappedf(float(minute) * 60.0 - goal_at + t, 0.01),
			"s": [int(shown[0]), int(shown[1])],
			"g": 1 if scored else 0,
			"b": [snappedf(bx, 0.01), snappedf(ball.y, 0.01), snappedf(ball.z, 0.01)],
			"p": flat,
		})

## The pack's poses for one goal: home XI first, then the away XI, in key order.
static func build(goal: Dictionary, sides: Dictionary, seed: int) -> Dictionary:
	var home := str(goal.get("home", ""))
	var keys: Array = []
	for p in sides.get("home", []):
		keys.append(str(p.get("id", "")))
	for p in sides.get("away", []):
		keys.append(str(p.get("id", "")))
	var sim := Sim.new(sides, goal, keys.size(), seed, str(goal.get("club_id", home)) == home)
	sim.run()
	return {"keys": keys, "frames": sim.frames}

## The mirror across the halfway line: the defending shape in the attacking frame.
static func mirror(p: Vector2) -> Vector2:
	return Vector2(L - p.x, p.y)
