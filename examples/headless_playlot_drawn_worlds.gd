extends "res://examples/headless_playlot_vehicles.gd"

## Every hand-built map, swept for closed slots and ground no spawn reaches or that leads nowhere (`[gate-sweep-2]`).
##
## The survey is asked about a fixture first, so a sweep that finds nothing is known to be looking.
var _tmas_data_script: GDScript
## The four survey checks of each unedited map, which is loaded but not surveyed; `_ready` takes them
## off the expected total, so the count follows the documents the maps repository holds.
var _tmas_unsurveyed_checks := 0


func _test_the_maps_are_surveyed_2() -> void:
	for id in CUSTOM_MAPS:
		var path := "res://maps/custom/%s.json" % id
		var map: Node3D = _tmas_data_script.new()
		var configured: GSResult = map.configure_doc(path)
		_check(configured.ok, "%s: the document loads" % id, str(configured.error) if not configured.ok else "")
		# A whole-map import (`"unedited": true`, written by the converter) is the author's map as built for Garry's
		# Mod, not a course laid out for this game's player: its ledges and slots are the author's, and a survey of a
		# whole Source map runs for minutes. It is shown as imported, so only the load is checked.
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if doc is Dictionary and GSValue.same((doc as Dictionary).get("unedited", false), true):
			map.free()
			print("    %s: an unedited whole-map import, not surveyed" % id)
			_tmas_unsurveyed_checks += 4
			continue
		var spawns: Array[Vector3] = [map.fallback_spawn]
		var declared: Array = map.survey_declared()
		var started := Time.get_ticks_msec()
		var found: Dictionary = PlaylotMapSurvey.survey(map, [], spawns, declared)
		map.free()
		print("    %s: %d standable cells in %d regions, %d declared, %d falls into nothing, %d ms" % [
			id, int(found["cells"]), int(found["regions"]), declared.size(),
			int(found["void_falls"]), Time.get_ticks_msec() - started,
		])
		_check((found["spawnless"] as Array).is_empty(), "%s: the spawn stands on standable ground" % id,
			", ".join(found["spawnless"]))
		_check((found["slots"] as Array).is_empty(), "%s: no slot narrower than a player" % id,
			"; ".join(found["slots"]))
		_check((found["unreached"] as Array).is_empty(), "%s: nothing standable out of reach, but what it declares" % id,
			"; ".join(found["unreached"]))
		_check((found["trapped"] as Array).is_empty(), "%s: and no place with no way out" % id,
			"; ".join(found["trapped"]))

	_brush_documents()
	_done()


## A document with brushes saved and read back: it validates, builds a mesh and convex collision
## per brush, and a bad brush kind or a liquid brush is refused whole.
func _brush_documents() -> void:
	var text := FileAccess.get_file_as_string("res://examples/fixtures/maps/pg_brushes.json")
	var doc: Variant = JSON.parse_string(text)
	var path := "user://pg_brushes_roundtrip.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	var map: Node3D = _tmas_data_script.new()
	var configured: GSResult = map.configure_doc(path)
	_check(configured.ok, "brushes: a saved and re-read document loads", str(configured.error) if not configured.ok else "")
	var kinds: Array[String] = []
	var convex := 0
	var meshes := 0
	for n in map.get_children():
		if n is StaticBody3D and n.has_meta(GSMapBrush.META_KIND):
			kinds.append(str(n.get_meta(GSMapBrush.META_KIND)))
			for c in n.get_children():
				if c is CollisionShape3D and (c as CollisionShape3D).shape is ConvexPolygonShape3D:
					convex += 1
				if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
					meshes += 1
			_check(PlaylotMaterials.material_of(n) != &"" and n.has_meta(&"pg_box"),
				"brushes: %s carries its material and box index" % kinds[-1])
	kinds.sort()
	_check(kinds == ["arch", "stairs", "wedge"], "brushes: stairs, wedge and arch are built", str(kinds))
	_check(convex >= 3 and meshes == 3, "brushes: each has convex collision and a mesh", "%d convex, %d meshes" % [convex, meshes])
	map.free()
	var bad: Dictionary = (doc as Dictionary).duplicate(true)
	bad["boxes"][1]["brush"] = "teapot"
	_check(not _tmas_data_script.call("validate", bad).ok, "brushes: an unknown brush kind refuses the document")
	bad = (doc as Dictionary).duplicate(true)
	bad["boxes"][1]["material"] = "water"
	_check(not _tmas_data_script.call("validate", bad).ok, "brushes: a liquid brush refuses the document")
	DirAccess.remove_absolute(path)


# A map drawn from its converted world pack

const WORLD_FIXTURE := "res://examples/fixtures/world_map"


