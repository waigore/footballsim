class_name CommentaryRender
extends RefCounted


const C := preload("res://scripts/sim/commentary/commentary.gd")
const R := preload("res://scripts/sim/commentary/commentary_restarts.gd")
const B := preload("res://scripts/sim/commentary/commentary_bench.gd")
const X := preload("res://scripts/sim/commentary/commentary_extra_time.gd")


static func render(kind: String, pick: int, f: Dictionary) -> String:
	var rng := CommentaryPick.new(pick)
	match kind:
		"shot":
			return C.shot(rng, str(f.get("player", "")), float(f.get("dist", 0.0)),
				float(f.get("xg", 0.0)), float(f.get("pressure", 0.0)),
				str(f.get("shot_kind", "shot")))
		"header":
			return C.shot(rng, str(f.get("player", "")), float(f.get("dist", 0.0)),
				float(f.get("xg", 0.0)), float(f.get("pressure", 0.0)), "header")
		"save":
			return C.save(rng, str(f.get("player", "")), str(f.get("credit", "")),
				str(f.get("how", "hold")), float(f.get("xg", 0.0)))
		"cross":
			return C.cross(rng, str(f.get("player", "")))
		"clearance":
			return C.clearance(rng, str(f.get("player", "")), bool(f.get("headed", false)))
		"block":
			return C.block(rng, str(f.get("player", "")), str(f.get("shooter", "")))
		"woodwork":
			return C.woodwork(rng, str(f.get("player", "")), str(f.get("frame", "post")))
		"foul":
			return C.foul(rng, str(f.get("fouler", "")), str(f.get("victim", "")),
				bool(f.get("penalty", false)))
		"handball":
			return C.handball(rng, str(f.get("player", "")), bool(f.get("penalty", false)))
		"offside":
			return C.offside(rng, str(f.get("player", "")))
		"card":
			return C.card(rng, str(f.get("player", "")), str(f.get("card", "yellow")))
		"goal":
			return C.goal(rng, str(f.get("player", "")), str(f.get("assist", "")),
				bool(f.get("own_goal", false)), str(f.get("team_short", "")),
				str(f.get("other_short", "")), int(f.get("before_for", 0)),
				int(f.get("before_against", 0)), int(f.get("minute", 0)),
				bool(f.get("penalty", false)))
		"kickoff":
			return R.kickoff(rng, str(f.get("team_name", "")))
		"restart":
			return R.restart(rng, str(f.get("restart", "")), str(f.get("team_short", "")),
				str(f.get("taker", "")), false)
		"restart_wait":
			return R.restart(rng, str(f.get("restart", "")), str(f.get("team_short", "")),
				str(f.get("taker", "")), true)
		"penalty_taken":
			return R.penalty_taken(rng, str(f.get("player", "")))
		"half_time":
			return R.half_time(rng, str(f.get("a_short", "")), int(f.get("a_score", 0)),
				str(f.get("b_short", "")), int(f.get("b_score", 0)))
		"full_time":
			return R.full_time(rng, str(f.get("a_short", "")), int(f.get("a_score", 0)),
				str(f.get("b_short", "")), int(f.get("b_score", 0)))
		"substitution":
			return B.substitution(rng, str(f.get("team_short", "")),
				str(f.get("on_name", "")), str(f.get("off_name", "")),
				str(f.get("manager", "")))
		"injury":
			return B.injury(rng, str(f.get("player", "")), bool(f.get("continues", false)))
		"tactics":
			return B.tactics(rng, str(f.get("manager", "")), str(f.get("team_short", "")),
				f.get("changes", []))
		"extra_time":
			return X.extra_time(rng, str(f.get("a_short", "")), str(f.get("b_short", "")))
		"extra_time_start":
			return X.extra_time_start(rng, str(f.get("a_short", "")), str(f.get("b_short", "")))
		"extra_time_second":
			return X.extra_time_second(rng, str(f.get("a_short", "")), str(f.get("b_short", "")))
		"extra_time_break":
			return X.extra_time_break()
		"shootout_start":
			return X.shootout_start(rng, str(f.get("team_short", "")))
		"penalty_scored", "penalty_missed":
			return X.shootout_kick(rng, str(f.get("player", "")), kind == "penalty_scored")
		"shootout_end":
			return X.shootout_end(str(f.get("team_short", "")), int(f.get("pens_for", 0)),
				int(f.get("pens_against", 0)))
		"full_time_pens":
			return X.full_time_pens(rng, str(f.get("a_short", "")), int(f.get("a_score", 0)),
				str(f.get("b_short", "")), int(f.get("b_score", 0)),
				int(f.get("pens_a", 0)), int(f.get("pens_b", 0)))
	return ""
