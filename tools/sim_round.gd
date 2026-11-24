extends SceneTree

## Simulates a full Premier League round (10 matches, all 20 clubs once).
##   godot --headless --path . --script tools/sim_round.gd -- [rounds] [seed0]
## Prints a results table plus aggregate score/shot statistics.

const FIXTURES := [
	["ARS", "CHE"], ["LIV", "MUN"], ["MCI", "TOT"], ["NEW", "AVL"], ["BHA", "CRY"],
	["FUL", "BRE"], ["BOU", "EVE"], ["COV", "NFO"], ["HUL", "LEE"], ["IPS", "SUN"],
]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var rounds := 1
	if args.size() > 0:
		rounds = int(args[0])
	var seed0 := 5000
	if args.size() > 1:
		seed0 = int(args[1])
	var only := -1
	if args.size() > 2:
		only = int(args[2])

	var total_goals := 0
	var total_matches := 0
	var total_shots := 0
	var total_on_target := 0
	var total_xg := 0.0
	var total_offsides := 0
	var total_corners := 0
	var total_fouls := 0
	var total_saves := 0
	var total_passes := 0
	var biggest := 0
	var biggest_line := ""
	var score_hist := {}
	var home_wins := 0
	var draws := 0
	var away_wins := 0
	var clean_sheets := 0
	var failed := 0

	for r in range(rounds):
		print("\n=== ROUND %d (seed %d) ===" % [r + 1, seed0 + r * 100])
		for i in range(FIXTURES.size()):
			if only >= 0 and i != only:
				continue
			var f: Array = FIXTURES[i]
			var eng := MatchEngine.new(seed0 + r * 100 + i, f[0], f[1])
			var guard := 0
			var max_ticks := int(60 * 60 * 125)
			while eng.phase != "full_time" and guard < max_ticks:
				if eng.phase == "half_time":
					eng.begin_second_half()
				eng.tick()
				guard += 1
			if eng.phase != "full_time":
				failed += 1
				print("  %s v %s  DID NOT FINISH (phase=%s clock=%.0f)" % [f[0], f[1], eng.phase, eng.clock])
				continue
			var sc: Array = eng.score
			var s0: Dictionary = eng.stats[0]
			var s1: Dictionary = eng.stats[1]
			var gd: int = absi(sc[0] - sc[1])
			if gd > biggest:
				biggest = gd
				biggest_line = "%s %d-%d %s" % [f[0], sc[0], sc[1], f[1]]
			var key := "%d-%d" % [sc[0], sc[1]]
			score_hist[key] = score_hist.get(key, 0) + 1
			total_goals += sc[0] + sc[1]
			total_matches += 1
			total_shots += s0["shots"] + s1["shots"]
			total_on_target += s0["on_target"] + s1["on_target"]
			total_xg += s0["xg"] + s1["xg"]
			total_offsides += s0["offsides"] + s1["offsides"]
			total_corners += s0["corners"] + s1["corners"]
			total_fouls += s0["fouls"] + s1["fouls"]
			total_saves += s0["saves"] + s1["saves"]
			total_passes += s0["passes"] + s1["passes"]
			if sc[0] > sc[1]:
				home_wins += 1
			elif sc[0] == sc[1]:
				draws += 1
			else:
				away_wins += 1
			if sc[0] == 0 or sc[1] == 0:
				clean_sheets += 1
			print("  %-3s %d-%d %-3s   shots %d-%d (ot %d-%d)  xG %.2f-%.2f  poss %.0f-%.0f  off %d-%d  cor %d-%d  fouls %d-%d" % [
				f[0], sc[0], sc[1], f[1],
				s0["shots"], s1["shots"], s0["on_target"], s1["on_target"],
				s0["xg"], s1["xg"], eng.possession_pct().x, eng.possession_pct().y,
				s0["offsides"], s1["offsides"], s0["corners"], s1["corners"],
				s0["fouls"], s1["fouls"]])

	if total_matches == 0:
		print("no matches simulated")
		quit()
		return
	print("\n=== AGGREGATE over %d matches ===" % total_matches)
	print("  goals/match      %.2f" % (float(total_goals) / total_matches))
	print("  shots/match      %.2f" % (float(total_shots) / total_matches))
	print("  on-target/match  %.2f" % (float(total_on_target) / total_matches))
	print("  xG/match         %.2f" % (total_xg / total_matches))
	print("  offsides/match   %.2f" % (float(total_offsides) / total_matches))
	print("  corners/match    %.2f" % (float(total_corners) / total_matches))
	print("  fouls/match      %.2f" % (float(total_fouls) / total_matches))
	print("  saves/match      %.2f" % (float(total_saves) / total_matches))
	print("  passes/match     %.2f" % (float(total_passes) / total_matches))
	print("  home W-D-L       %d-%d-%d" % [home_wins, draws, away_wins])
	print("  clean sheets     %d" % clean_sheets)
	print("  biggest win      %d goals (%s)" % [biggest, biggest_line])
	var keys := score_hist.keys()
	keys.sort()
	var hist := []
	for k in keys:
		hist.append("%s x%d" % [k, score_hist[k]])
	print("  scorelines       %s" % ", ".join(hist))
	print("  unfinished       %d" % failed)
	quit()
