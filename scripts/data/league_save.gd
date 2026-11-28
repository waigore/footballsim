class_name LeagueSave
extends RefCounted


const DEFAULT_DIR := "user://saves"
const EXT := ".sqlite"
const SCHEMA_VERSION := 20
const NEW_SAVE_MESSAGE := "This save predates the transfer market. Start a new league."


static var dir := DEFAULT_DIR
static var current: LeagueSave = null

var slug := ""
var path := ""
var meta: Dictionary = {}


var rules: Dictionary = {}
var rules_by: Dictionary = {}

var actives: Array = []
static var last_error := ""


static func create(name: String, rules: Dictionary, seed: int = 0,
		competitions: Array = ["PL"]) -> LeagueSave:
	return LeagueSaveBoot.create(name, rules, seed, competitions)


static func open(slug_or_path: String) -> LeagueSave:
	return LeagueSaveBoot.open(slug_or_path)


static func close() -> void:
	LeagueSaveBoot.close()


func touch() -> bool:
	if not ensure_open():
		return false
	var stamp := Time.get_datetime_string_from_system(true, true)
	if not put_meta("saved_at", stamp):
		return false
	meta["saved_at"] = stamp
	return true


func write_copy(name: String) -> String:
	var typed := name.strip_edges()
	if typed == "" or not ensure_open():
		return ""
	var slug := LeagueSaveCatalog.slugify(typed)
	if slug == "" or slug == self.slug:
		return self.slug if touch() else ""
	DirAccess.make_dir_recursive_absolute(dir)
	var target := dir.path_join(slug + EXT)


	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	var out := FileAccess.open(target, FileAccess.WRITE)
	if out == null or bytes.is_empty():
		last_error = "cannot write %s" % target
		ensure_open()
		return ""
	out.store_buffer(bytes)
	out.close()
	var copy := open(target)
	if copy == null:
		ensure_open()
		return ""
	copy.put_meta("name", typed)
	copy.put_meta("saved_at", Time.get_datetime_string_from_system(true, true))

	ensure_open()
	current = self
	PLRepository.shared().invalidate()
	return slug


func ensure_open() -> bool:
	if PLDatabase.current_path() == path and PLDatabase.get_db() != null:
		return true
	if not PLDatabase.open_path(path):
		return false
	PLRepository.shared().invalidate()
	return true

func read_meta() -> Dictionary:
	if not ensure_open():
		return {}
	var out := {}
	for row in PLDatabase.rows("SELECT key, value FROM save_meta;"):
		out[str(row["key"])] = str(row["value"])
	return out

func put_meta(key: String, value: String) -> bool:
	if not ensure_open():
		return false
	var ok := PLDatabase.execute(
		"INSERT INTO save_meta (key, value) VALUES (?, ?) "
		+ "ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
		[key, value],
	)
	if ok:
		meta[key] = value
	return ok

func name() -> String:
	return str(meta.get("name", slug))


func theme_ready() -> bool:
	return meta.has("season_index")


func season_index() -> int:
	return int(str(meta.get("season_index", "0")))


func season_label() -> String:
	return str(meta.get("season_label", ""))


func set_season(index: int, label: String) -> bool:
	var ok := put_meta("season_index", str(maxi(index, 0)))
	return put_meta("season_label", label) and ok


func status() -> String:
	return str(meta.get("status", "in_progress"))

func set_status(value: String) -> void:
	put_meta("status", value)

func current_date() -> String:
	return str(meta.get("current_date", ""))

func set_date(value: String) -> bool:
	return put_meta("current_date", value)

func matchday() -> int:
	return int(meta.get("matchday", "1"))

func set_matchday(value: int) -> void:
	put_meta("matchday", str(maxi(value, 1)))


func competition_ids() -> Array:
	return actives.duplicate()


func rules_for(competition_id: String) -> Dictionary:
	if rules_by.has(competition_id):
		return rules_by[competition_id]
	return rules


func set_advance_mode(value: String) -> bool:
	var mode := value if LeagueRules.ADVANCE_MODES.has(value) else "fixture_days"
	var ok := true
	for cid in actives:
		var r := rules_for(str(cid)).duplicate(true)
		r["advance_mode"] = mode
		ok = LeagueRules.write(str(cid), r) and ok
		rules_by[str(cid)] = r
	rules = rules_for(str(actives[0])) if not actives.is_empty() else rules
	return put_meta("advance_mode", mode) and ok

func advance_mode() -> String:
	return str(meta.get("advance_mode", rules.get("advance_mode", "fixture_days")))

func reload() -> void:
	if not ensure_open():
		return
	meta = read_meta()
	actives = LeagueSaveSchema.valid(LeagueSaveSchema.active_from_disk())
	rules_by = LeagueRules.read_all()
	if not actives.is_empty():
		rules = rules_for(str(actives[0]))
