class_name MatchAI
extends RefCounted


var e = null
var pq = null
var on_ball: MatchAIPlanning = null
var shapes: MatchAIShapes = null
var shape_timer = 0.0
var mark_timer = 0.0
var gk_react_at = [-1.0, -1.0]
var kickoff_lock = 0.0

func _init(engine) -> void:
	e = engine
	pq = PitchQueries.new(engine)
	on_ball = MatchAIPlanning.new(self)
	shapes = MatchAIShapes.new(self)

func on_kickoff() -> void:
	on_ball.reset_state()
	gk_react_at = [-1.0, -1.0]
	kickoff_lock = 1.2

func on_restore() -> void:
	on_ball.reset_state()

func on_shot(shooter) -> void:
	var t: int = 1 - shooter.team
	var gk = e._gk_of(t)
	if gk != null:
		gk_react_at[t] = e.clock + Attrs.gk_reaction(gk) * e.rng.randf_range(0.75, 1.35)

func update(dt: float) -> void:
	if kickoff_lock > 0.0:
		kickoff_lock -= dt
	shape_timer -= dt
	mark_timer -= dt
	if mark_timer <= 0.0:
		_assign_marks()
		mark_timer = 0.45
	if shape_timer <= 0.0:
		_update_shapes()
		shape_timer = 0.11
	var owner = e.ball_owner()
	if owner != null:
		on_ball.update(dt)

func update_restart(dt: float, restart: Dictionary) -> void:
	if restart.get("type", "") == "penalty":
		return
	shape_timer -= dt
	if shape_timer <= 0.0:
		_update_shapes()
		shape_timer = 0.15


func _update_shapes() -> void:
	shapes.update()


func _assign_marks() -> void:
	shapes.assign_marks()
