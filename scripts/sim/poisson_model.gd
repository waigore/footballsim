class_name PoissonModel
extends RefCounted

## Independent, physics-free scoreline model: Dixon-Coles corrected Poisson on
## expected goals derived from EA FC squad ratings.
##
## Every input is a rating or a documented constant, so a fixture's λ can be
## read and audited without running the match engine. The physics engine is
## calibrated against this model, not the other way round.
##
##   λ_home = HOME_XG · exp(A·(attack_h − Ā)/10 + D·(D̄ − defence_a)/10) · weather
##   λ_away = AWAY_XG · exp(A·(attack_a − Ā)/10 + D·(D̄ − defence_h)/10) · weather
##
## Dixon-Coles τ then lifts 0-0 and 1-1 and trims 1-0 / 0-1, which is where a
## plain Poisson under-counts low-scoring draws.

## League baselines (goals per side in an average fixture, home advantage built in).
## Fitted to the last-10 Premier League scoring envelope (`data/pl_scoring_envelope.json`),
## not to the physics census: an even fixture sits near 2.5 goals, and a top side
## at home against the weakest club sits near 2.5 expected goals.
const HOME_XG := 1.35
const AWAY_XG := 1.16
## Rating elasticity per 10 points of the derived 0-100 strength scale. It still
## separates the sides, but flat enough that a big gap makes a football-sized
## scoreline rather than a census-sized one.
const ATTACK_ELASTICITY := 0.98
const DEFENCE_ELASTICITY := 0.98
## Dixon-Coles low-score dependence. Damping the scoring lifted 0-0 and 1-1 draws
## about five points above the liked win–draw–loss mix, so the correction leans
## the other way: it trims the two low-scoring draws slightly and lifts 1-0 / 0-1.
## The owner's constraint is to keep the pre-tune 1X2 shape; see the calibration
## report (`tools/poisson_calibrate.gd`) and the poisson-model wiki page.
const RHO := 0.08
## Every number λ and τ read, in one table: the constants above, with what-if
## overrides when a calibration run sweeps candidates before landing one.
const DEFAULT_CALIBRATION := {
	"home_xg": HOME_XG,
	"away_xg": AWAY_XG,
	"attack_elasticity": ATTACK_ELASTICITY,
	"defence_elasticity": DEFENCE_ELASTICITY,
	"rho": RHO,
}
## Score grid: values above this per side carry < 0.01% of the mass for λ ≤ 6.
const MAX_GOALS := 9

const WEATHER_MULT := {
	"clear": 1.0, "cloudy": 0.99, "rain": 0.94, "wind": 0.91, "snow": 0.84,
}

var home_id := ""
var away_id := ""
var weather := "clear"
var modifiers: Dictionary = {}
## The calibration this model was built with (defaults unless overridden).
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

## The constants in force, with any what-if overrides applied. One table so the
## calibration tool and the model read the same numbers.
static func calibration(overrides: Dictionary = {}) -> Dictionary:
	var c: Dictionary = DEFAULT_CALIBRATION.duplicate()
	if not overrides.is_empty():
		c.merge(overrides, true)
	return c

# ------------------------------------------------------------- strengths ----

## Attack / midfield / defence reading of a squad, all on the 0-100 attribute
## scale. Roles decide the weights: strikers define the attack, midfield the
## control term, the back line and keeper the defence.
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
		# Attacking output: finishing first, then carry, then supply.
		attack_num += (sho * 0.60 + dri * 0.30 + pas * 0.10) * (0.25 + push)
		attack_w += 0.25 + push
		if Attrs.is_mid(role):
			mid_sum += pas * 0.45 + dri * 0.30 + dfn * 0.25
			mid_n += 1
		if Attrs.is_defender(role) or role in ["RDM", "LDM", "CDM"]:
			def_num += (dfn * 0.70 + phy * 0.20 + ovr * 0.10) * (1.15 if Attrs.is_defender(role) else 0.65)
			def_w += 1.15 if Attrs.is_defender(role) else 0.65
	# A squad with no listed midfielder (rare shapes) still needs a control term.
	var midfield := mid_sum / float(mid_n) if mid_n > 0 else (attack_num / maxf(attack_w, 0.01) + def_num / maxf(def_w, 0.01)) * 0.5
	return {
		"attack": attack_num / maxf(attack_w, 0.01),
		"midfield": midfield,
		"defence": def_num / maxf(def_w, 0.01),
	}

