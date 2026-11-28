class_name PoissonModel
extends RefCounted


const HOME_XG := 1.35
const AWAY_XG := 1.16


const ATTACK_ELASTICITY := 0.78
const DEFENCE_ELASTICITY := 0.78


const RHO := 0.10


const DEFAULT_CALIBRATION := {
	"home_xg": HOME_XG,
	"away_xg": AWAY_XG,
	"attack_elasticity": ATTACK_ELASTICITY,
	"defence_elasticity": DEFENCE_ELASTICITY,
	"rho": RHO,
}

const MAX_GOALS := 9

const WEATHER_MULT := {
	"clear": 1.0, "cloudy": 0.99, "rain": 0.94, "wind": 0.91, "snow": 0.84,
}

var home_id := ""
var away_id := ""
var weather := "clear"
var modifiers: Dictionary = {}

var cal: Dictionary = DEFAULT_CALIBRATION
var lambda_home := 0.0
var lambda_away := 0.0
var rng := RandomNumberGenerator.new()

static var _means_cache: Dictionary = {}

var _table: Array = []

func _init(seed: int, home: String, away: String, conditions: String = "clear", mods: Dictionary = {},
		cal_overrides: Dictionary = {}) -> void:
	rng.seed = seed
	home_id = home
	away_id = away
	weather = conditions
	modifiers = mods
	cal = calibration(cal_overrides)
	_recompute()


static func calibration(overrides: Dictionary = {}) -> Dictionary:
	var c: Dictionary = DEFAULT_CALIBRATION.duplicate()
	if not overrides.is_empty():
		c.merge(overrides, true)
	return c


static func team_strength(team: Dictionary) -> Dictionary:
	var attack_num := 0.0
	var attack_w := 0.0
	var mid_sum := 0.0
	var mid_n := 0
	var def_num := 0.0
	var def_w := 0.0
	for pd in team["starters"]:
		var role := str(pd["role"])
		var sho := float(pd["sho"])
		var pas := float(pd["pas"])
		var dri := float(pd["dri"])
		var dfn := float(pd["def"])
		var phy := float(pd["phy"])
		var ovr := float(pd["ovr"])
		if role == "GK":
			var gk: Dictionary = pd.get("gk", {})
			var keeper := float(gk.get("div", 30)) * 0.40 + float(gk.get("ref", 30)) * 0.35 + float(gk.get("han", 30)) * 0.25
			def_num += keeper * 1.6
			def_w += 1.6
			continue
		var push: float = Attrs.role_push(role)

		attack_num += (sho * 0.60 + dri * 0.30 + pas * 0.10) * (0.25 + push)
		attack_w += 0.25 + push
		if Attrs.is_mid(role):
			mid_sum += pas * 0.45 + dri * 0.30 + dfn * 0.25
			mid_n += 1
		if Attrs.is_defender(role) or role in ["RDM", "LDM", "CDM"]:
			def_num += (dfn * 0.70 + phy * 0.20 + ovr * 0.10) * (1.15 if Attrs.is_defender(role) else 0.65)
			def_w += 1.15 if Attrs.is_defender(role) else 0.65

	var midfield := mid_sum / float(mid_n) if mid_n > 0 else (attack_num / maxf(attack_w, 0.01) + def_num / maxf(def_w, 0.01)) * 0.5
	return {
		"attack": attack_num / maxf(attack_w, 0.01),
		"midfield": midfield,
		"defence": def_num / maxf(def_w, 0.01),
	}


static func effective(s: Dictionary) -> Vector2:
	return Vector2(
		float(s["attack"]) * 0.65 + float(s["midfield"]) * 0.35,
		float(s["defence"]) * 0.75 + float(s["midfield"]) * 0.25)


static func league_means(competition_id: String = "PL") -> Dictionary:


	var key := PLDatabase.current_path() + "|" + competition_id
	if _means_cache.has(key):
		return _means_cache[key]
	var att := 0.0
	var dfn := 0.0
	var n := 0
	for id in TeamData.team_ids(competition_id):
		var eff := effective(team_strength(TeamData.get_team(id)))
		att += eff.x
		dfn += eff.y
		n += 1
	var out := {"attack": att / maxf(float(n), 1.0), "defence": dfn / maxf(float(n), 1.0), "clubs": n}
	_means_cache[key] = out
	return out


static func competition_of(club_id: String) -> String:
	var comp := str(TeamData.get_team(club_id).get("competition_id", ""))
	return comp if comp != "" else "PL"


