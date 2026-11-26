class_name LeagueColumns
extends RefCounted

## Column geometry for one row of the league table: the compact set the table
## sheet and the hub side table paint — place, club, and the whole overall
## record (P W D L GF GA GD PTS).
##
## The place number and the club name sit on the left; the number boxes ride one
## right-aligned rail measured back from the row's own right edge. Deriving the
## rail from the width — instead of fixed X offsets — is what keeps every
## compact column inside a phone-sized sheet: once the handheld overlay scale
## shrinks the design viewport, fixed offsets bunch the numbers on the left while
## `PTS` floats out at the far right, and a full club name runs over the record.
##
## The rail tightens before the club column is starved: eight boxes at their
## preferred width only fit a desktop sheet, so on a phone the boxes and the air
## between them give way first, down to a floor where `PTS` and a signed goal
## difference still fit. That keeps Compact readable on a landscape phone
## instead of needing a sideways pan for its own default reading.
##
## Its own module, not a helper inside a sheet: the hub's side table, the table
## and the report all read one rail, and this is pure arithmetic a headless test
## can pin.

## The compact reading, in paint order: the place, the club, then the whole
## overall record. Full adds the home and away splits on top of these.
const COMPACT_COLS := [
	{"key": "position", "label": "#", "num": false},
	{"key": "club", "label": "CLUB", "num": false},
	{"key": "played", "label": "P", "num": true},
	{"key": "won", "label": "W", "num": true},
	{"key": "drawn", "label": "D", "num": true},
	{"key": "lost", "label": "L", "num": true},
	{"key": "gf", "label": "GF", "num": true},
	{"key": "ga", "label": "GA", "num": true},
	{"key": "gd", "label": "GD", "num": true},
	{"key": "points", "label": "PTS", "num": true},
]

## Table row indents: the place number, then the club name after the zone band.
const POS_INDENT := 10.0
const CLUB_INDENT := 32.0
## One number box at its preferred width and the air between two of them.
const NUM_W := 26.0
const NUM_GAP := 10.0
## What the rail tightens to on a narrow sheet: a box still holds `PTS` and a
## signed goal difference at the sheet's number size.
const MIN_NUM_W := 18.0
const MIN_GAP := 4.0
## Air between the last number and the row's right edge.
const TAIL := 10.0
## The club column keeps at least this much. A sheet that shows the full club
## name needs more of it than one that shows the three-letter abbreviation.
const MIN_CLUB_W := 100.0
## The club column's share of the row, capped so a very wide sheet does not
## leave the record bunched at the far right behind a mostly empty name column.
const CLUB_SHARE := 0.42
const MAX_CLUB_W := 460.0

## The number boxes of `cols`, in paint order.
static func numbers(cols: Array) -> Array:
	var out: Array = []
	for col in cols:
		if bool(col["num"]):
			out.append(col)
	return out

## The narrowest row that still shows the whole record without a sideways pan:
## the rail at its floor and the club column at its floor.
static func min_row(cols: Array, club_min: float = MIN_CLUB_W) -> float:
	var n := float(maxi(numbers(cols).size(), 1))
	return CLUB_INDENT + club_min + n * (MIN_NUM_W + MIN_GAP) + TAIL

## Right edges for the number boxes of `cols`, the left edges of the place
## number and the club name, and the width the name may use before it has to be
## shortened.
##
## The club column takes its share of the row and the number boxes spread evenly
## over the rest, so all eight of them share the width instead of crowding a
## short rail and leaving a dead gap before `PTS`. Where the row is narrow the
## air goes first, then the boxes, both down to a floor where `PTS` and a signed
## goal difference still sit inside their box — and below that floor the sheet
## pans rather than squeezing the columns.
##
## `club_min` / `club_share` let a caller that paints the abbreviation instead
## of the name keep a much smaller name column (the hub's side table).
static func of(row: Rect2, cols: Array, club_min: float = MIN_CLUB_W,
		club_share: float = CLUB_SHARE) -> Dictionary:
	var boxes := numbers(cols)
	var club_x := row.position.x + CLUB_INDENT
	var right := row.end.x - TAIL
	var n := float(maxi(boxes.size(), 1))
	var room := right - club_x
	var floor_pitch := MIN_NUM_W + MIN_GAP
	var club_w := clampf(room * club_share, club_min, MAX_CLUB_W)
	club_w = minf(club_w, maxf(room - n * floor_pitch, club_min))
	var pitch := maxf((room - club_w) / n, floor_pitch)
	var gap := clampf(pitch - NUM_W, MIN_GAP, NUM_GAP)
	var w := pitch - gap
	var rail: Array = []
	for i in range(boxes.size()):
		var col: Dictionary = boxes[i]
		rail.append({
			"key": str(col["key"]), "label": str(col["label"]),
			"right": right - float(boxes.size() - 1 - i) * pitch, "w": w,
		})
	return {
		"pos_x": row.position.x + POS_INDENT,
		"club_x": club_x,
		"club_w": club_w,
		"cols": rail,
	}

## A cell's text: goal difference is signed, everything else is a count.
static func text(row: Dictionary, key: String) -> String:
	if key == "gd":
		return "%+d" % (int(row.get("gf", 0)) - int(row.get("ga", 0)))
	return "%d" % int(row.get(key, 0))

## Longest prefix of `s` that fits `max_w` at `size`, with an ellipsis, so a
## club name that would run into the number rail is shortened instead of drawn
## over the record.
static func fit_name(s: String, font: Font, size: int, max_w: float) -> String:
	if font == null or max_w <= 0.0:
		return s
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return s
	var cut := s
	while cut.length() > 1:
		cut = cut.substr(0, cut.length() - 1).strip_edges()
		var probe := cut + "…"
		if font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			return probe
	return "…"

## A caption for a narrow column: the string itself when `room` holds it, or the
## shortened form when it does not — a venue name between two club cards must
## never run over the cards it sits between (#200). No room means no caption,
## never a word painted past the column's edge. Pure, so a suite can pin it.
static func fit_caption(s: String, font: Font, size: int, room: float) -> String:
	if s == "" or room <= 0.0:
		return ""
	return fit_name(s, font, ChromeDensity.read_size(size), room)
