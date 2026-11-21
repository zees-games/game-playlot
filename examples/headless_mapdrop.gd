extends GSGameCheckSuite

const PlaylotMapDrop := preload("../game/client/playlot_map_drop.gd")
const PlaylotMapSources := preload("../game/client/playlot_map_sources.gd")
const PlaylotWorldMaps := preload("../game/playlot_world_maps.gd")

## Maps dropped on the window or the executable: PLAYLOT's documents (alone, in a folder, in a zip) are copied into
## the maps folder; anything else, a bad document or a taken id is refused with a line that says why. A Garry's Mod map
## (gm_fork's Workshop folder, its .bsp or .gma) is the PLAYLOT map converted from it (pgc_fork), or a refusal saying
## what to drop instead; the converted map knows its Garry's Mod name, which is what `pg_map gm_fork` finds.
##
## [codeblock]
## godot --headless --path . res://examples/headless_mapdrop.tscn
## [/codeblock]

const CHECKS := 35
const SECTIONS := 4
const ROOT := "user://headless_mapdrop"
const OUTSIDE := ROOT + "/outside"
const INTO := ROOT + "/maps"
const FIXTURE := "res://examples/fixtures/maps/pg_brushes.json"

var _entered := 0
var _finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.OFF)
	_run.call_deferred()


func _run() -> void:
	print("game-playlot: dropped maps")
	_fixtures()
	_test_acceptor()
	_test_drop_args()
	_test_source_maps()
	await _test_intake()
	_wipe(ProjectSettings.globalize_path(ROOT))
	_report_sections(_entered, _finished, SECTIONS, CHECKS)


func _test_acceptor() -> void:
	_entered += 1
	var out := _outside()
	var none := func(_id: StringName) -> String: return ""
	var one := PlaylotMapDrop.accept(out.path_join("brushes.json"), _into(), 3, none)
	_check(one.get("added", []).size() == 1 and (one["errors"] as PackedStringArray).is_empty(),
			"a map document is taken", str(one))
	_check(FileAccess.file_exists(_into().path_join("pg_brushes.json")), "it is copied to <id>.json")
	_check(PlaylotMapDrop.accept(out.path_join("other.json"), _into(), 3, none).is_empty(),
			"a .json of another kind is not claimed")
	var renamed := PlaylotMapDrop.accept(out.path_join("renamed.json"), _into(), 3, none)
	_check(renamed.get("added", []).size() == 1 and (renamed["errors"] as PackedStringArray).is_empty(),
			"a document of the Playlot kind is taken too, beside the former kind", str(renamed))
	_check(PlaylotMapDrop.accept(out.path_join("notes.txt"), _into(), 3, none).is_empty(), "a text file is not claimed")
	var deep := PlaylotMapDrop.accept(out.path_join("pack"), _into(), 3, none)
	_check(deep.get("added", []).size() == 2, "a folder gives the documents two folders down", str(deep))
	_check(PlaylotMapDrop.accept(out.path_join("pack"), _into(), 1, none).get("added", []).size() == 1,
			"search depth 1 reaches only the one a folder down")
	_check(PlaylotMapDrop.accept(out.path_join("pack"), _into(), 0, none).get("added", []).size() == 2,
			"search depth 0 is no limit")
	var bad := PlaylotMapDrop.accept(out.path_join("bad.json"), _into(), 3, none)
	var bad_errors: PackedStringArray = bad.get("errors", PackedStringArray())
	_check(bad.get("added", []).size() == 0 and bad_errors.size() == 1 and bad_errors[0].contains("identifier"),
			"a broken document is claimed and refused with the reason", str(bad))
	var taken := PlaylotMapDrop.accept(out.path_join("brushes.json"), _into(), 3,
			func(id: StringName) -> String: return "%s is taken" % id)
	_check((taken.get("errors", PackedStringArray()) as PackedStringArray).has("brushes.json: pg_brushes is taken"),
			"a taken id is refused by name", str(taken))
	var zipped := PlaylotMapDrop.accept(out.path_join("maps.zip"), _into(), 3, none)
	_check(zipped.get("added", []).size() == 2, "a zip of documents is taken", str(zipped))
	var broken := PlaylotMapDrop.accept(out.path_join("broken.zip"), _into(), 3, none)
	_check((broken.get("errors", PackedStringArray()) as PackedStringArray).size() == 1, "an unreadable zip is an error", str(broken))
	_finished += 1


