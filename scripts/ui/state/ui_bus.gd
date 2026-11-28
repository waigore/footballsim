class_name UiBus
extends RefCounted


signal session_changed
signal screen_changed(screen: String)
signal selection_changed(kind: String, id: String)
signal data_changed(scope: String)

var season: LeagueSeason = null
var screen := ""

static func make() -> UiBus:
	return UiBus.new()

func bind_season(target: LeagueSeason) -> void:
	if season == target:
		return
	unbind_season()
	season = target
	if season == null:
		return
	if not season.state_changed.is_connected(_on_season_state):
		season.state_changed.connect(_on_season_state)
	if not season.match_recorded.is_connected(_on_season_recorded):
		season.match_recorded.connect(_on_season_recorded)
	session_changed.emit()
	data_changed.emit("season")

func unbind_season() -> void:
	if season == null:
		return
	if season.state_changed.is_connected(_on_season_state):
		season.state_changed.disconnect(_on_season_state)
	if season.match_recorded.is_connected(_on_season_recorded):
		season.match_recorded.disconnect(_on_season_recorded)
	season = null
	data_changed.emit("season")

func bound() -> bool:
	return season != null

func announce_screen(next: String) -> void:
	if screen == next:
		return
	screen = next
	screen_changed.emit(screen)

func announce_selection(kind: String, id: String) -> void:
	selection_changed.emit(kind, id)

func announce(scope: String) -> void:
	data_changed.emit(scope)

func _on_season_state() -> void:
	data_changed.emit("season")

func _on_season_recorded(_report: Dictionary) -> void:
	session_changed.emit()
	data_changed.emit("match")
