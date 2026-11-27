class_name MatchMarking
extends RefCounted


const ZONAL := 26.0
const MAN := 30.0


static func band(style: Dictionary) -> float:
	return MAN if str(style.get("marking", "zonal")) == "man" else ZONAL
