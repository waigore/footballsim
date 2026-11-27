extends SceneTree

## Evidence log for #321: a player who leaves the pitch takes no further part.
##
## Sweeps seeded synthetic reports (the AUTO/Poisson path) across four clubs and
## prints what the sweep found: how many reports listed a card, goal or assist
## for a player from his injury or sending-off minute on, how many bodies were
## claimed to leave twice, and how far the goal count drifted from the scoreline.
## A clean run prints `later_rows=0` and `double_exits=0`.
##
## It then prints one report that loses a body, row by row, so the log names the
## rule it checked rather than only counting it.
##
##   godot --headless --path . --script res://tools/issue321_probe.gd

const SEEDS := 300
const CLUBS := ["MCI", "ARS", "CH-BIR", "CH-WXM"]
const GOAL_COUNTS := [0, 2, 4]

func _initialize() -> void:
	var reports := 0
	var exits := 0
	var later_rows := 0
	var double_exits := 0
	var goal_drift := 0
	var bad_reports := 0
	var sample: Dictionary = {}
	var violation: Dictionary = {}
	for club in CLUBS:
		var xi: Array = TeamData.get_team(club).get("starters", [])
		for seed in range(1, SEEDS + 1):
			for goals in GOAL_COUNTS:
				reports += 1
				var fixture_id := "gw01-%s-X" % club
				var events := MatchEvents.side(seed, fixture_id, club, xi, goals)
				var exit_at := {}
				var seen := {}
				for e in events:
					var kind := str(e["kind"])
					if kind != "injury" and kind != "red":
						continue
					var id := str(e["player_id"])
					if seen.has(id):
						double_exits += 1
					seen[id] = true
					var minute := int(e["minute"])
					if not exit_at.has(id) or minute < int(exit_at[id]):
						exit_at[id] = minute
				exits += exit_at.size()
				if not exit_at.is_empty() and sample.is_empty():
					sample = {"club": club, "seed": seed, "goals": goals,
						"fixture_id": fixture_id, "events": events}
				var scored := 0
				var bad := false
				for e in events:
					var kind := str(e["kind"])
					var id := str(e["player_id"])
					if kind == "goal":
						scored += 1
					if kind == "injury" or kind == "red":
						continue
					if not exit_at.has(id):
						continue
					if int(e["minute"]) >= int(exit_at[id]):
						later_rows += 1
						bad = true
						if violation.is_empty():
							violation = {"club": club, "seed": seed, "goals": goals,
								"fixture_id": fixture_id, "events": events}
				if scored != goals:
					goal_drift += 1
				if bad:
					bad_reports += 1
	print("reports=%d exits=%d later_rows=%d double_exits=%d goal_drift=%d bad_reports=%d" % [
		reports, exits, later_rows, double_exits, goal_drift, bad_reports])
	if not sample.is_empty():
		_print_report("sample", sample)
	if not violation.is_empty():
		_print_report("violation", violation)

## One readable report, row by row, so the log shows what the sweep read.
func _print_report(label: String, report: Dictionary) -> void:
	var rows: Array = []
	for e in report["events"]:
		rows.append("%d %s %s" % [int(e["minute"]), str(e["kind"]), str(e["detail"])])
	print("%s club=%s seed=%d goals=%d fixture=%s\n  %s" % [
		label, str(report["club"]), int(report["seed"]), int(report["goals"]),
		str(report["fixture_id"]), "\n  ".join(rows)])
