class_name LeagueRecord
extends RefCounted

## The season ledger inside one save: the calendar, the standings, the match
## reports and the Teams of Interest shortlist.
##
## Everything here talks to whichever database PLDatabase is bound to — the save
## — so the planner, the table screen and the encyclopedia all read one source.
## The old flat door (`record.fixtures()` and its siblings) now reads through
## the concern it belongs to: `record.fixtures.all()`, `record.standings.table()`.
## Each concern keeps its own module (`LeagueFixtures`, `LeagueStandings`,
## `LeagueReport`, `LeagueInterest`); this record composes them, installs a new
## season and turns one stored result into a report.

var save: LeagueSave = null
var fixtures: LeagueFixtures = null
var standings: LeagueStandings = null
var report: LeagueReport = null
## Teams of Interest inside this save (#104): the shortlist and its Watch rule.
var interest: LeagueInterest = null
## The goal clips stored beside the ledger (see `LeagueClips`).
var clips: LeagueClips = null

func _init(owner: LeagueSave) -> void:
	save = owner
	fixtures = LeagueFixtures.new(owner)
	standings = LeagueStandings.new(owner)
	report = LeagueReport.new(owner)
	interest = LeagueInterest.new(owner)
	clips = report.clips
