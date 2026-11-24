class_name CensusLib
extends RefCounted

## Shared helpers for the tier-2 Poisson-agreement census suites. Not a test
## suite: it runs full matches, moves the per-match rows from the shard jobs to
## the assert job, and reduces the statistics the assert asserts on. Kept next
## to the suites so the census is one unit.

## Agreement target: the calibration goal is a relative gap of ≤ 10% between
## sample variance and the model's λ. Big-n manual censuses are the evidence
## for that goal; the suite grid alone cannot resolve it (see below).
const VAR_TARGET := 0.10

## Wall-clock budget for one full headless physics match. Measured on the
## tier-2 runners (4-vCPU ubuntu-latest, Nov 2026): 40–80 s per match for the
## same fixed seeds, so the gate sits at 120 s — it still catches a real
## sim-cost regression (a 2× tick) without failing on runner hardware
## variance. A native hot loop stays the way to tighten it.
## CENSUS_MATCH_BUDGET_MS overrides it when measuring another host.
const MATCH_BUDGET_MS := 120_000

## Two-sided 95% coverage factor for the sampling band around λ.
const VAR_Z := 1.96

## Fixed census grid: n matches per anchor, seeds SEED0 + i·STRIDE. Fixed, so a
## failure is engine drift rather than a fresh roll.
const GRID_N := 32
const SEED0 := 7000
const STRIDE := 13

## CI shards the grid this many ways (one job each). The shards partition the
## grid exactly, so pooling their rows reproduces a single-run census.
const GRID_SHARDS := 4

## Where shard suites write their rows and the assert suite reads them.
const DEFAULT_RESULTS_DIR := ".gd-tools/census-results"

## The gated anchors: a rating-gap fixture and an even-strength one.
const ANCHORS := {
	"mci_ips": {"home": "MCI", "away": "IPS"},
	"mci_mci": {"home": "MCI", "away": "MCI"},
}

## Play one full physics match headless and return its outcome and wall clock.
static func run_match(home: String, away: String, seed_in: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var eng := MatchEngine.new(seed_in, home, away)
	var guard := 0
	while eng.phase != "full_time" and guard < 60 * 60 * 400:
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		guard += 1
	var ms := Time.get_ticks_msec() - t0
	return {
		"seed": seed_in, "home_goals": int(eng.score[0]), "away_goals": int(eng.score[1]),
		"ms": ms, "xg_home": float(eng.stats[0]["xg"]), "xg_away": float(eng.stats[1]["xg"]),
		"shots_home": int(eng.stats[0]["shots"]), "shots_away": int(eng.stats[1]["shots"]),
	}

## Unbiased sample variance (n-1 denominator), same as the manual drive in
## tests/check_poisson_agreement.gd.
static func sample_variance(xs: Array) -> float:
	if xs.size() < 2:
		return 0.0
	var total := 0.0
	for x in xs:
		total += float(x)
	var m: float = total / xs.size()
	var acc := 0.0
	for x in xs:
		acc += (float(x) - m) * (float(x) - m)
	return acc / (xs.size() - 1)

static func mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var total := 0.0
	for x in xs:
		total += float(x)
	return total / xs.size()

## Relative distance between a sample statistic and the model value.
static func rel_gap(sample: float, model: float) -> float:
	return absf(sample - model) / model

## Standard deviation of the unbiased sample variance S² when the counts are
## Poisson(lam) draws, i.e. the noise the census inherits from its own n.
##
## Var(S²) = [μ4 − σ⁴·(n−3)/(n−1)] / n with σ² = λ and μ4 = 3λ² + λ.
static func variance_sampling_sd(lam: float, n: int) -> float:
	if n < 2 or lam <= 0.0:
		return 0.0
	var var_s2 := (3.0 * lam * lam + lam - lam * lam * float(n - 3) / float(n - 1)) / float(n)
	return sqrt(maxf(var_s2, 0.0))

## Relative half-width the census may tolerate: the 10% agreement target plus
## the two-sided 95% sampling allowance at this n and λ.
##
## The bare 10% tolerance sits *below* the census's own sampling noise (the
## relative sd of S² is ~27% at n = 32), so a literal 10% gate would fail an
## honestly calibrated engine almost every run — and could only be turned green
## by tuning to the fixed seeds. Widening by the sampling band keeps the 10%
## goal as the calibration target (proved by big-n manual censuses) while the
## fixed grid stays a reproducible drift tripwire: it fails when the engine's
## dispersion moves by more than n can explain.
static func variance_tolerance(lam: float, n: int) -> float:
	return VAR_TARGET + VAR_Z * variance_sampling_sd(lam, n) / maxf(lam, 0.001)

## Read an integer from the environment, falling back when unset or malformed.
static func env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key).strip_edges()
	return int(raw) if raw.is_valid_int() else fallback

## Global grid indices that belong to one shard. Interleaved, so every shard
## sees the whole spread of the grid and their union is the grid itself.
static func shard_indices(n: int, shard: int, shards: int) -> Array:
	var out: Array = []
	var parts := maxi(1, shards)
	for i in range(maxi(1, n)):
		if i % parts == clampi(shard, 0, parts - 1):
			out.append(i)
	return out