## Attack and defence as they enter λ: midfield supplies the attack and screens
## the defence, so a strong midfield improves both ends.
static func effective(s: Dictionary) -> Vector2:
	return Vector2(
		float(s["attack"]) * 0.65 + float(s["midfield"]) * 0.35,
		float(s["defence"]) * 0.75 + float(s["midfield"]) * 0.25)

## League means over every club in the data set (cached for the session).
static func league_means() -> Dictionary:
	if not _means_cache.is_empty():
		return _means_cache
	var att := 0.0
	var dfn := 0.0
	var n := 0
	for id in TeamData.team_ids():
		var eff := effective(team_strength(TeamData.get_team(id)))
		att += eff.x
		dfn += eff.y
		n += 1
	_means_cache = {"attack": att / maxf(float(n), 1.0), "defence": dfn / maxf(float(n), 1.0), "clubs": n}
	return _means_cache

# ---------------------------------------------------------------- lambdas ---

## The two halves of λ's exponent, per side, already divided by 10 rating
## points: `attack` is how far the side's effective attack sits above the league
## mean, `defence` how far the opposition's effective defence sits below it.
## One exponent source: the model's λ and the engine's shot-contest calibration
## both read these numbers instead of deriving rating gaps of their own.
static func exponent_terms(home: String, away: String) -> Dictionary:
	var m := league_means()
	var h := effective(team_strength(TeamData.get_team(home)))
	var a := effective(team_strength(TeamData.get_team(away)))
	return {
		"attack": Vector2(
			(h.x - float(m["attack"])) / 10.0, (a.x - float(m["attack"])) / 10.0),
		"defence": Vector2(
			(float(m["defence"]) - a.y) / 10.0, (float(m["defence"]) - h.y) / 10.0),
	}

## How weak the defence each side faces is, in rating points / 10. The physics
## engine scales a shot's quality by this, because its positional xG only knows
## distance, angle and aim.
static func defence_exponents(home: String, away: String) -> Vector2:
	return exponent_terms(home, away)["defence"]

## Per-side λ exponents for a pairing: what the model adds to (or subtracts
## from) each side's goals relative to the league baselines, from the two
## squads' effective attack/defence.
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
	var m := league_means()
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

## Expected goals for (home, away).
func expected_goals() -> Vector2:
	return Vector2(lambda_home, lambda_away)

# ------------------------------------------------------------ distribution --

func _poisson(k: int, lam: float) -> float:
	var p := exp(-lam)
	for i in range(1, k + 1):
		p *= lam / float(i)
	return p

## Dixon-Coles low-score dependence. τ > 1 lifts the outcome, τ < 1 trims it.
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

## Joint score probability P(home = x, away = y), τ-corrected and normalised
## over the 0..MAX_GOALS grid.
func joint(x: int, y: int) -> float:
	if x < 0 or y < 0 or x > MAX_GOALS or y > MAX_GOALS:
		return 0.0
	return float(_build_table()[(y * (MAX_GOALS + 1)) + x])

## Flat row-major probability table: index y * (MAX_GOALS + 1) + x.
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

## Draw one scoreline from the corrected distribution. Deterministic per seed.
func sample() -> Vector2i:
	var table := _build_table()
	var u := rng.randf()
	var acc := 0.0
	for i in range(table.size()):
		acc += float(table[i])
		if u < acc:
			return Vector2i(i % (MAX_GOALS + 1), i / (MAX_GOALS + 1))
	return Vector2i(MAX_GOALS, MAX_GOALS)

## Result-market probabilities for the same distribution.
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