static func exponent_terms(home: String, away: String) -> Dictionary:
	var m := league_means(competition_of(home))
	var h := effective(team_strength(TeamData.get_team(home)))
	var a := effective(team_strength(TeamData.get_team(away)))
	return {
		"attack": Vector2(
			(h.x - float(m["attack"])) / 10.0, (a.x - float(m["attack"])) / 10.0),
		"defence": Vector2(
			(float(m["defence"]) - a.y) / 10.0, (float(m["defence"]) - h.y) / 10.0),
	}


static func defence_exponents(home: String, away: String) -> Vector2:
	return exponent_terms(home, away)["defence"]


static func side_exponents(home: String, away: String, cal: Dictionary = DEFAULT_CALIBRATION) -> Vector2:
	var terms := exponent_terms(home, away)
	var attack: Vector2 = terms["attack"]
	var defence: Vector2 = terms["defence"]
	var att_k := float(cal["attack_elasticity"])
	var def_k := float(cal["defence_elasticity"])
	return Vector2(
		att_k * attack.x + def_k * defence.x,
		att_k * attack.y + def_k * defence.y)

func _recompute() -> void:
	var ex := side_exponents(home_id, away_id, cal)
	var cond: float = float(WEATHER_MULT.get(weather, 1.0))
	var home_mod: float = float(modifiers.get("home", 1.0))
	var away_mod: float = float(modifiers.get("away", 1.0))
	var total_mod: float = float(modifiers.get("total", 1.0))
	lambda_home = float(cal["home_xg"]) * exp(ex.x) * cond * home_mod * total_mod
	lambda_away = float(cal["away_xg"]) * exp(ex.y) * cond * away_mod * total_mod
	lambda_home = clampf(lambda_home, 0.05, 6.5)
	lambda_away = clampf(lambda_away, 0.05, 6.5)
	_table.clear()


func expected_goals() -> Vector2:
	return Vector2(lambda_home, lambda_away)


func _poisson(k: int, lam: float) -> float:
	var p := exp(-lam)
	for i in range(1, k + 1):
		p *= lam / float(i)
	return p


func _tau(x: int, y: int) -> float:
	var rho := float(cal["rho"])
	if x == 0 and y == 0:
		return maxf(0.0, 1.0 - lambda_home * lambda_away * rho)
	if x == 0 and y == 1:
		return maxf(0.0, 1.0 + lambda_home * rho)
	if x == 1 and y == 0:
		return maxf(0.0, 1.0 + lambda_away * rho)
	if x == 1 and y == 1:
		return maxf(0.0, 1.0 - rho)
	return 1.0


func joint(x: int, y: int) -> float:
	if x < 0 or y < 0 or x > MAX_GOALS or y > MAX_GOALS:
		return 0.0
	return float(_build_table()[(y * (MAX_GOALS + 1)) + x])


func probabilities() -> Array:
	return _build_table()

func _build_table() -> Array:
	if not _table.is_empty():
		return _table
	var cells := (MAX_GOALS + 1) * (MAX_GOALS + 1)
	var probs: Array = []
	probs.resize(cells)
	var total := 0.0
	for y in range(MAX_GOALS + 1):
		var py := _poisson(y, lambda_away)
		for x in range(MAX_GOALS + 1):
			var p := py * _poisson(x, lambda_home) * _tau(x, y)
			probs[y * (MAX_GOALS + 1) + x] = p
			total += p
	for i in range(cells):
		probs[i] = float(probs[i]) / total
	_table = probs
	return _table


func sample() -> Vector2i:
	var table := _build_table()
	var u := rng.randf()
	var acc := 0.0
	for i in range(table.size()):
		acc += float(table[i])
		if u < acc:
			return Vector2i(i % (MAX_GOALS + 1), i / (MAX_GOALS + 1))
	return Vector2i(MAX_GOALS, MAX_GOALS)


func outcomes() -> Dictionary:
	var table := _build_table()
	var home_win := 0.0
	var draw := 0.0
	var away_win := 0.0
	var over25 := 0.0
	var btts := 0.0
	for y in range(MAX_GOALS + 1):
		for x in range(MAX_GOALS + 1):
			var p := float(table[y * (MAX_GOALS + 1) + x])
			if x > y:
				home_win += p
			elif x == y:
				draw += p
			else:
				away_win += p
			if x + y > 2.5:
				over25 += p
			if x > 0 and y > 0:
				btts += p
	return {"home": home_win, "draw": draw, "away": away_win, "over_2_5": over25, "btts": btts}
