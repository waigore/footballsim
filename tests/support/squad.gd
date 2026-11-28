class_name TestSquad
extends RefCounted


static func id_of(club_id: String, name: String) -> String:
	return str(PLRepository.shared().player_by_name(club_id, name).get("id", ""))


static func none() -> String:
	return "00000000-0000-4000-8000-000000000000"
