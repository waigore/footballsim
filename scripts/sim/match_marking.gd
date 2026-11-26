class_name MatchMarking
extends RefCounted

## The opposition `marking` instruction, read as the radius a defence picks a man
## up in (wiki Live tactics: `zonal` / `man`, "man-marking radius (30 m vs
## 26 m)"; consumption map: MatchAI shape / press / **marks**).
##
## One pure read so every place that answers "who does this defender pick up?"
## asks the same question of the same number. The instruction belongs to the
## **defending** side — it is an instruction about how that side marks the other
## one — so a caller passes the marker's own live style, never the carrier's.

const ZONAL := 26.0
const MAN := 30.0

## The pickup band for a side's live style. An unknown or absent instruction is
## the default `zonal`, so a fake or partial style still marks like a side that
## was never told otherwise.
static func band(style: Dictionary) -> float:
	return MAN if str(style.get("marking", "zonal")) == "man" else ZONAL
