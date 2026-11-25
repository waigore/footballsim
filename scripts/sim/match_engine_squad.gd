extends "res://scripts/sim/match_engine_core.gd"

## The painted squad and the reads every other layer takes off it: who is on
## the pitch per side, the team-revision cache that keeps those lookups off the
## per-tick path, the closes-opponent and pressure probes the AI and duels ask
## for, the squad build itself, and the finishing multiplier the squads' ratings
## price into every shot. One layer up from the bare core state so core owns
## only the shape (match scalars, Player/Ball/Official), and every module that
## needs a body or a side read reads it here.

## Finishing calibration against the Poisson model: a shot converts with
## p = FINISH_EFFICIENCY · xG, so a match's goals track its expected goals (the
## model's λ) instead of the old keeper-steer hack.
const FINISH_EFFICIENCY := 1.0
## Positional xG is calibrated down to real-football levels: the engine creates
## more chances than a real side, so each one is worth less. Fitted to the
## tier-2 census against the PL-envelope λ (wiki poisson-model, DR-20261126-02).
const XG_SCALE := 0.335
## A shot is also worth more when the defence facing it is weak and when the
## side taking it is strong — the same combined rating gradient the model puts
## into λ, read from one source (`PoissonModel.exponent_terms`). The engine's
## positional xG knows only distance, angle and aim, so without this a good back
## line and keeper move *where* chances happen but never how good a chance is.
## Elasticity is per 10 rating points of that derived gap; it sits below the
## model's 0.98 because the engine's chance creation already carries part of the
## gradient. Fitted to the tier-2 census (wiki poisson-model, DR-20261126-02).
const XG_CONTEST_ELASTICITY := 0.78
## Venue premium in chance quality, in log terms. It is zero because the home
## side already gets its edge in *creation* — it holds the ball higher up and
## shoots from better positions — so pricing the venue again in the finishing
## multiplier double-counted it and left the even anchor's home side above λ;
## the model keeps its own edge in HOME_XG / AWAY_XG.
const XG_HOME_EDGE := 0.0
## Per-side shot-contest multiplier, exp(XG_CONTEST_ELASTICITY · the side's
## share of the model's rating gradient ± XG_HOME_EDGE). Rebuilt by
## `_calibrate_finishing`.
var xg_form: Array = [1.0, 1.0]

## Tactics bridge -------------------------------------------------------------

## MatchAI reads the side's effective FM style from here instead of the static
## club style, so a manager change moves the whole pitch.
func style_of(t: int) -> Dictionary:
	return live_style[t]

## Role push after the manager's duty instruction (attack runs higher, defend
## holds deeper) is applied on top of the squad role.
func push_of(p) -> float:
	if manager == null:
		return Attrs.role_push(p.role)
	return Attrs.role_push(p.role) + manager.tactics_for(p.team).duty_offset(p.role)

## Reads each side's share of the model's rating gradient once per match, so the
## same shot is a better chance for a strong attack against a weak defence than
## for a weak one against a strong defence. Cheap: one squad reading per side,
## then a per-shot multiply.
func _calibrate_finishing() -> void:
	var terms := PoissonModel.exponent_terms(str(teams[0]["id"]), str(teams[1]["id"]))
	var attack: Vector2 = terms["attack"]
	var defence: Vector2 = terms["defence"]
	var venue: float = exp(XG_HOME_EDGE)
	xg_form[0] = exp(XG_CONTEST_ELASTICITY * (attack.x + defence.x)) * venue
	xg_form[1] = exp(XG_CONTEST_ELASTICITY * (attack.y + defence.y)) / venue

## Squad cache ----------------------------------------------------------------

## Active (on-pitch) players of one side, cached per squad revision.
## Callers must treat the returned array as read-only.
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

## Contract answers ------------------------------------------------------------

## Home advantage, expressed as a multiplier on technical execution.
## >1 means less error for the home side; <1 slightly more for the visitors.
func home_factor(p) -> float:
	if p.team == home_team:
		return 1.0 + home_advantage
	return 1.0 - home_advantage * 0.5

## Shirt colour the side is actually wearing in this match (kit selection may
## have sent the visitors to their change kit).
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

## Squad build ----------------------------------------------------------------

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

## Pitch caches ---------------------------------------------------------------

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
