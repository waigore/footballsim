extends "res://scripts/sim/match_engine/match_engine_squad.gd"


func attacking_dir(t: int) -> int:
	return teams[t]["dir"]

func own_goal_pos(t: int) -> Vector2:
	return Vector2(0.0 if teams[t]["dir"] == 1 else L, W * 0.5)

func target_goal_pos(t: int) -> Vector2:
	return Vector2(L if teams[t]["dir"] == 1 else 0.0, W * 0.5)


func line_save_chance(gk: Player, defending_team: int, cross_y: float, speed: float) -> float:
	if gk == null or gk.sent_off:
		return 0.0
	var gpos := Vector2(own_goal_pos(defending_team).x, cross_y)
	var gd: float = gk.pos.distance_to(gpos)
	var reach: float = AttrKeeper.dive_reach(gk) + 1.05
	if gd >= reach + 3.2:
		return 0.0
	var save_p: float = 0.91 + (reach - gd) * 0.06 + (AttrKeeper.handling(gk) - 0.8) * 0.25 - speed * 0.003
	return clampf(save_p, 0.18, 0.985)

func to_world(t: int, norm: Vector2) -> Vector2:
	if teams[t]["dir"] == 1:
		return Vector2(norm.x * L, norm.y * W)
	return Vector2((1.0 - norm.x) * L, norm.y * W)

func to_norm(t: int, world: Vector2) -> Vector2:
	if teams[t]["dir"] == 1:
		return Vector2(world.x / L, world.y / W)
	return Vector2(1.0 - world.x / L, world.y / W)

func attacking_x(t: int, world: Vector2) -> float:
	return world.x if teams[t]["dir"] == 1 else L - world.x

func in_penalty_box(pos: Vector2, defending_team: int) -> bool:
	if teams[defending_team]["dir"] == 1:
		return pos.x <= BOX_D and absf(pos.y - W * 0.5) <= BOX_W * 0.5
	return pos.x >= L - BOX_D and absf(pos.y - W * 0.5) <= BOX_W * 0.5

func is_attacking_third(t: int, pos: Vector2) -> bool:
	var ax = attacking_x(t, pos)
	return ax > L * 0.66

func opponent_goal_angle(p) -> float:

	var g = target_goal_pos(p.team)
	var to_goal = g - p.pos
	if to_goal.length() < 0.001:
		return 1.0
	var half_w = GOAL_W * 0.5
	var dx = absf(g.x - p.pos.x)
	var angles = absf(atan2(half_w, maxf(dx, 0.4)))
	return clampf(angles / 0.9, 0.0, 1.0)


var _offside_xs := [[], []]
var _offside_xs_tick := [-1, -1]
var _offside_xs_rev := [-1, -1]

func offside_xs(t: int) -> Array:
	if _offside_xs_tick[t] != sim_tick or _offside_xs_rev[t] != _squad_rev:
		var xs: Array = _offside_xs[t]
		xs.clear()
		for q in players:
			if q.team == t or q.sent_off:
				continue
			xs.append(attacking_x(t, q.pos))
		xs.sort()
		xs.reverse()
		_offside_xs_tick[t] = sim_tick
		_offside_xs_rev[t] = _squad_rev
	return _offside_xs[t]
