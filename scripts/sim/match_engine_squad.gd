extends "res://scripts/sim/match_engine_core.gd"


const XG_SCALE := 0.50


const XG_CONTEST_ELASTICITY := 0.13


const XG_HOME_EDGE := 0.0


const XG_ON_TARGET_BASE := 0.26


const PENALTY_BASE := 0.76


const PENALTY_PER_SHOOTING := 0.0018


var xg_form: Array = [1.0, 1.0]


func _shot_split(xg: float, save_chance: float) -> Array:
	var save: float = clampf(save_chance, 0.0, 1.0)
	var land: float = 1.0 - save
	var on_target: float = clampf(minf(XG_ON_TARGET_BASE + xg, xg / maxf(land, 0.0001)), 0.0, 0.92)
	var planned: float = clampf((xg - on_target * land) / maxf(save, 0.06), 0.0, on_target)
	return [planned, maxf(0.0, on_target - planned)]


func penalty_conversion(p: Player) -> float:
	return clampf(PENALTY_BASE + float(p.attr["sho"]) * PENALTY_PER_SHOOTING, 0.05, 0.95)


func style_of(t: int) -> Dictionary:
	return live_style[t]


func push_of(p) -> float:
	if manager == null:
		return Attrs.role_push(p.role)
	return Attrs.role_push(p.role) + manager.tactics_for(p.team).duty_offset(p.role)


func _calibrate_finishing() -> void:
	var h := str(teams[0]["id"])
	var a := str(teams[1]["id"])
	var terms := PoissonModel.exponent_terms(h, a)
	var attack: Vector2 = terms["attack"]
	var defence: Vector2 = terms["defence"]
	var ex := PoissonModel.side_exponents(h, a)
	var total: float = PoissonModel.HOME_XG + PoissonModel.AWAY_XG
	var open: float = (PoissonModel.HOME_XG * exp(ex.x) + PoissonModel.AWAY_XG * exp(ex.y)) / total
	var venue: float = exp(XG_HOME_EDGE)
	xg_form[0] = exp(XG_CONTEST_ELASTICITY * (attack.x + defence.x)) * venue * open
	xg_form[1] = exp(XG_CONTEST_ELASTICITY * (attack.y + defence.y)) / venue * open


func team_players(t: int) -> Array:
	if _team_cache_rev != _squad_rev:
		_team_cache[0].clear()
		_team_cache[1].clear()
		for q in players:
			if not q.sent_off:
				_team_cache[q.team].append(q)
		_team_cache_rev = _squad_rev
	return _team_cache[t]

func _touch_squad() -> void:
	_squad_rev += 1


func home_factor(p) -> float:
	if p.team == home_team:
		return 1.0 + home_advantage
	return 1.0 - home_advantage * 0.5


func kit_color(t: int) -> Color:
	var kit: Dictionary = teams[t].get("kit", {})
	if kit.has("shirt"):
		return kit["shirt"]
	return teams[t]["data"]["color"]

func _blank_stats() -> Dictionary:
	return {
		"possession": 0.0, "shots": 0, "on_target": 0, "goals": 0, "xg": 0.0,
		"passes": 0, "passes_ok": 0, "tackles": 0, "fouls": 0, "corners": 0,
		"offsides": 0, "saves": 0, "yellow": 0, "red": 0, "distance": 0.0,
		"big_chances": 0, "woodwork": 0, "handballs": 0, "injuries": 0,
		"interceptions": 0,
	}


func _build_squads() -> void:
	players.clear()
	by_id.clear()
	for t in range(2):
		var data: Dictionary = teams[t]["data"]
		var i = 0
		for pd in data["starters"]:
			var p = _make_player(pd, t, t * 100 + i)
			players.append(p)
			by_id[p.id] = p
			i += 1
	_touch_squad()

func _make_player(pd: Dictionary, t: int, id_in: int) -> Player:
	var p = Player.new()
	p.id = id_in
	p.key = str(pd.get("id", ""))
	p.team = t
	p.name = pd["name"]
	p.number = pd["number"]
	p.role = pd["role"]
	p.pos_label = pd["pos"]
	p.attr = {
		"ovr": pd["ovr"], "pac": pd["pac"], "sho": pd["sho"], "pas": pd["pas"],
		"dri": pd["dri"], "def": pd["def"], "phy": pd["phy"], "height": pd.get("height", 180),
	}
	p.gk = pd.get("gk", {"div": 30, "han": 30, "kic": 40, "ref": 30, "spd": 60})
	p.is_gk = p.role == "GK"
	p.base = TeamData.formation_slot(teams[t]["data"], p.role)
	p.target = Vector2.ZERO
	_fill_attr_cache(p)
	return p


func ball_owner():
	if ball.owner_id < 0:
		return null
	return by_id.get(ball.owner_id, null)

func teammates_of(p) -> Array:
	var out := []
	for q in team_players(p.team):
		if q.id != p.id:
			out.append(q)
	return out

func opponents_of(p) -> Array:
	var out := []
	for q in team_players(1 - p.team):
		out.append(q)
	return out

func nearest_opponent(pos: Vector2, t: int):
	var best = null
	var bd = 1e9
	for q in players:
		if q.team == t or q.sent_off:
			continue
		var d = pos.distance_squared_to(q.pos)
		if d < bd:
			bd = d
			best = q
	return best

func nearest_opponent_dist(pos: Vector2, t: int) -> float:
	var q = nearest_opponent(pos, t)
	if q == null:
		return 99.0
	return pos.distance_to(q.pos)

func pressure_on(p) -> float:
	var pressure = 0.0
	for q in players:
		if q.team == p.team or q.sent_off:
			continue
		var d = p.pos.distance_to(q.pos)
		if d < 6.0:
			pressure += (1.0 - d / 6.0)
	return clampf(pressure, 0.0, 2.5)
