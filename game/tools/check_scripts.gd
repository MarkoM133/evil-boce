extends SceneTree
## Loads every project script so parse errors (warnings are errors here) show up without
## opening the editor. GUT does not report them for scripts the tests never touch.
## godot_console --headless --path game -s res://tools/check_scripts.gd

const DIRS: Array[String] = ["res://rules", "res://sim", "res://data", "res://scenes", "res://ui", "res://tests", "res://tools"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bad: int = 0
	var total: int = 0
	for dir: String in DIRS:
		for path: String in _scripts(dir):
			total += 1
			var script: Script = load(path)
			if script == null or not script.can_instantiate() and not _is_tool_or_abstract(path):
				bad += 1
				print("FAILED  " + path)
	print("%d scripts checked, %d failed" % [total, bad])
	quit(1 if bad > 0 else 0)


## SceneTree scripts (tools) and GUT tests do not need instancing to count as compiled.
func _is_tool_or_abstract(path: String) -> bool:
	var script: GDScript = load(path)
	return script != null and script.reload() == OK


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return out
	for sub: String in d.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(_scripts(dir.path_join(sub)))
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