## A document naming a converted world pack (gs-map's mesh fixture, copied): a drawing map lays the pack over its boxes,
## hides every opaque box and brush mesh and keeps their collision, and leaves glass and water drawn. A server draws nothing;
## a pack that is missing or made at another scale leaves the boxes drawn; a bad `world` refuses the document.
func _test_drawn_worlds() -> void:
	_section("a map drawn from its converted world pack")
	var doc_path := WORLD_FIXTURE + "/pg_world.json"

	var server: Node3D = _tmas_data_script.new()
	server.draw_world = false
	add_child(server)
	server.configure_doc(doc_path)
	await get_tree().process_frame
	_check(server.get_node_or_null(^"World") == null and server.drawn_world == null and _hidden_box_meshes(server) == 0,
		"world: a map that does not draw reads no pack and keeps its boxes drawn")
	_check(not server._shades_boxes(), "world: a server builds no contact shade for a map its pack would draw",
		"gm_fork's 21,329 boxes spent two minutes in it")
	server.queue_free()

	var map: Node3D = _tmas_data_script.new()
	map.draw_world = true
	add_child(map)
	var configured: GSResult = map.configure_doc(doc_path)
	var guard := 300
	while map.drawn_world == null and map._world_loading and guard > 0:
		await get_tree().process_frame
		guard -= 1
	_check(configured.ok and map.drawn_world != null and map.get_node_or_null(^"World") != null,
		"world: the pack is drawn under the map", str(configured.error) if not configured.ok else "%d frames left" % guard)
	var bodies := 0
	var shapes := 0
	for child in map.get_children():
		if child is StaticBody3D and child.has_meta(&"pg_box"):
			bodies += 1
			for part in child.get_children():
				if part is CollisionShape3D and not (part as CollisionShape3D).disabled:
					shapes += 1
					break
	_check(_hidden_box_meshes(map) == 2, "world: the floor and the wedge are drawn by the pack, not as boxes",
		"%d box meshes hidden" % _hidden_box_meshes(map))
	_check(bodies == 3 and shapes == 3, "world: every box and brush still collides", "%d bodies, %d with a shape" % [bodies, shapes])
	var glass_drawn := false
	for child in map.get_children():
		if child is StaticBody3D and PlaylotMaterials.material_of(child) == &"glass":
			for part in child.get_children():
				glass_drawn = glass_drawn or (part is GeometryInstance3D and (part as GeometryInstance3D).visible)
	var water := map.get_node_or_null(^"Liquid3") as GeometryInstance3D
	_check(glass_drawn and water != null and water.visible and map.get_node_or_null(^"ContactShade") == null,
		"world: glass and water stay drawn, the boxes' contact shade goes")
	map.queue_free()

	var text := FileAccess.get_file_as_string(doc_path)
	await _check_unusable_packs(text, doc_path)
	_check_world_specs(text)
	await get_tree().process_frame
	_done()


## A document whose pack is missing, or made at another scale, is refused and its boxes stay drawn.
func _check_unusable_packs(text: String, doc_path: String) -> void:
	var dir := "user://pg_world_fixture"
	var pack_dir := dir.path_join("world/pg_world_fixture")
	DirAccess.make_dir_recursive_absolute(pack_dir)
	for ext in [".json", ".bin"]:
		DirAccess.copy_absolute(WORLD_FIXTURE + "/world/pg_world_fixture/pg_world" + ext, pack_dir.path_join("pg_world" + ext))
	var cases := {
		"missing": text.replace("\"pack\": \"pg_world_fixture\"", "\"pack\": \"pg_world_gone\""),
		"scale": text.replace("0.01905", "0.0254"),
	}
	for name: String in cases:
		var path := dir.path_join("pg_world.json")
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(cases[name])
		f.close()
		var other: Node3D = _tmas_data_script.new()
		other.draw_world = false
		add_child(other)
		other.configure_doc(path)
		other.draw_world = true
		var got: GSResult = await other.load_world()
		var shaded_before: bool = other._shades_boxes()
		_check(not got.ok and other.drawn_world == null and other.get_node_or_null(^"World") == null and _hidden_box_meshes(other) == 0,
			"world: a pack %s leaves the boxes drawn" % ("that is not there" if name == "missing" else "made at another scale"),
			str(got.value) if got.ok else got.error.message)
		var plain_doc: Dictionary = (other.doc as Dictionary).duplicate()
		plain_doc.erase("world")
		other.doc = plain_doc
		_check(not shaded_before and other._shades_boxes(), "world: a map with no pack shades its boxes, one with a pack only when it is not drawn")
		other.queue_free()
		DirAccess.remove_absolute(path)
	for ext in [".json", ".bin"]:
		DirAccess.remove_absolute(pack_dir.path_join("pg_world" + ext))
	DirAccess.remove_absolute(pack_dir)
	DirAccess.remove_absolute(dir.path_join("world"))
	DirAccess.remove_absolute(dir)


