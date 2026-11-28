class_name LeagueSaveBoot
extends RefCounted


static func create(name: String, rules: Dictionary, seed: int = 0,
		competitions: Array = ["PL"]) -> LeagueSave:
	if not FileAccess.file_exists(PLDatabase.SEED_PATH):
		LeagueSave.last_error = "the shipped seed is missing"
		return null
	DirAccess.make_dir_recursive_absolute(LeagueSave.dir)
	var save := LeagueSave.new()
	save.slug = LeagueSaveCatalog.unique_slug(name)
	save.path = LeagueSave.dir.path_join(save.slug + LeagueSave.EXT)
	var bytes := FileAccess.get_file_as_bytes(PLDatabase.SEED_PATH)
	var out := FileAccess.open(save.path, FileAccess.WRITE)
	if out == null or bytes.is_empty():
		LeagueSave.last_error = "cannot write %s" % save.path
		return null
	out.store_buffer(bytes)
	out.close()
	if not PLDatabase.open_path(save.path):
		LeagueSave.last_error = "cannot open %s" % save.path
		return null
	LeagueSaveSchema.migrate()
	save.meta = {}
	save.put_meta("name", name.strip_edges() if name.strip_edges() != "" else "New League")
	save.put_meta("created_at", Time.get_datetime_string_from_system(true, true))
	save.put_meta("status", "in_progress")
	save.put_meta("seed", str(seed))
	save.put_meta("matchday", "1")
	save.put_meta("db_version", str(LeagueSave.SCHEMA_VERSION))
	save.put_meta("season_index", "0")
	save.actives = LeagueSaveSchema.valid(competitions)
	save.put_meta("competitions", ",".join(PackedStringArray(save.actives)))
	for i in range(save.actives.size()):
		var cid := str(save.actives[i])
		PLDatabase.execute(
			"INSERT INTO save_competition (competition_id, active, position) VALUES (?, 1, ?) "
			+ "ON CONFLICT(competition_id) DO UPDATE SET active = 1, position = excluded.position;",
			[cid, i])
	var primary_rules := _rules_for_input(rules,
		str(save.actives[0]) if not save.actives.is_empty() else "PL")
	save.put_meta("calendar_mode", str(primary_rules["calendar_mode"]))
	save.put_meta("advance_mode", str(primary_rules["advance_mode"]))
	for cid in save.actives:
		LeagueRules.write(str(cid), _rules_for_input(rules, str(cid)))
	save.rules_by = LeagueRules.read_all()
	save.rules = save.rules_by.get(str(save.actives[0]), primary_rules)
	var season := PLDatabase.row("SELECT value FROM metadata WHERE key = 'season_label';")
	save.put_meta("season_label", str(season.get("value", "")))
	PLRepository.shared().invalidate()
	LeagueSave.current = save
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
	LeagueSave.last_error = ""
	var file := slug_or_path
	if not file.ends_with(LeagueSave.EXT):
		file = LeagueSave.dir.path_join(slug_or_path + LeagueSave.EXT)
	if not FileAccess.file_exists(file):
		return null
	if not PLDatabase.open_path(file):
		return null
	var save := LeagueSave.new()
	save.path = file
	save.slug = file.get_file().trim_suffix(LeagueSave.EXT)
	save.meta = save.read_meta()
	if save.meta.is_empty():
		PLDatabase.reset()
		return null
	if not save.theme_ready():
		LeagueSave.last_error = LeagueSave.NEW_SAVE_MESSAGE
		PLDatabase.reset()
		return null
	PLRepository.shared().invalidate()
	LeagueSaveSchema.migrate()
	save.actives = LeagueSaveSchema.valid(LeagueSaveSchema.active_from_disk())
	save.rules_by = LeagueRules.read_all()
	save.rules = save.rules_by.get(str(save.actives[0]),
		LeagueRules.read(str(save.actives[0])))
	LeagueSaveSchema.ensure_schema(save)
	LeagueSave.current = save
	return save


static func close() -> void:
	if LeagueSave.current != null and LeagueSave.current.path == PLDatabase.current_path():
		PLDatabase.reset()
	LeagueSave.current = null
	PLRepository.shared().invalidate()
