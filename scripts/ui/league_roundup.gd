class_name LeagueRoundup
extends RefCounted

## A roundup row's scorer run: every goal of one fixture in minute order, each
## entry carrying the club that scored it (#125).
##
## The run mixes both sides' goals on one line, so — like the whistle card's
## phone rows (DR-20261125-04) — no column implies who a goal belongs to and the
## entry names its own club: `CRY 6' J. Mateta · MUN 23' M. Cunha`. A goal the
## row cannot fit is counted (`+2`) rather than dropped silently, the rule the
## cards use. Geometry and text only, no nodes: the book paints what this
## returns.

## Between two entries on the run.
const SEP := "  ·  "
## Prefix of the count that closes a run the row cannot hold.
const MORE := "  +%d"
## A roundup row with no goals in it.
const NONE := "no goals"

## The club abbreviation a goal belongs to, read off the fixture's own row: the
## fixture carries both clubs' labels, so no club lookup is needed to paint a
## result. An event whose club is neither side (a test row, an older save)
## contributes no prefix instead of a wrong one.
static func club_abbr(fixture: Dictionary, club_id: String) -> String:
	if club_id == "":
		return ""
	if club_id == str(fixture.get("home_club_id", "")):
		return str(fixture.get("home_abbr", ""))
	if club_id == str(fixture.get("away_club_id", "")):
		return str(fixture.get("away_abbr", ""))
	return ""

## A scorer's name as a report reads it. A penalty is marked on the name — the
## same shape the HUD gives an own goal — so a spot kick is visible without a
## column of its own, and a row with no name still reads as nothing.
static func name_of(e: Dictionary) -> String:
	var name := str(e.get("player_name", e.get("detail", "")))
	if bool(e.get("penalty", false)):
		return name + " (PEN)"
	return name

## One goal as the row reads it: `CRY 6' J. Mateta`.
static func entry(fixture: Dictionary, e: Dictionary) -> String:
	var name := name_of(e)
	var minute := int(e.get("minute", 0))
	var abbr := club_abbr(fixture, str(e.get("club_id", "")))
	if abbr == "":
		return "%d' %s" % [minute, name]
	return "%s %d' %s" % [abbr, minute, name]

## Every goal of the report in minute order, labelled with its club. The ledger
## already orders by minute (`LeagueRecord.events`); ties keep that order by
## row id, so a replayed report reads the same way twice.
static func entries(report: Dictionary) -> Array:
	var fixture: Dictionary = report.get("fixture", {})
	var goals: Array = []
	for e in report.get("events", []):
		if str(e.get("kind", "")) == "goal":
			goals.append(e)
	goals.sort_custom(_before)
	var out: Array = []
	for e in goals:
		out.append(entry(fixture, e))
	return out

static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ma := int(a.get("minute", 0))
	var mb := int(b.get("minute", 0))
	if ma != mb:
		return ma < mb
	return int(a.get("id", 0)) < int(b.get("id", 0))

## The run one row can hold, measured at the size it is really painted: entries
## are added while they fit beside the count, and the goals left over close the
## line as `+n`. One entry is shown even when it alone is too wide — a row that
## names its first scorer beats an empty caption.
static func run(report: Dictionary, font: Font, max_w: float, size: int) -> String:
	var all := entries(report)
	if all.is_empty():
		return ""
	var line := ""
	var shown := 0
	for i in range(all.size()):
		var candidate: String = str(all[i]) if shown == 0 else line + SEP + str(all[i])
		var tail := all.size() - i - 1
		if tail > 0:
			candidate += MORE % tail
		if shown > 0 and UiChrome.text_width(font, candidate, size) > max_w:
			break
		line = str(all[i]) if shown == 0 else line + SEP + str(all[i])
		shown += 1
	if shown < all.size():
		return line + MORE % (all.size() - shown)
	return line
