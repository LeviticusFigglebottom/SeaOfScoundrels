extends Node
## Headless test entry point:
##   godot --headless --path . res://tests/test_runner.tscn
## Optional filter:  -- --only=test_sea
## Exit code 0 on success, 1 on any failure.

func _ready() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") \
				and f != "test_case.gd" and f != "test_runner.gd":
			if only == "" or f.get_basename() == only:
				files.append(f)
	files.sort()
	var total := 0
	var failed: Array[String] = []
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			failed.append(f + ": failed to load")
			continue
		var tc: TestCase = script.new()
		add_child(tc)
		for m in script.get_script_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_"):
				continue
			total += 1
			tc._current = "%s::%s" % [f, mname]
			var before := tc.failures.size()
			await tc.call(mname)
			print("  [%s] %s" % ["ok" if tc.failures.size() == before else "FAIL", tc._current])
		failed.append_array(tc.failures)
		tc.queue_free()
		await get_tree().process_frame
	print("\n%d tests, %d failures" % [total, failed.size()])
	for msg in failed:
		printerr("FAIL " + msg)
	get_tree().quit(1 if failed.size() > 0 else 0)
