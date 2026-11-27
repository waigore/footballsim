extends GdToolsTest


const PATHS: Array[String] = [
	"res://scripts/sim/match_engine_play.gd",
	"res://scripts/sim/strongest_xi.gd",
	"res://scripts/sim/match_engine_clock.gd",
	"res://scripts/sim/goal_vignette_ai.gd",
	"res://scripts/sim/match_engine_duels.gd",
	"res://scripts/ui/sheet_pointer.gd",
	"res://scripts/ui/app_shell_input.gd",
	"res://scripts/ui/team_select.gd",
]


func test_branch_headers_are_not_followed_by_a_blank_line() -> void:
	for path in PATHS:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s did not load" % path)
		var lines: PackedStringArray = text.split("\n")
		for i in range(lines.size()):
			var line: String = lines[i]
			if not _is_branch_header(line):
				continue
			assert_true(
				i + 1 < lines.size() and not str(lines[i + 1]).strip_edges().is_empty(),
				"%s:%d leaves a blank line under a branch header (coverage inject breaks)" % [path, i + 1]
			)


func _is_branch_header(line: String) -> bool:
	var t: String = line.strip_edges()
	if not t.ends_with(":"):
		return false
	return (
		t.begins_with("if ")
		or t.begins_with("elif ")
		or t == "else:"
		or t.begins_with("match ")
		or t.begins_with("for ")
		or t.begins_with("while ")
	)
