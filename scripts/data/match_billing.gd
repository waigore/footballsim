class_name MatchBilling
extends RefCounted

## What competition a match is being played in (#209): the briefing's caption,
## its desk blurb, the broadcast's fixture card and the opening team sheet all
## read this one answer, so one match can never be the Premier League on one
## line and a friendly on the next.
##
## The competition is the home club's own, as the file names it — never a
## hard-coded league — so the seed's single competition and a
## multi-competition file (#185) are named by the same rule. A match with no
## league fixture behind it (the fixture picker's KICK OFF) is a **friendly**,
## and a friendly has no matchday to announce.
##
## The names are resolved once, when the match is bound, off the repository's
## memoised club row: the overlay paints every frame and must not read the
## database per frame.

## The chrome's name for a match outside a league.
const FRIENDLY := "FRIENDLY"
## A friendly's briefing caption, in the header's grammar.
const FRIENDLY_CAPTION := "FRIENDLY · SINGLE MATCH"

## The competition id as the file carries it, empty for a friendly.
var competition_id := ""
## The competition in chrome caps, the full name in a sentence.
var short_name := ""
var full_name := ""
## The league round, 0 for a friendly.
var matchday := 0
var friendly := true
## A friendly has no league to name, so it names the sides' own competitions
## instead: two chrome names, mixed when the fixture crosses leagues (#187).
var home_short := ""
var away_short := ""

## Bind this match to the league fixture it plays. `home_id` names the club whose
## competition it is; an empty row leaves the match a friendly.
func bind_fixture(home_id: String, fixture: Dictionary, away_id: String = "") -> void:
	if fixture.is_empty():
		bind_friendly(home_id, away_id)
		return
	var club := TeamData.get_team(home_id)
	if club.is_empty():
		bind_friendly(home_id, away_id)
		return
	friendly = false
	competition_id = str(club.get("competition", ""))
	short_name = str(club.get("competition_short", competition_id))
	full_name = str(club.get("competition_name", short_name))
	matchday = maxi(int(fixture.get("matchday", 1)), 1)
	home_short = short_name
	away_short = ""

## The picker's match: no league, no round, no matchday copy. The sides' own
## competitions are kept so a fixture that crosses leagues can say so.
func bind_friendly(home_id: String = "", away_id: String = "") -> void:
	friendly = true
	competition_id = ""
	short_name = ""
	full_name = ""
	matchday = 0
	home_short = str(TeamData.get_team(home_id).get("competition_short", ""))
	away_short = str(TeamData.get_team(away_id).get("competition_short", ""))

## The competition in chrome caps: the briefing header, the broadcast's fixture
## card and the opening team sheet all print this.
func chrome_name() -> String:
	return FRIENDLY if friendly else short_name

## The competition in a sentence's grammar: "the Premier League", "a friendly".
func prose_name() -> String:
	return "a friendly" if friendly else "the " + full_name

## The briefing's caption: a friendly names the sides' competitions (both when
## the fixture crosses leagues), a league names its round.
func caption() -> String:
	if not friendly:
		return "%s · MATCHDAY %d" % [short_name, matchday]
	if home_short != "" and away_short != "" and home_short != away_short:
		return "FRIENDLY · %s v %s" % [home_short, away_short]
	return FRIENDLY_CAPTION

## Bind the match now about to be played to its competition (#209). Every way
## into a match calls this — a league Watch with its own fixture row, the picker
## with none — so no surface can name a different competition from another.
static func bind_scene(scene, home_id: String, fixture: Dictionary,
		away_id: String = "") -> MatchBilling:
	var binding = scene.get("billing") if scene != null else null
	if binding is MatchBilling:
		(binding as MatchBilling).bind_fixture(home_id, fixture, away_id)
		return binding as MatchBilling
	# A stand-in scene (a suite, a probe) carries no binding: build a throwaway
	# one so the caller still reads one consistent answer.
	var made := MatchBilling.new()
	made.bind_fixture(home_id, fixture, away_id)
	return made
