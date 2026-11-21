extends SceneTree
func _init():
	for k in ProjectSettings.get_property_list():
		var n: String = k.get("name", "")
		if n.begins_with("debug/gdscript") or n.contains("warnings"):
			print(n, " = ", ProjectSettings.get_setting(n))
	quit()
