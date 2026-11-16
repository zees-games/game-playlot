extends DotGameCheckSuite

const PlaygroundMapDrop := preload("../game/client/playground_map_drop.gd")

## Maps dropped on the window or the executable: PLAYLOT's documents (alone, in a folder, in a zip) are copied into
## the maps folder; anything else, a bad document or a taken id is refused with a line that says why.
##
## [codeblock]
## godot --headless --path . res://examples/headless_mapdrop.tscn
## [/codeblock]

const CHECKS := 21
const SECTIONS := 3
const ROOT := "user://headless_mapdrop"
const OUTSIDE := ROOT + "/outside"
const INTO := ROOT + "/maps"
const FIXTURE := "res://examples/fixtures/maps/pg_brushes.json"

var _entered := 0
var _finished := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.OFF)
	_run.call_deferred()


func _run() -> void:
	print("game-playground: dropped maps")
	_fixtures()
	_test_acceptor()
	_test_drop_args()
	await _test_intake()
	_wipe(ProjectSettings.globalize_path(ROOT))
	_report_sections(_entered, _finished, SECTIONS, CHECKS)


func _test_acceptor() -> void:
	_entered += 1
	var out := _outside()
	var none := func(_id: StringName) -> String: return ""
	var one := PlaygroundMapDrop.accept(out.path_join("brushes.json"), _into(), 3, none)
	_check(one.get("added", []).size() == 1 and (one["errors"] as PackedStringArray).is_empty(),
			"a map document is taken", str(one))
	_check(FileAccess.file_exists(_into().path_join("pg_brushes.json")), "it is copied to <id>.json")
	_check(PlaygroundMapDrop.accept(out.path_join("other.json"), _into(), 3, none).is_empty(),
			"a .json of another kind is not claimed")
	_check(PlaygroundMapDrop.accept(out.path_join("notes.txt"), _into(), 3, none).is_empty(), "a text file is not claimed")
	var deep := PlaygroundMapDrop.accept(out.path_join("pack"), _into(), 3, none)
	_check(deep.get("added", []).size() == 2, "a folder gives the documents two folders down", str(deep))
	_check(PlaygroundMapDrop.accept(out.path_join("pack"), _into(), 1, none).get("added", []).size() == 1,
			"search depth 1 reaches only the one a folder down")
	_check(PlaygroundMapDrop.accept(out.path_join("pack"), _into(), 0, none).get("added", []).size() == 2,
			"search depth 0 is no limit")
	var bad := PlaygroundMapDrop.accept(out.path_join("bad.json"), _into(), 3, none)
	var bad_errors: PackedStringArray = bad.get("errors", PackedStringArray())
	_check(bad.get("added", []).size() == 0 and bad_errors.size() == 1 and bad_errors[0].contains("identifier"),
			"a broken document is claimed and refused with the reason", str(bad))
	var taken := PlaygroundMapDrop.accept(out.path_join("brushes.json"), _into(), 3,
			func(id: StringName) -> String: return "%s is taken" % id)
	_check((taken.get("errors", PackedStringArray()) as PackedStringArray).has("brushes.json: pg_brushes is taken"),
			"a taken id is refused by name", str(taken))
	var zipped := PlaygroundMapDrop.accept(out.path_join("maps.zip"), _into(), 3, none)
	_check(zipped.get("added", []).size() == 2, "a zip of documents is taken", str(zipped))
	var broken := PlaygroundMapDrop.accept(out.path_join("broken.zip"), _into(), 3, none)
	_check((broken.get("errors", PackedStringArray()) as PackedStringArray).size() == 1, "an unreadable zip is an error", str(broken))
	_finished += 1


func _test_drop_args() -> void:
	_entered += 1
	var got := PlaygroundMapDrop.drop_args(PackedStringArray([
		"--pg-map", "pg_flatgrass", "--config", "/etc", "--dot_map.search", "/tmp", "--pg-x=1", "--offline", "/maps/a"]))
	_check(got == PackedStringArray(["--offline", "/maps/a"]), "config options and their values are not drops", str(got))
	var flag := PlaygroundMapDrop.drop_args(PackedStringArray(["--pg-fast", "--map-path=/x"]))
	_check(flag == PackedStringArray(["--map-path=/x"]), "an option followed by an option keeps the second", str(flag))
	_finished += 1


