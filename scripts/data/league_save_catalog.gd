class_name LeagueSaveCatalog
extends RefCounted

## The save directory as a catalogue: naming, listing and deleting the files
## beside the season a player has open. Split out of `LeagueSave` so the storage
## class keeps one concern and stays inside its size budget.
##
## Listing reads only `save_meta` from each file, so it never disturbs the
## connection a running season is using.

static func slugify(name: String) -> String:
	var out := ""
	var last_dash := true
	for i in range(name.length()):
		var ch := name.substr(i, 1).to_lower()
		var ok := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		if ok:
			out += ch
			last_dash = false
		elif not last_dash:
			out += "-"
			last_dash = true
	return out.strip_edges().trim_suffix("-")

static func unique_slug(base: String) -> String:
	var stem := slugify(base)
	if stem == "":
		stem = "league"
	var candidate := stem
	var n := 2
	while FileAccess.file_exists(LeagueSave.dir.path_join(candidate + LeagueSave.EXT)):
		candidate = "%s-%d" % [stem, n]
		n += 1
	return candidate

## Every save on disk, newest first.
static func list() -> Array:
	var out: Array = []
	DirAccess.make_dir_recursive_absolute(LeagueSave.dir)
	for name in DirAccess.get_files_at(LeagueSave.dir):
		if not name.ends_with(LeagueSave.EXT):
			continue
		var file := LeagueSave.dir.path_join(name)
		var info := _peek(file)
		if info.is_empty():
			continue
		out.append({
			"slug": name.trim_suffix(LeagueSave.EXT),
			"path": file,
			"name": str(info.get("name", name)),
			"status": str(info.get("status", "in_progress")),
			"current_date": str(info.get("current_date", "")),
			"matchday": int(info.get("matchday", 1)),
			"competitions": str(info.get("competitions", "PL")),
			"modified": FileAccess.get_modified_time(file),
		})
	out.sort_custom(func(a, b): return int(a["modified"]) > int(b["modified"]))
	return out

static func _peek(file: String) -> Dictionary:
	var db := SQLite.new()
	db.path = file
	if not db.open_db():
		return {}
	var out := {}
	if db.query("SELECT key, value FROM save_meta;"):
		for row in db.query_result:
			out[str(row["key"])] = str(row["value"])
	db.close_db()
	return out

static func remove(slug: String) -> bool:
	var file := LeagueSave.dir.path_join(slug + LeagueSave.EXT)
	if not FileAccess.file_exists(file):
		return false
	if PLDatabase.current_path() == file:
		LeagueSave.close()
	PLRepository.shared().invalidate()
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(file)) == OK
