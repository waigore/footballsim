class_name LeagueSave
extends RefCounted


const DEFAULT_DIR := "user://saves"
const EXT := ".sqlite"
const SCHEMA_VERSION := 18
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
	if not FileAccess.file_exists(PLDatabase.SEED_PATH):
		last_error = "the shipped seed is missing"
		return null
	DirAccess.make_dir_recursive_absolute(dir)
	var save := LeagueSave.new()
	save.slug = LeagueSaveCatalog.unique_slug(name)
	save.path = dir.path_join(save.slug + EXT)
	var bytes := FileAccess.get_file_as_bytes(PLDatabase.SEED_PATH)
	var out := FileAccess.open(save.path, FileAccess.WRITE)
	if out == null or bytes.is_empty():
		last_error = "cannot write %s" % save.path
		return null
	out.store_buffer(bytes)
	out.close()
	if not PLDatabase.open_path(save.path):
		last_error = "cannot open %s" % save.path
		return null
	LeagueSaveSchema.migrate()
	save.meta = {}
	save.put_meta("name", name.strip_edges() if name.strip_edges() != "" else "New League")
	save.put_meta("created_at", Time.get_datetime_string_from_system(true, true))
	save.put_meta("status", "in_progress")
	save.put_meta("seed", str(seed))
	save.put_meta("matchday", "1")
	save.put_meta("db_version", str(SCHEMA_VERSION))
	save.put_meta("season_index", "0")
	save.actives = LeagueSaveSchema.valid(competitions)
	save.put_meta("competitions", ",".join(PackedStringArray(save.actives)))
	for i in range(save.actives.size()):
		var cid := str(save.actives[i])
		PLDatabase.execute(
			"INSERT INTO save_competition (competition_id, active, position) VALUES (?, 1, ?) "
			+ "ON CONFLICT(competition_id) DO UPDATE SET active = 1, position = excluded.position;",
			[cid, i])
	var primary_rules := _rules_for_input(rules, str(save.actives[0]) if not save.actives.is_empty() else "PL")
	save.put_meta("calendar_mode", str(primary_rules["calendar_mode"]))
	save.put_meta("advance_mode", str(primary_rules["advance_mode"]))
	for cid in save.actives:
		LeagueRules.write(str(cid), _rules_for_input(rules, str(cid)))
	save.rules_by = LeagueRules.read_all()
	save.rules = save.rules_by.get(str(save.actives[0]), primary_rules)
	var season := PLDatabase.row("SELECT value FROM metadata WHERE key = 'season_label';")
	save.put_meta("season_label", str(season.get("value", "")))
	PLRepository.shared().invalidate()
	current = save
	return save


static func _rules_for_input(rules: Dictionary, competition_id: String) -> Dictionary:
	if rules.has("win_points") or rules.is_empty():
		var base := LeagueRules.defaults("generated", "fixture_days", competition_id)
		for key in rules.keys():
			if base.has(key):
				base[key] = rules[key]
		return LeagueRules.normalize(base)
	return LeagueRules.normalize(rules.get(competition_id, {}) as Dictionary)


static func open(slug_or_path: String) -> LeagueSave:
	last_error = ""
	var file := slug_or_path
	if not file.ends_with(EXT):
		file = dir.path_join(slug_or_path + EXT)
	if not FileAccess.file_exists(file):
		return null
	if not PLDatabase.open_path(file):
		return null
	var save := LeagueSave.new()
	save.path = file
	save.slug = file.get_file().trim_suffix(EXT)
	save.meta = save.read_meta()
	if save.meta.is_empty():
		PLDatabase.reset()
		return null
	if not save.theme_ready():
		last_error = NEW_SAVE_MESSAGE
		PLDatabase.reset()
		return null
	PLRepository.shared().invalidate()
	LeagueSaveSchema.migrate()
	save.actives = LeagueSaveSchema.valid(LeagueSaveSchema.active_from_disk())
	save.rules_by = LeagueRules.read_all()
	save.rules = save.rules_by.get(str(save.actives[0]), LeagueRules.read(str(save.actives[0])))
	LeagueSaveSchema.ensure_schema(save)
	current = save
	return save


static func close() -> void:
	if current != null and current.path == PLDatabase.current_path():
		PLDatabase.reset()
	current = null
	PLRepository.shared().invalidate()


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
