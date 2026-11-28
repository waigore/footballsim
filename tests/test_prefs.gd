extends GdToolsTest


var P := TestScratch.file("test_prefs_issue36.cfg")

func after_each() -> void:
	for path in [P, A]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_a_missing_file_falls_back_to_a_sensible_default() -> void:
	assert_false(FileAccess.file_exists(P), "the probe file should start absent")
	assert_almost_eq(Prefs.load_bgm(P), Prefs.DEFAULT_BGM, 0.0001, "a missing prefs file did not default")
	assert_between(Prefs.DEFAULT_BGM, 0.5, 1.0, "the default is not a mid-high level")

func test_volume_survives_a_save_and_load() -> void:
	assert_true(Prefs.save_bgm(0.42, P), "saving the volume failed")
	assert_almost_eq(Prefs.load_bgm(P), 0.42, 0.0001, "the saved volume did not load back")

func test_out_of_range_values_are_clamped() -> void:
	Prefs.save_bgm(3.0, P)
	assert_almost_eq(Prefs.load_bgm(P), 1.0, 0.0001, "a loud value was not clamped to 1.0")
	Prefs.save_bgm(-2.0, P)
	assert_almost_eq(Prefs.load_bgm(P), 0.0, 0.0001, "a negative value was not clamped to 0.0")
	assert_almost_eq(Prefs.clamp_volume(0.35), 0.35, 0.0001, "an in-range value was changed")

func test_zero_is_a_real_mute_and_persists() -> void:
	assert_true(Prefs.save_bgm(0.0, P), "saving mute failed")
	assert_almost_eq(Prefs.load_bgm(P), 0.0, 0.0001, "mute did not survive a relaunch")

func test_a_corrupt_file_does_not_take_the_menu_down() -> void:
	var f := FileAccess.open(P, FileAccess.WRITE)
	assert_not_null(f, "could not write the corrupt probe")
	f.store_string("this is not a config file\n")
	f.close()
	assert_almost_eq(Prefs.load_bgm(P), Prefs.DEFAULT_BGM, 0.0001, "a corrupt file did not default")

func test_a_wrong_value_type_falls_back() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(Prefs.SECTION, Prefs.KEY_BGM, "loud")
	assert_eq(cfg.save(P), OK, "could not write the type probe")
	assert_almost_eq(Prefs.load_bgm(P), Prefs.DEFAULT_BGM, 0.0001, "a string volume did not default")


var A := TestScratch.file("test_prefs_attrs_issue411.cfg")

func test_the_attribute_view_defaults_to_simplified() -> void:
	assert_eq(Prefs.load_attrs(A), "SIMPLIFIED", "a missing preference did not default to Simplified")
	assert_eq(Prefs.DEFAULT_ATTRS, "SIMPLIFIED", "the shipped default moved")

func test_the_attribute_view_survives_a_save_and_load() -> void:
	assert_true(Prefs.save_attrs("FULL", A), "saving the attribute view failed")
	assert_eq(Prefs.load_attrs(A), "FULL", "the Full view did not survive a relaunch")

func test_a_junk_attribute_view_falls_back_to_simplified() -> void:
	Prefs.save_attrs("TINY", A)
	assert_eq(Prefs.load_attrs(A), "SIMPLIFIED", "an unknown mode was not normalised")
	assert_eq(Prefs.normalize_attrs("full"), "SIMPLIFIED", "case folding invented a mode")
