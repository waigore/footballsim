extends SceneTree

## Prints every goal plus the goal-line keeper check that allowed it.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_i := 8008
	var home := "WOL"
	var away := "LEE"
	if args.size() >= 3:
		seed_i = int(args[0])
		home = args[1]
		away = args[2]
	var eng := MatchEngine.new(seed_i, home, away)
	var guard := 0
	while eng.phase != "full_time" and guard < int(60 * 60 * 125):
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		guard += 1
	print("FINAL %s %d-%d %s  shots %d-%d  xg %.2f-%.2f" % [
		home, eng.score[0], eng.score[1], away,
		eng.stats[0]["shots"], eng.stats[1]["shots"], eng.stats[0]["xg"], eng.stats[1]["xg"]])
	var gi := 0
	for ev in eng.events:
		if ev["type"] == "goal":
			gi += 1
			print("  %d' %s" % [ev["minute"], ev["text"]])
	var n: int = eng.gk_debug.size()
	print("gk goal-line checks: %d" % n)
	for i in range(maxi(0, n - 16), n):
		print("    " + String(eng.gk_debug[i]))
	quit()