## Seed for one grid index.
static func seed_for(index: int) -> int:
	return SEED0 + index * STRIDE

## Play this anchor's shard of the fixed grid and return the per-match rows.
## Rows carry the anchor so one results directory can pool every shard.
static func run_shard(anchor: String, n: int, shard: int, shards: int) -> Array:
	var sides: Dictionary = ANCHORS[anchor]
	var rows: Array = []
	for i in shard_indices(n, shard, shards):
		var row := run_match(str(sides["home"]), str(sides["away"]), seed_for(int(i)))
		row["anchor"] = anchor
		rows.append(row)
	return rows

## Slowest row of a run (the timer gate reads it), or {} when there are none.
static func slowest(rows: Array) -> Dictionary:
	var worst: Dictionary = {}
	for r in rows:
		if worst.is_empty() or int(r["ms"]) > int(worst["ms"]):
			worst = r
	return worst

## Filesystem path for a results directory. `user://`-style project paths are
## globalised so the DirAccess/FileAccess absolute helpers behave the same for
## tests and CI.
static func fs_path(dir: String) -> String:
	if dir.begins_with("user://") or dir.begins_with("res://"):
		return ProjectSettings.globalize_path(dir)
	return dir

## Write rows as JSON Lines into `dir`. The shard id keeps every job's file
## distinct when CI downloads them all into one directory.
static func write_rows(dir: String, anchor: String, shard: int, rows: Array) -> String:
	var base := fs_path(dir)
	DirAccess.make_dir_recursive_absolute(base)
	var path := "%s/%s-shard%d.jsonl" % [base.rstrip("/"), anchor, shard]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	for r in rows:
		f.store_line(JSON.stringify(r))
	f.close()
	return path

## Read every JSONL row under `dir`. A missing directory reads as empty, which
## is how a local run before any shard results exist skips instead of failing.
static func read_rows(dir: String) -> Array:
	var rows: Array = []
	var base := fs_path(dir)
	for name in DirAccess.get_files_at(base):
		if not str(name).ends_with(".jsonl"):
			continue
		var f := FileAccess.open("%s/%s" % [base.rstrip("/"), name], FileAccess.READ)
		if f == null:
			continue
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line.is_empty():
				continue
			var parsed = JSON.parse_string(line)
			if parsed is Dictionary:
				rows.append(parsed)
		f.close()
	return rows

## Pool rows by anchor, keeping one row per seed so a re-run shard cannot
## double-count itself.
static func pool_by_anchor(rows: Array) -> Dictionary:
	var by_anchor := {}
	var seen := {}
	for r in rows:
		var anchor := str(r.get("anchor", ""))
		if not ANCHORS.has(anchor):
			continue
		var key := "%s:%d" % [anchor, int(r["seed"])]
		if seen.has(key):
			continue
		seen[key] = true
		if not by_anchor.has(anchor):
			by_anchor[anchor] = []
		by_anchor[anchor].append(r)
	return by_anchor

## Model λ for an anchor, from the same Poisson model the gate compares to.
static func anchor_lambda(anchor: String) -> Array:
	var sides: Dictionary = ANCHORS[anchor]
	var model := PoissonModel.new(SEED0, str(sides["home"]), str(sides["away"]))
	return [model.lambda_home, model.lambda_away]

## Reduce one anchor's rows to the numbers the gate asserts on.
static func summarise(anchor: String, rows: Array) -> Dictionary:
	var home: Array = []
	var away: Array = []
	var xg_h := 0.0
	var xg_a := 0.0
	for r in rows:
		home.append(int(r["home_goals"]))
		away.append(int(r["away_goals"]))
		xg_h += float(r["xg_home"])
		xg_a += float(r["xg_away"])
	var n := rows.size()
	var lam := anchor_lambda(anchor)
	var var_h := sample_variance(home)
	var var_a := sample_variance(away)
	return {
		"anchor": anchor, "n": n,
		"mean_home": mean(home), "mean_away": mean(away),
		"lambda_home": lam[0], "lambda_away": lam[1],
		"var_home": var_h, "var_away": var_a,
		"gap_home": rel_gap(var_h, lam[0]), "gap_away": rel_gap(var_a, lam[1]),
		"tol_home": variance_tolerance(lam[0], n), "tol_away": variance_tolerance(lam[1], n),
		"xg_home": xg_h / maxf(float(n), 1.0), "xg_away": xg_a / maxf(float(n), 1.0),
		"slowest_ms": int(slowest(rows).get("ms", 0)),
	}

## One log line per anchor that CI logs and the wiki table can be read from.
static func summary_line(s: Dictionary) -> String:
	return "CENSUS %s n=%d  goals %.2f-%.2f (λ %.2f-%.2f)  var %.2f-%.2f (band %.0f%%/%.0f%%, gap %.0f%%/%.0f%%)  xG %.2f-%.2f  slowest %d ms" % [
		s["anchor"], s["n"], s["mean_home"], s["mean_away"], s["lambda_home"], s["lambda_away"],
		s["var_home"], s["var_away"], s["tol_home"] * 100.0, s["tol_away"] * 100.0,
		s["gap_home"] * 100.0, s["gap_away"] * 100.0, s["xg_home"], s["xg_away"], s["slowest_ms"]]
