class_name InterestPress
extends RefCounted

## A press that stays put on a team name for long enough becomes a long press
## (#107): the surface it lands on opens the Teams of Interest menu. The grammar
## is the same on every surface — a still press of `HOLD` seconds with less than
## `SLOP` of travel, never a press that turns into a scroll drag.
##
## Pure timing and travel, no input types: the sheets, the match HUD and the
## fixture picker each feed it their own events, so one clock rules every surface
## and a headless test can drive it by the delta alone.

## Seconds a press must stay put before it counts as a long press. Short taps
## never reach it, so the ordinary click of a name is unchanged.
const HOLD := 0.45
## Travel, in design units, that turns the press into a drag and cancels the hold.
const SLOP := 8.0

## The club the press started on, or "" when the press is not on a name at all.
var club := ""
## Where the press landed, in design space: the menu opens there.
var at := Vector2.ZERO
## A club name was under the press, so the release waits for the hold's verdict.
var watching := false
var fired := false
var moved := false
var elapsed := 0.0

## Start watching a press. `club_id` is the name under the point, or "" for
## anything else, which keeps the surface's press behaving exactly as before.
func press(point: Vector2, club_id: String) -> void:
	at = point
	club = club_id
	watching = club_id != ""
	fired = false
	moved = false
	elapsed = 0.0

## Still armed: the hold can still fire and the release is not a click yet.
func armed() -> bool:
	return watching and not fired and not moved

## Travel since the press. A drag cancels the hold and leaves the gesture to the
## scroll grammar; below the slop a shaky hand still counts as a hold.
func move(point: Vector2) -> void:
	if armed() and point.distance_to(at) > SLOP:
		moved = true

## Advance the clock. True on the frame the hold fires, once per press.
func tick(delta: float) -> bool:
	if not armed():
		return false
	elapsed += delta
	if elapsed < HOLD:
		return false
	fired = true
	return true

## The surface released the press. True when the release is still the surface's
## ordinary click: a press that never touched a club name, or a short tap that
## did. False when the hold owns the gesture (fired or dragged).
func release_click() -> bool:
	var click: bool = not watching or (not fired and not moved)
	clear()
	return click

## Forget the gesture (a pose change, a page swap, a fresh sheet).
func clear() -> void:
	club = ""
	watching = false
	fired = false
	moved = false
	elapsed = 0.0
