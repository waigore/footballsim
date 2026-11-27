class_name WikiNav
extends RefCounted


var entries: Array = []


func open(page: String, id: String) -> void:
	if not WikiModel.has_page(page, id):
		page = WikiModel.LEAGUE
		id = ""
	entries = [{"page": page, "id": id}]


func push(page: String, id: String) -> bool:
	if not WikiModel.has_page(page, id):
		return false
	if not entries.is_empty():
		var top: Dictionary = entries.back()
		if str(top["page"]) == page and str(top["id"]) == id:
			return false
	entries.append({"page": page, "id": id})
	return true


func back() -> bool:
	if entries.size() > 1:
		entries.pop_back()
		return true
	return false


func close() -> void:
	entries.clear()


func current() -> Dictionary:
	return entries.back() if not entries.is_empty() else {}


func is_open() -> bool:
	return not entries.is_empty()


func crumb_pages() -> Array:
	return entries.slice(0, maxi(entries.size() - 1, 0))


func truncate_to(crumb_index: int) -> void:
	entries = entries.slice(0, crumb_index + 1)
