class_name LeagueRecord
extends RefCounted


var save: LeagueSave = null
var fixtures: LeagueFixtures = null
var standings: LeagueStandings = null
var report: LeagueReport = null

var interest: LeagueInterest = null

var clips: LeagueClips = null

func _init(owner: LeagueSave) -> void:
	save = owner
	fixtures = LeagueFixtures.new(owner)
	standings = LeagueStandings.new(owner)
	report = LeagueReport.new(owner)
	interest = LeagueInterest.new(owner)
	clips = report.clips
