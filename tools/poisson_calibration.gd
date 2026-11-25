class_name PoissonCalibration
extends RefCounted

## Physics-free Monte Carlo for the Poisson scoreline model: whole seasons are
## sampled from `PoissonModel.sample()` over a mirrored round-robin, and the
## metrics the last-10 Premier League envelope gates on are read back out.
##
## The CLI (`tools/poisson_calibrate.gd`) prints the report; the regression
## suite reads the same functions, so a constant change cannot pass one gate and
## fail the other.

const ENVELOPE_PATH := "res://data/pl_scoring_envelope.json"

## The checked-in envelope. Empty when the file is missing or unreadable, which
## the caller treats as "no gate" rather than inventing bands.
static func load_envelope(path: String = ENVELOPE_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

# ------------------------------------------------------------- fixtures -----

## One season: every pairing, then the mirror, in round order. Home and away
## alternate across the circle's rounds, so the mirror gives each club a
## balanced 19 home / 19 away split.
static func season_fixtures(clubs: Array) -> Array:
	var out: Array = []
	var rounds := FixtureCalendar.pairings(clubs)
	for round_pairs in rounds:
		for pair in round_pairs:
			out.append([str(pair[0]), str(pair[1])])
	for round_pairs in rounds:
		for pair in round_pairs:
			out.append([str(pair[1]), str(pair[0])])
	return out

# -------------------------------------------------------------- seasons -----

## Play one sampled season. Returns the season's totals plus the champion's
## goal figures, which is where overscoring shows up first.
static func play_season(season: int, seed0: int, cal: Dictionary, fixtures: Array) -> Dictionary:
	var goals_for: Dictionary = {}
	var goals_against: Dictionary = {}
	var points: Dictionary = {}
	var goal_seq: Dictionary = {}
	var home_goals := 0
	var away_goals := 0
	var home_wins := 0
	var draws := 0
	var away_wins := 0
	var blowouts := 0
	var lambda_sum := 0.0
	for i in range(fixtures.size()):
		var pair: Array = fixtures[i]
		var home := str(pair[0])
		var away := str(pair[1])
		var model := PoissonModel.new(seed0 + season * 100003 + i, home, away, "clear", {}, cal)
		lambda_sum += model.lambda_home + model.lambda_away
		var score := model.sample()
		var gh := score.x
		var ga := score.y
		home_goals += gh
		away_goals += ga
		goals_for[home] = int(goals_for.get(home, 0)) + gh
		goals_against[home] = int(goals_against.get(home, 0)) + ga
		goals_for[away] = int(goals_for.get(away, 0)) + ga
		goals_against[away] = int(goals_against.get(away, 0)) + gh
		_append_seq(goal_seq, home, gh)
		_append_seq(goal_seq, away, ga)
		if gh > ga:
			points[home] = int(points.get(home, 0)) + 3
			home_wins += 1
		elif gh == ga:
			points[home] = int(points.get(home, 0)) + 1
			points[away] = int(points.get(away, 0)) + 1
			draws += 1
		else:
			points[away] = int(points.get(away, 0)) + 3
			away_wins += 1
		if absi(gh - ga) >= 3:
			blowouts += 1
	var champion := _champion(points, goals_for, goals_against)
	var seq: Array = goal_seq.get(champion, [])
	var best15 := 0
	if seq.size() >= 15:
		for start in range(seq.size() - 14):
			var window := 0
			for k in range(start, start + 15):
				window += int(seq[k])
			best15 = maxi(best15, window)
	return {
		"matches": fixtures.size(),
		"goals": home_goals + away_goals,
		"home_goals": home_goals,
		"away_goals": away_goals,
		"home_wins": home_wins,
		"draws": draws,
		"away_wins": away_wins,
		"blowouts": blowouts,
		"lambda_sum": lambda_sum,
		"champion": champion,
		"champion_gf": int(goals_for.get(champion, 0)),
		"champion_best_15_gf": best15,
	}

static func _append_seq(seq: Dictionary, team: String, goals: int) -> void:
	var row: Array = seq.get(team, [])
	row.append(goals)
	seq[team] = row

## Table order: points, then goal difference, then goals for.
static func _champion(points: Dictionary, goals_for: Dictionary, goals_against: Dictionary) -> String:
	var best := ""
	var best_points := -1
	var best_gd := -99999
	var best_gf := -1
	for id in points.keys():
		var p := int(points[id])
		var gd := int(goals_for.get(id, 0)) - int(goals_against.get(id, 0))
		var gf := int(goals_for.get(id, 0))
		var better := false
		if p != best_points:
			better = p > best_points
		elif gd != best_gd:
			better = gd > best_gd
		else:
			better = gf > best_gf
		if better:
			best = str(id)
			best_points = p
			best_gd = gd
			best_gf = gf
	return best

## Seasons of sampled football, aggregated into the envelope's metrics.
static func run(seasons: int, seed0: int, cal: Dictionary, clubs: Array = []) -> Dictionary:
	# The envelope gates the Premier League's scoring bands, so the sampled
	# league is the Premier League even when the seed carries more competitions.
	var ids: Array = clubs.duplicate() if not clubs.is_empty() else TeamData.team_ids("PL")
	var fixtures := season_fixtures(ids)
	var matches := 0
	var goals := 0
	var home_goals := 0
	var home_wins := 0
	var draws := 0
	var away_wins := 0
	var blowouts := 0
	var lambda_sum := 0.0
	var champion_gf := 0.0
	var champion_best_15 := 0.0
	for s in range(seasons):
		var st := play_season(s, seed0, cal, fixtures)
		matches += int(st["matches"])
		goals += int(st["goals"])
		home_goals += int(st["home_goals"])
		home_wins += int(st["home_wins"])
		draws += int(st["draws"])
		away_wins += int(st["away_wins"])
		blowouts += int(st["blowouts"])
		lambda_sum += float(st["lambda_sum"])
		champion_gf += float(st["champion_gf"])
		champion_best_15 += float(st["champion_best_15_gf"])
	var n := maxf(float(matches), 1.0)
	var season_count := maxf(float(seasons), 1.0)
	return {
		"seasons": seasons,
		"matches": matches,
		"goals_per_game": float(goals) / n,
		"home_goal_share": float(home_goals) / maxf(float(goals), 1.0),
		"result_mix": {
			"home": float(home_wins) / n,
			"draw": float(draws) / n,
			"away": float(away_wins) / n,
		},
		"blowout_margin_3_rate": float(blowouts) / n,
		"champion_gf_mean": champion_gf / season_count,
		"champion_best_15_gf_mean": champion_best_15 / season_count,
		"lambda_per_game": lambda_sum / n,
	}

# ---------------------------------------------------------------- gates -----

## The envelope bands, then the owner's preserve-1X2 gate against the frozen
## pre-tune mix. Each row: name, value, target text, pass.
static func checks(metrics: Dictionary, envelope: Dictionary) -> Array:
	var bands: Dictionary = envelope.get("bands", {})
	var gate: Dictionary = envelope.get("gate", {})
	var rows: Array = []
	rows.append(_band("goals per game", float(metrics["goals_per_game"]),
		float(bands["goals_per_game"]["min"]), float(bands["goals_per_game"]["max"]), "%.2f"))
	rows.append(_band("home share of goals", float(metrics["home_goal_share"]),
		float(bands["home_goal_share"]["min"]), float(bands["home_goal_share"]["max"]), "%.3f"))
	rows.append(_band("champion GF (mean)", float(metrics["champion_gf_mean"]),
		float(bands["champion_gf"]["min"]), float(bands["champion_gf"]["max"]), "%.0f"))
	rows.append(_band("champion best 15 GF (mean)", float(metrics["champion_best_15_gf_mean"]),
		float(bands["champion_best_15_gf"]["min"]), float(bands["champion_best_15_gf"]["max"]), "%.0f"))
	rows.append(_band("blowout rate (margin 3+)", float(metrics["blowout_margin_3_rate"]),
		float(bands["blowout_margin_3_rate"]["min"]), float(bands["blowout_margin_3_rate"]["max"]), "%.3f"))
	var baseline: Dictionary = envelope.get("pre_tune", {}).get("result_mix", {})
	var tolerance := float(gate.get("hda_drift_pp", 2.0)) / 100.0
	var mix: Dictionary = metrics["result_mix"]
	for key in ["home", "draw", "away"]:
		var target := float(baseline.get(key, 0.0))
		if target <= 0.0:
			continue
		rows.append(_band("%s share vs pre-tune" % key, float(mix[key]),
			target - tolerance, target + tolerance, "%.3f"))
	return rows

static func _band(name: String, value: float, lo: float, hi: float, fmt: String) -> Dictionary:
	return {
		"name": name,
		"value": value,
		"lo": lo,
		"hi": hi,
		"format": fmt,
		"pass": value >= lo and value <= hi,
	}

## True when every gate passes. Used by the regression suite.
static func passes(metrics: Dictionary, envelope: Dictionary) -> bool:
	for row in checks(metrics, envelope):
		if not bool(row["pass"]):
			return false
	return true