func _test_source_maps() -> void:
	_entered += 1
	_check(PlaylotMapSources.name_of("/w/326332456_gm_fork.gma") == "gm_fork", "a Workshop .gma is named without its id")
	_check(PlaylotMapSources.name_of("C:/maps/GM_Fork.bsp") == "gm_fork", "a .bsp is named by its file, lower case")
	_check(PlaylotMapSources.source_of({"source_frame": {"map": "gm_fork.bsp"}}) == "gm_fork",
			"a converted document names its map by source_frame")
	_check(PlaylotMapSources.source_of({"attribution": "Geometry converted from gm_construct_small, https://x by Y."})
			== "gm_construct_small", "or by its attribution")
	_check(PlaylotMapSources.source_of({"attribution": "Built in PLAYLOT."}) == "", "a map made in PLAYLOT has none")
	var catalogue := GSMapCatalogue.new()
	var shelf := ProjectSettings.globalize_path(ROOT + "/shelf")
	var added := PlaylotWorldMaps.add_map_docs(catalogue, shelf)
	var fork := catalogue.get_map(&"pgt_fork")
	_check(added == 1 and fork != null and str(fork.meta.get("source_map", "")) == "gm_fork",
			"a loaded document keeps its Garry's Mod name", str(fork.meta if fork != null else {}))
	_check(PlaylotMapSources.find(catalogue, "gm_fork") == fork and PlaylotMapSources.find(catalogue, "GM_FORK.bsp") == fork,
			"pg_map's alias: gm_fork finds the converted map")
	_check(PlaylotMapSources.find(catalogue, "gm_other") == null, "a map with no conversion finds nothing")
	var converted := func(source: String) -> Dictionary:
		var map := PlaylotMapSources.find(catalogue, source)
		return {} if map == null else {"id": map.id, "title": map.name_or_id()}
	var out := _outside()
	var folder := PlaylotMapDrop.accept(out.path_join("gm_fork"), _into(), 3, func(_id: StringName) -> String: return "", converted)
	var got: Array = folder.get("added", [])
	_check(got.size() == 1 and got[0]["id"] == &"pgt_fork" and got[0]["source_map"] == "gm_fork"
			and (folder["errors"] as PackedStringArray).is_empty(), "a dropped gm_fork Workshop folder is the converted map", str(folder))
	_check(not FileAccess.file_exists(_into().path_join("pgt_fork.json")), "and nothing is copied for it")
	var gma := PlaylotMapDrop.accept(out.path_join("326332456_gm_fork.gma"), _into(), 3, func(_id: StringName) -> String: return "", converted)
	_check(gma.get("added", []).size() == 1, "so is its .gma", str(gma))
	var other := PlaylotMapDrop.accept(out.path_join("gm_other.bsp"), _into(), 3, func(_id: StringName) -> String: return "", converted)
	var why: PackedStringArray = other.get("errors", PackedStringArray())
	_check(other.get("added", []).size() == 0 and why.size() == 1 and why[0].begins_with("gm_other: a Garry's Mod")
			and why[0].contains(".json converted from it"), "a .bsp with no conversion is refused saying what to drop", str(other))
	_finished += 1


func _test_drop_args() -> void:
	_entered += 1
	var got := PlaylotMapDrop.drop_args(PackedStringArray([
		"--pg-map", "pg_flatgrass", "--config", "/etc", "--dot_map.search", "/tmp", "--pg-x=1", "--offline", "/maps/a"]))
	_check(got == PackedStringArray(["--offline", "/maps/a"]), "config options and their values are not drops", str(got))
	var flag := PlaylotMapDrop.drop_args(PackedStringArray(["--pg-fast", "--map-path=/x"]))
	_check(flag == PackedStringArray(["--map-path=/x"]), "an option followed by an option keeps the second", str(flag))
	_finished += 1


