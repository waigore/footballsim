class_name MatchCadence
extends RefCounted

## How often a dugout may act: the law's floor under a tactical change, and the
## manager's own `patience` read on top of it (wiki Match AI: "how long he waits
## between tactical changes", `ManagerData.profile`).
##
## Pure reads over plain values — a profile dictionary and a clock gap — so the
## rule is pinned directly and the manager loop keeps no branch per profile
## field. Split out of `MatchManager` for the P3 size budget, the same way
## `MatchRestarts` holds the taker's dead-ball judgement.

## The law's floor: at least seven minutes between changes (wiki Match AI), and
## the wait the league's default manager takes. A more patient hand buys more;
## a less patient one cannot legally act sooner than the floor.
const MIN_GAP := 420.0

## The league's neutral `patience` (the shipped mean). This is the point at
## which the wait is exactly the seven-minute floor, so a default side plays the
## match it always played and no club is asked to break the law.
const NEUTRAL_PATIENCE := 0.52

## How far a manager's `patience` stretches the wait above the floor. At this
## slope the most patient shipped profile (0.66) waits ~1.4x the floor, which is
## worth about a third of a change a side over a season of matches.
##
## The slope was measured, not guessed: `tools/patience_clubs.gd` replays the
## same seeded timelines per club and counts the changes each profile makes. The
## shipped spread (0.40–0.66) runs from 2.16 to 1.69 changes a side; a steeper
## slope (6.0) pushed the patient end to 1.36, below the 2–3 band the product
## asks for, so it was rejected.
const SPAN := 3.0

## How long this manager waits between tactical changes. Patience below the
## neutral value buys nothing — the floor already forbids acting sooner — so at
## the shipped spread the waits run 420 s up to about 600 s.
static func tactics_gap(profile: Dictionary) -> float:
	var patience := clampf(float(profile.get("patience", NEUTRAL_PATIENCE)), 0.0, 1.0)
	return MIN_GAP * (1.0 + maxf(0.0, patience - NEUTRAL_PATIENCE) * SPAN)

## Has this manager's wait since his last change elapsed?
static func may_change(profile: Dictionary, since_last: float) -> bool:
	return since_last >= tactics_gap(profile)
