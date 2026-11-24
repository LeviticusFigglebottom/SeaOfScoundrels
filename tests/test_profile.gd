extends TestCase

const PATH := "user://test_profile.json"

func test_roundtrip() -> void:
	var p := Profile.new()
	p.add_gold(350)
	check(p.spend_gold(100))
	check(not p.spend_gold(1000), "cannot overspend")
	p.add_renown("chartwrights", 5)
	p.unlock("hull_stout")
	check(p.discover("gull_rock"))
	check(not p.discover("gull_rock"), "second discovery is not new")
	p.bump_stat("chests_sold")
	check_eq(p.save(PATH), OK)
	var q := Profile.new()
	check(q.load_from(PATH))
	check_eq(int(q.data["gold"]), 250)
	check_eq(int(q.data["renown"]["chartwrights"]), 5)
	check(q.has_unlock("hull_stout"))
	check_eq(int(q.data["stats"]["chests_sold"]), 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func test_old_and_corrupt_files() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string('{"gold": 12, "future_key": [1,2]}')
	f.close()
	var p := Profile.new()
	check(p.load_from(PATH))
	check_eq(int(p.data["gold"]), 12)
	check(p.data.has("stats"), "missing keys take defaults")
	check(p.data.has("future_key"), "unknown keys are preserved")
	f = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("not json {")
	f.close()
	var q := Profile.new()
	check(not q.load_from(PATH))
	check_eq(int(q.data["gold"]), 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