func _test_intake() -> void:
	_entered += 1
	var results: Array = []
	var holder := Node.new()
	add_child(holder)
	var intake := PlaylotMapDrop.attach(holder, _into(), func(_id: StringName) -> String: return "",
			func(r: Dictionary) -> void: results.append(r))
	if not _check(intake != null, "the intake is attached on dot-map API 26"):
		holder.free()
		return
	_check(results.is_empty(), "a start with no paths handles nothing")
	var out := _outside()
	var refused: Dictionary = intake.call(&"handle", PackedStringArray([out.path_join("notes.txt")]), "window")
	var lines: PackedStringArray = load(PlaylotMapDrop.INTAKE_SCRIPT).lines_for(refused)
	_check(lines.size() == 1 and lines[0].contains("notes.txt") and lines[0].contains(PlaylotMapDrop.TAKES),
			"an unsupported drop says what was dropped and what PLAYLOT takes", str(lines))
	var taken: Dictionary = intake.call(&"handle", PackedStringArray([out.path_join("brushes.json")]), "window")
	_check(results.size() == 2, "each drop reaches the game")
	_check(load(PlaylotMapDrop.INTAKE_SCRIPT).lines_for(taken) == PackedStringArray(["Added map: Brushes"]),
			"a taken map is announced by its name", str(taken))
	var exe: Dictionary = intake.call(&"take_cmdline", PackedStringArray(["--pg-map", "pg_flatgrass", out.path_join("pack")]), false)
	_check(str(exe.get("source", "")) == "command line" and exe.get("added", []).size() == 2,
			"a folder dropped on the executable is taken", str(exe))
	var missing: Dictionary = intake.call(&"take_cmdline", PackedStringArray(["--map-path=/no/such/map"]), false)
	_check((missing.get("errors", PackedStringArray()) as PackedStringArray).size() == 1, "a missing --map-path is an error")
	_check(str(intake.call(&"describe_lines")[1]).contains(PlaylotMapDrop.TAKES), "describe_lines names what it takes")
	var bsp: Dictionary = intake.call(&"handle", PackedStringArray([out.path_join("gm_other.bsp")]), "window")
	var bsp_lines: PackedStringArray = load(PlaylotMapDrop.INTAKE_SCRIPT).lines_for(bsp)
	_check(bsp_lines.size() == 1 and bsp_lines[0].begins_with("Cannot load gm_other: a Garry's Mod (Source engine) map"),
			"through the intake a dropped .bsp says plainly it is a Garry's Mod map", str(bsp_lines))
	await get_tree().process_frame
	holder.free()
	_finished += 1


func _outside() -> String:
	return ProjectSettings.globalize_path(OUTSIDE)


func _into() -> String:
	return ProjectSettings.globalize_path(INTO)


## A document, one of another kind, a broken one, a text file, a folder with two documents two folders down, a zip
## of the same, a file that only says it is a zip, gm_fork's Workshop folder and .gma, a .bsp PLAYLOT has no conversion
## of, and a shelf with a document converted from gm_fork.
func _fixtures() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))
	var out := _outside()
	var _m := DirAccess.make_dir_recursive_absolute(out.path_join("pack/a/b"))
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_write(out.path_join("brushes.json"), JSON.stringify(doc))
	_write(out.path_join("other.json"), JSON.stringify({"kind": "fc_map"}))
	var renamed := doc.duplicate(true)
	renamed["id"] = "pgt_drop_renamed"
	renamed["kind"] = "playlot_map"
	_write(out.path_join("renamed.json"), JSON.stringify(renamed))
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
	var _g := DirAccess.make_dir_recursive_absolute(out.path_join("gm_fork/maps"))
	_write(out.path_join("gm_fork/addon.json"), JSON.stringify({"title": "gm_fork", "type": "map"}))
	_write(out.path_join("gm_fork/maps/gm_fork.bsp"), "VBSP")
	_write(out.path_join("326332456_gm_fork.gma"), "GMAD")
	_write(out.path_join("gm_other.bsp"), "VBSP")
	var shelf := ProjectSettings.globalize_path(ROOT + "/shelf")
	var _s := DirAccess.make_dir_recursive_absolute(shelf)
	var fork := doc.duplicate(true)
	fork["id"] = "pgt_fork"
	fork["source_frame"] = {"map": "gm_fork.bsp"}
	_write(shelf.path_join("pgt_fork.json"), JSON.stringify(fork))


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
