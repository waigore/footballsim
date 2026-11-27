class_name TestScratch
extends RefCounted


static func dir(name: String) -> String:
	return "user://%s_%d" % [name, OS.get_process_id()]


static func file(name: String) -> String:
	var ext := name.get_extension()
	if ext == "":
		return dir(name)
	return "user://%s_%d.%s" % [name.trim_suffix("." + ext), OS.get_process_id(), ext]


static func clear(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