func _test_intake() -> void:
	_entered += 1
	var results: Array = []
	var holder := Node.new()
	add_child(holder)
	var intake := PlaygroundMapDrop.attach(holder, _into(), func(_id: StringName) -> String: return "",
			func(r: Dictionary) -> void: results.append(r))
	if not _check(intake != null, "the intake is attached on dot-map API 26"):
		holder.free()
		return
	_check(results.is_empty(), "a start with no paths handles nothing")
	var out := _outside()
	var refused: Dictionary = intake.call(&"handle", PackedStringArray([out.path_join("notes.txt")]), "window")
	var lines: PackedStringArray = load(PlaygroundMapDrop.INTAKE_SCRIPT).lines_for(refused)
	_check(lines.size() == 1 and lines[0].contains("notes.txt") and lines[0].contains(PlaygroundMapDrop.TAKES),
			"an unsupported drop says what was dropped and what PLAYLOT takes", str(lines))
	var taken: Dictionary = intake.call(&"handle", PackedStringArray([out.path_join("brushes.json")]), "window")
	_check(results.size() == 2, "each drop reaches the game")
	_check(load(PlaygroundMapDrop.INTAKE_SCRIPT).lines_for(taken) == PackedStringArray(["Added map: Brushes"]),
			"a taken map is announced by its name", str(taken))
	var exe: Dictionary = intake.call(&"take_cmdline", PackedStringArray(["--pg-map", "pg_flatgrass", out.path_join("pack")]), false)
	_check(str(exe.get("source", "")) == "command line" and exe.get("added", []).size() == 2,
			"a folder dropped on the executable is taken", str(exe))
	var missing: Dictionary = intake.call(&"take_cmdline", PackedStringArray(["--map-path=/no/such/map"]), false)
	_check((missing.get("errors", PackedStringArray()) as PackedStringArray).size() == 1, "a missing --map-path is an error")
	_check(str(intake.call(&"describe_lines")[1]).contains(PlaygroundMapDrop.TAKES), "describe_lines names what it takes")
	await get_tree().process_frame
	holder.free()
	_finished += 1


func _outside() -> String:
	return ProjectSettings.globalize_path(OUTSIDE)


func _into() -> String:
	return ProjectSettings.globalize_path(INTO)


## A document, one of another kind, a broken one, a text file, a folder with two documents two folders down, a zip
## of the same and a file that only says it is a zip.
func _fixtures() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	var out := _outside()
	var _m := DirAccess.make_dir_recursive_absolute(out.path_join("pack/a/b"))
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_write(out.path_join("brushes.json"), JSON.stringify(doc))
	_write(out.path_join("other.json"), JSON.stringify({"kind": "fc_map"}))
	var bad := doc.duplicate(true)
	bad["id"] = "not an id"
	_write(out.path_join("bad.json"), JSON.stringify(bad))
	_write(out.path_join("notes.txt"), "not a map")
	_write(out.path_join("broken.zip"), "not a zip")
	var docs := []
	for id in ["pgt_drop_one", "pgt_drop_two"]:
		var d := doc.duplicate(true)
		d["id"] = id
		docs.append(d)
	_write(out.path_join("pack/a/b/one.json"), JSON.stringify(docs[0]))
	_write(out.path_join("pack/a/two.json"), JSON.stringify(docs[1]))
	var zip := ZIPPacker.new()
	var _o := zip.open(out.path_join("maps.zip"))
	for k in docs.size():
		var _s := zip.start_file("maps/map%d.json" % k)
		var _w := zip.write_file(JSON.stringify(docs[k]).to_utf8_buffer())
		var _c := zip.close_file()
	var _z := zip.close()


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		var _s := f.store_string(text)
		f.close()


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		var _r := DirAccess.remove_absolute(dir.path_join(file))
	var _d := DirAccess.remove_absolute(dir)