## The document reader refuses a bad `world` entry and reads a bare pack name or none.
func _check_world_specs(text: String) -> void:
	var parsed: Dictionary = JSON.parse_string(text)
	var refused := 0
	for bad: Variant in ["../up", "", 5, {"pack": "a/b"}, {"pack": "p", "offset": [0, 0]}, {"pack": "p", "metres_per_unit": 0}]:
		var d := parsed.duplicate(true)
		d["world"] = bad
		refused += 0 if _tmas_data_script.call("validate", d).ok else 1
	var named := parsed.duplicate(true)
	named["world"] = "pg_world_fixture"
	var plain := parsed.duplicate(true)
	plain.erase("world")
	_check(refused == 6 and _tmas_data_script.call("validate", named).ok and _tmas_data_script.call("validate", plain).ok
		and (_tmas_data_script.call("world_spec", plain) as Dictionary).is_empty(),
		"world: a path, a number or a bad offset or scale refuses the document; a bare pack name and no world read",
		"%d of 6 refused" % refused)


## How many box and brush meshes under [param map] are hidden.
func _hidden_box_meshes(map: Node3D) -> int:
	var hidden := 0
	for child in map.get_children():
		if child is StaticBody3D and child.has_meta(&"pg_box"):
			for part in child.get_children():
				if part is GeometryInstance3D and not (part as GeometryInstance3D).visible:
					hidden += 1
	return hidden


# The collision audit

## A floor with one of everything on it: a 0.5 m slot between two walls, a platform 5 m
## up, and a cellar a player drops into and cannot climb out of.
func _the_survey_sees_what_it_looks_for() -> void:
	var boxes: Array = [
		PlaylotMapSurvey.solid(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0)),
		# The slot: two walls 0.5 m apart.
		PlaylotMapSurvey.solid(Vector3(-5.0, 1.5, -6.0), Vector3(2.0, 3.0, 1.0)),
		PlaylotMapSurvey.solid(Vector3(-2.5, 1.5, -6.0), Vector3(2.0, 3.0, 1.0)),
		# Out of reach: 5 m up, 4 m across, nothing to climb.
		PlaylotMapSurvey.solid(Vector3(-6.0, 5.0, 6.0), Vector3(4.0, 0.5, 4.0)),
		# The cellar: 3 m under the floor's east edge, walled in on its other three sides.
		PlaylotMapSurvey.solid(Vector3(13.0, -3.5, 0.0), Vector3(6.0, 1.0, 6.0)),
		PlaylotMapSurvey.solid(Vector3(16.5, 0.0, 0.0), Vector3(1.0, 8.0, 8.0)),
		PlaylotMapSurvey.solid(Vector3(13.0, 0.0, 3.5), Vector3(6.0, 8.0, 1.0)),
		PlaylotMapSurvey.solid(Vector3(13.0, 0.0, -3.5), Vector3(6.0, 8.0, 1.0)),
	]
	var solids: Array[PlaylotMapSurvey.Solid] = []
	for box: Variant in boxes:
		solids.append(box)

	# The walls' own tops are out of reach too, which is right and is not what this asks
	# about, so the fixture declares them the way a map declares its walls.
	var walls: Array = []
	for i in [1, 2, 5, 6, 7]:
		var wall: PlaylotMapSurvey.Solid = solids[i]
		walls.append({"box": wall.bounds.grow(0.1), "why": "a fixture wall's top"})

	var spawns: Array[Vector3] = [Vector3(0.0, 1.0, 0.0)]
	var found: Dictionary = PlaylotMapSurvey.survey_solids(solids, [], spawns, walls)

	_check((found["slots"] as Array).size() == 1,
		"the survey finds the fixture's one slot", "; ".join(found["slots"]))
	_check((found["unreached"] as Array).size() == 1
			and str((found["unreached"] as Array)[0]).contains(", 5.2, "),
		"and the platform nobody can reach", "; ".join(found["unreached"]))
	_check((found["trapped"] as Array).size() == 1
			and str((found["trapped"] as Array)[0]).contains("-3.0"),
		"and the cellar nobody can leave", "; ".join(found["trapped"]))

	# Declared, the platform is not reported; a reset in the cellar is a way out of it.
	var declared: Array = walls.duplicate()
	declared.append({"box": AABB(Vector3(-8.0, 4.0, 4.0), Vector3(4.0, 2.0, 4.0)), "why": "fixture"})
	# A way out as `PlaylotMapSurvey.ways_out_of` reads one off a timer's RESPAWN zone.
	var reset: Array = [{"box": AABB(Vector3(10.0, -3.5, -3.0), Vector3(6.0, 3.5, 6.0)), "pit": true}]
	var quiet: Dictionary = PlaylotMapSurvey.survey_solids(solids, reset, spawns, declared)

	_check((quiet["unreached"] as Array).is_empty() and (quiet["trapped"] as Array).is_empty(),
		"and neither once the platform is declared and the cellar has a reset",
		"unreached %s; trapped %s" % [str(quiet["unreached"]), str(quiet["trapped"])])
