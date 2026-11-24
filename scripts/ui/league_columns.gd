class_name LeagueColumns
extends RefCounted

## Column geometry for one row of the league table: the compact set the sheet
## paints on every platform — place number, club, played, goal difference,
## points.
##
## The place number and the club name sit on the left; P, GD and PTS are one
## right-aligned rail measured back from the row's own right edge. Deriving the
## rail from the width — instead of fixed X offsets — is what keeps all five
## compact columns inside a phone-sized sheet: once the handheld overlay scale
## shrinks the design viewport, fixed offsets bunch the numbers on the left while
## `PTS` floats out at the far right, and a full club name runs over `P` and
## `GD`.
##
## Kept beside `LeagueBook` rather than inside it: the book is already at its
## method budget, and this is pure arithmetic a headless test can pin.

## Table row indents: the place number, then the club name after the zone band.
const POS_INDENT := 10.0
const CLUB_INDENT := 32.0
## Width of one number box on the right-hand rail and the air between them.
const NUM_W := 26.0
const NUM_GAP := 10.0
## Never let the club column collapse to nothing on an absurdly narrow sheet.
const MIN_CLUB_W := 24.0

## Right edges for P, GD and PTS, the left edges of the place number and the
## club name, and the width the name may use before it has to be shortened.
static func of(row: Rect2) -> Dictionary:
	var pts_r := row.end.x - 10.0
	var gd_r := pts_r - NUM_W - NUM_GAP
	var p_r := gd_r - NUM_W - NUM_GAP
	var club_x := row.position.x + CLUB_INDENT
	return {
		"pos_x": row.position.x + POS_INDENT,
		"club_x": club_x,
		"club_w": maxf(p_r - NUM_W - NUM_GAP - club_x, MIN_CLUB_W),
		"p_r": p_r, "gd_r": gd_r, "pts_r": pts_r,
	}

## Longest prefix of `s` that fits `max_w` at `size`, with an ellipsis, so a
## club name that would run into the number rail is shortened instead of drawn
## over `P` and `GD`.
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
