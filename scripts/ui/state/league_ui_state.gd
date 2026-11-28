class_name LeagueUiState
extends RefCounted


signal changed(scope: String)

var mode := "wizard"
var wizard := {"name": "", "calendar_mode": "generated", "advance_mode": "fixture_days",
	"competitions": ["PL"], "uefa": true, "error": ""}
var europe := {"comp": "", "tab": "", "round": ""}
var europe_draw := {"competition": "", "round": "", "revealed": 0, "done": false, "t": 0.0}
var stats_filter := {"league": "", "month": "", "team": "", "stat": "goals"}
var report_filter := {"league": "", "interest": false}
var interest_query := ""
var calendar_filter := ""
var cups_round := ""
var cup_focus := ""
var draw_state := {"shown": 0, "clock": 0.0}
var month := ""
var day := ""
var day_fixtures: Array = []
var days_cache := {}
var report: Dictionary = {}
var roundup: Array = []
var saves: Array = []
var load_from := "menu"
var sys := {"status": "", "error": "", "naming": false, "name": ""}
var report_back := "hub"


func set_mode(next: String) -> void:
	if mode == next:
		return
	mode = next
	mark("mode")


func mark(scope: String) -> void:
	changed.emit(scope)


func open_wizard(uefa_available: bool) -> void:
	mode = "wizard"
	wizard = {"name": "", "calendar_mode": "generated", "advance_mode": "fixture_days",
		"competitions": ["PL"], "uefa": uefa_available, "cups_off": [], "error": ""}
	mark("wizard")


func set_filter(scope: String, key: String, value: Variant) -> void:
	if scope == "stats":
		if stats_filter.get(key, null) == value:
			return
		stats_filter[key] = value
	elif scope == "report":
		if report_filter.get(key, null) == value:
			return
		report_filter[key] = value
	else:
		return
	mark(scope)
