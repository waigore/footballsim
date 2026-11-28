extends SceneTree

## Poisson calibration loop: audit expected goals, then Monte Carlo whole
## seasons against the last-10 Premier League scoring envelope.
##
##   godot --headless --path . --script res://tools/poisson_calibrate.gd
##   godot --headless --path . --script res://tools/poisson_calibrate.gd -- 40 9000 home_xg=1.40 away_xg=1.20
##
## Args: [seasons] [seed] [key=value ...]. Keys are the model's calibration
## table: home_xg, away_xg, attack_elasticity, defence_elasticity, rho. Anything
## not overridden keeps the model's constant.
##
## Exits 1 when a scored band or the home/draw/away drift gate fails, so a
## candidate retune can be checked in one command. Runs in a couple of seconds
## for the default 20 seasons; no physics, no UI, no renders.

func _init() -> void:
	var envelope := PoissonCalibration.load_envelope()
	if envelope.is_empty():
		print("No envelope at %s — nothing to gate against." % PoissonCalibration.ENVELOPE_PATH)
		quit(1)
		return
	var gate: Dictionary = envelope.get("gate", {})
	var seasons := int(gate.get("seasons", 20))
	var seed0 := int(gate.get("seed", 7000))
	var overrides: Dictionary = {}
	var positional := 0
	for arg in OS.get_cmdline_user_args():
		if arg.contains("="):
			var parts := arg.split("=", true, 1)
			overrides[parts[0]] = float(parts[1])
			continue
		if positional == 0:
			seasons = int(arg)
		elif positional == 1:
			seed0 = int(arg)
		positional += 1

	var cal := PoissonModel.calibration(overrides)
	var started := Time.get_ticks_msec()
	var metrics := PoissonCalibration.run(seasons, seed0, cal)
	var elapsed := Time.get_ticks_msec() - started

	print("\nPoisson calibration — %d seasons, seed %d, %d matches" % [
		int(metrics["seasons"]), seed0, int(metrics["matches"])])
	print("model   home_xg=%.2f away_xg=%.2f attack=%.2f defence=%.2f rho=%.2f" % [
		float(cal["home_xg"]), float(cal["away_xg"]), float(cal["attack_elasticity"]),
		float(cal["defence_elasticity"]), float(cal["rho"])])
	print("λ       %.2f goals a game from expected goals (chance model, not sampled)" % [
		float(metrics["lambda_per_game"])])
	print("time    %.1fs\n" % (float(elapsed) / 1000.0))

	print("λ audit (clear weather)")
	for pairing in [["ENG-MCI1", "ENG-IPS1"], ["ENG-MCI1", "ENG-MUN1"], ["ENG-MCI1", "ENG-ARS1"], ["ENG-MCI1", "ENG-MCI1"], ["ENG-IPS1", "ENG-MCI1"]]:
		var m := PoissonModel.new(0, str(pairing[0]), str(pairing[1]), "clear", {}, cal)
		var o := m.outcomes()
		print("  %-3s v %-3s   λ %.2f - %.2f   H/D/A %.2f / %.2f / %.2f" % [
			pairing[0], pairing[1], m.lambda_home, m.lambda_away,
			float(o["home"]), float(o["draw"]), float(o["away"])])

	var source: Dictionary = envelope.get("source", {})
	print("Last-10 PL envelope — %s, %d seasons, %d matches" % [
		str(source.get("name", "?")), source.get("seasons", []).size(), int(source.get("matches", 0))])
	print("  %-28s %9s   %-20s %s" % ["metric", "model", "envelope", "verdict"])
	var rows := PoissonCalibration.checks(metrics, envelope)
	var fails := 0
	for row in rows:
		var fmt := str(row["format"])
		var value := fmt % float(row["value"])
		var band := (fmt + " .. " + fmt) % [float(row["lo"]), float(row["hi"])]
		var ok := bool(row["pass"])
		if not ok:
			fails += 1
		print("  %-28s %9s   %-20s %s" % [str(row["name"]), value, band, "PASS" if ok else "FAIL"])

	if envelope.get("pre_tune", {}).get("result_mix", {}).get("home", 0.0) == 0.0:
		var mix: Dictionary = metrics["result_mix"]
		print("\n  sampled home / draw / away: %.3f / %.3f / %.3f" % [
			float(mix["home"]), float(mix["draw"]), float(mix["away"])])
		print("  (pre-tune H/D/A baseline not recorded yet — the drift gate is skipped)")
	print("\n%s: %d of %d gates passed" % ["PASS" if fails == 0 else "FAIL", rows.size() - fails, rows.size()])
	quit(1 if fails > 0 else 0)
