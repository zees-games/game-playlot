extends Node

## Fall-through probe for the converted custom maps: where the drawn world (the map's world pack) shows a floor
## that the game's collision (the document's boxes, brushes and prop bodies) does not hold up, a player falls
## through the ground. Per map:
##
## - the drawn world's meshes get a temporary trimesh body on a layer of their own (PROBE_LAYER);
## - on a grid of --cell metres over the drawn bounds, every upward-facing drawn surface (normal.y > 0.7) is
##   found, and the game collision is asked for a floor within FLOOR_TOLERANCE below it (the ray starts
##   RAY_UP above, so a box a little over the drawn face still counts). None: a HOLE, `deep` when nothing
##   holds within --deep metres (a fall), `sunk` when the game floor is lower but within it;
##   a drawn surface inside a liquid volume is water, not a hole;
## - the game collision's own floors are flooded from the spawns (a step of at most STEP metres between
##   neighbouring cells), and a hole is EXPOSED when a reached floor next to it is within STEP of its height:
##   a player walks onto it;
## - a capsule is dropped at each spawn: it must come to rest within FELL metres of where it started.
##
## Prints one line per map and the exposed deep holes (clustered), writes --json, and exits 1 when a map has
## more exposed deep holes than --max-holes (default 0) or a spawn drop falls. --max-holes -1 never fails on
## holes (report only). Same idea as game-zombie-zone tools/fall_probe.gd (HOLE_DRAWN), on Playlot's documents.
##
##   tools/fall_probe.tscn -- pgc_fork pgc_southside [--cell=1.0] [--deep=2.5] [--max-holes=0] [--json=user://fall.json]
##   (no id: every maps/custom/*.json); through hv: hv <wt> scene res://tools/fall_probe.tscn -- pgc_fork

const PROBE_LAYER := 1 << 30
const RAY_UP := 0.6
const FLOOR_TOLERANCE := 0.75
const STEP := 1.0
const FELL := 2.5
const UPWARD := 0.7

var cell := 1.0
var deep := 2.5
var max_holes := 0
var json_path := ""


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var ids := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cell="):
			cell = maxf(0.1, float(a.substr(7)))
		elif a.begins_with("--deep="):
			deep = float(a.substr(7))
		elif a.begins_with("--max-holes="):
			max_holes = int(a.substr(12))
		elif a.begins_with("--json="):
			json_path = a.substr(7)
		elif not a.begins_with("--"):
			ids.append(a)
	if ids.is_empty():
		for file in DirAccess.get_files_at("res://maps/custom"):
			if file.ends_with(".json"):
				ids.append(file.get_basename())
	var data_script := load("res://maps/pg_data.gd") as GDScript
	var failed := false
	var report := {}
	for id in ids:
		var r: Dictionary = await _probe(data_script, id)
		report[id] = r
		var bad := bool(r.get("load_failed", false)) or int(r.get("fell", 0)) > 0
		bad = bad or (max_holes >= 0 and int(r.get("exposed", 0)) > max_holes)
		bad = bad or int(r.get("floors", 0)) == 0   # nothing probed is a failure, not a pass
		failed = failed or bad
		print("%s %s: drawn floors %d, holes %d (deep %d, sunk %d), exposed %d, water %d, reached cells %d, spawn drops fell %d" % [
			"FAIL" if bad else "ok  ", id, int(r.get("floors", 0)), int(r.get("holes", 0)), int(r.get("deep", 0)),
			int(r.get("sunk", 0)), int(r.get("exposed", 0)), int(r.get("water", 0)), int(r.get("reached", 0)), int(r.get("fell", 0))])
		for c in r.get("clusters", []):
			print("  HOLE %d cells near (%.1f, %.1f, %.1f)" % [int(c["cells"]), c["at"][0], c["at"][1], c["at"][2]])
		if r.has("error"):
			print("  " + str(r["error"]))
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(report, " "))
			f.close()
			print("fall_probe: wrote %s" % ProjectSettings.globalize_path(json_path))
	get_tree().quit(1 if failed else 0)


func _probe(data_script: GDScript, id: String) -> Dictionary:
	var map: Node3D = data_script.new()
	map.draw_world = true
	add_child(map)
	var configured: DotResult = map.configure_doc("res://maps/custom/%s.json" % id)
	if not configured.ok:
		map.queue_free()
		return {"load_failed": true, "error": str(configured.error)}
	var guard := 6000
	while map.drawn_world == null and map._world_loading and guard > 0:
		await get_tree().process_frame
		guard -= 1
	if map.drawn_world == null:
		map.queue_free()
		return {"load_failed": true, "error": "no world pack drawn"}
	var built: Array = _build_probe(map)
	var probe: StaticBody3D = built[0]
	var bounds: AABB = built[1]
	for _i in 3:
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var game_mask := 0xFFFFFFFF & ~PROBE_LAYER
	var scan: Dictionary = _scan(space, bounds, game_mask)
	var game_floors: Dictionary = scan.game_floors
	var holes: Array = scan.holes
	var floors: int = scan.floors
	var water: int = scan.water
	var spawns: Array[Vector3] = _spawns(map)
	var reached := _flood(spawns, game_floors, bounds)
	var n_reached := 0
	for k in reached:
		n_reached += (reached[k] as Array).size()
	var split := _exposed(holes, reached)
	var exposed: Array = split[0]
	var n_deep: int = split[1]
	var n_sunk: int = split[2]
	var fell := 0
	var drops := []
	for s in spawns:
		var d: float = await _drop(s)
		drops.append(d)
		if d > FELL:
			fell += 1
	probe.queue_free()
	map.queue_free()
	await get_tree().process_frame
	var out := {"floors": floors, "holes": holes.size(), "deep": n_deep, "sunk": n_sunk, "water": water,
		"exposed": exposed.size(), "reached": n_reached, "fell": fell, "drops": drops, "cell": cell,
		"clusters": _clusters(exposed, bounds)}
	return out


## Mirror every visible drawn mesh into a probe-layer collider; returns [body, bounds].
func _build_probe(map: Node3D) -> Array:
	var probe := StaticBody3D.new()
	probe.collision_layer = PROBE_LAYER
	probe.collision_mask = 0
	var bounds := AABB()
	var first := true
	var droot: Node3D = map.drawn_world.root if map.drawn_world.root != null else map
	for node in droot.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or String(mi.name).to_lower().contains("sky"):
			continue
		var faces: PackedVector3Array = mi.mesh.get_faces()
		if faces.is_empty():
			continue
		var xf: Transform3D = mi.global_transform
		for i in faces.size():
			faces[i] = xf * faces[i]
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		probe.add_child(cs)
		var box: AABB = xf * mi.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	add_child(probe)
	return [probe, bounds]


## Probe-floor columns: which drawn floors have game collision under them.
func _scan(space: PhysicsDirectSpaceState3D, bounds: AABB, game_mask: int) -> Dictionary:
	var nx := int(ceil(bounds.size.x / cell))
	var nz := int(ceil(bounds.size.z / cell))
	var top := bounds.end.y + 1.0
	var bottom := bounds.position.y - 1.0
	var game_floors := {}   # Vector2i -> Array[float]
	var holes := []         # [Vector2i, y, kind]
	var floors := 0
	var water := 0
	for ix in nx:
		for iz in nz:
			var x := bounds.position.x + (ix + 0.5) * cell
			var z := bounds.position.z + (iz + 0.5) * cell
			var key := Vector2i(ix, iz)
			game_floors[key] = _floors(space, x, z, top, bottom, game_mask)
			for y in _floors(space, x, z, top, bottom, PROBE_LAYER):
				floors += 1
				var held := _hit(space, Vector3(x, y + RAY_UP, z), Vector3(x, y - FLOOR_TOLERANCE, z), game_mask)
				if held:
					continue
				if _in_liquid(space, Vector3(x, y + 0.2, z)) or _in_liquid(space, Vector3(x, y - 0.3, z)):
					water += 1
					continue
				var below := _hit(space, Vector3(x, y - FLOOR_TOLERANCE, z), Vector3(x, y - deep, z), game_mask)
				holes.append([key, y, "sunk" if below else "deep"])
	return {"game_floors": game_floors, "holes": holes, "floors": floors, "water": water}


## The map's spawn points plus its fallback spawn.
func _spawns(map: Node3D) -> Array[Vector3]:
	var spawns: Array[Vector3] = [map.fallback_spawn]
	for s in (map.doc as Dictionary).get("spawns", []):
		if s is Array and (s as Array).size() >= 3:
			spawns.append(Vector3(float(s[0]), float(s[1]), float(s[2])))
	return spawns


## Flood game floors walkable (STEP) from the spawns; Vector2i -> Array[float].
func _flood(spawns: Array[Vector3], game_floors: Dictionary, bounds: AABB) -> Dictionary:
	var reached := {}  # Vector2i -> Array[float]
	var queue := []
	for s in spawns:
		var k := Vector2i(int(floor((s.x - bounds.position.x) / cell)), int(floor((s.z - bounds.position.z) / cell)))
		var best := INF
		for y in game_floors.get(k, []):
			if y <= s.y + STEP and absf(s.y - y) < absf(s.y - best):
				best = y
		if best != INF:
			queue.append([k, best])
	while not queue.is_empty():
		var it: Array = queue.pop_back()
		var k: Vector2i = it[0]
		var y: float = it[1]
		var got: Array = reached.get(k, [])
		var seen := false
		for g in got:
			seen = seen or absf(g - y) < 0.05
		if seen:
			continue
		got.append(y)
		reached[k] = got
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			for ny in game_floors.get(k + d, []):
				if absf(ny - y) <= STEP:
					queue.append([k + d, ny])
	return reached


## Deep holes next to a reached floor; returns [exposed, n_deep, n_sunk].
func _exposed(holes: Array, reached: Dictionary) -> Array:
	var exposed := []
	var n_deep := 0
	var n_sunk := 0
	for h in holes:
		if h[2] == "sunk":
			n_sunk += 1
			continue
		n_deep += 1
		var k: Vector2i = h[0]
		var near := false
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for ry in reached.get(k + Vector2i(dx, dz), []):
					near = near or absf(ry - float(h[1])) <= STEP
		if near:
			exposed.append(h)
	return [exposed, n_deep, n_sunk]


## Every upward-facing surface height in a column, top down.
func _floors(space: PhysicsDirectSpaceState3D, x: float, z: float, top: float, bottom: float, mask: int) -> Array:
	var out := []
	var y := top
	var guard := 64
	while guard > 0 and y > bottom:
		guard -= 1
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, y, z), Vector3(x, bottom, z), mask)
		q.hit_back_faces = false
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		var p: Vector3 = r["position"]
		if (r["normal"] as Vector3).y > UPWARD:
			out.append(p.y)
		y = p.y - 0.05
	return out


func _hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.hit_from_inside = true
	return not space.intersect_ray(q).is_empty()


func _in_liquid(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = at
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r in space.intersect_point(q, 8):
		var c: Object = r.get("collider")
		if c is Area3D:
			return true
	return false


## How far a capsule dropped at `at` ends below it after two seconds of falling.
func _drop(at: Vector3) -> float:
	var body := CharacterBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 0xFFFFFFFF & ~PROBE_LAYER
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	add_child(body)
	body.global_position = at + Vector3(0, 0.1, 0)
	var dt := 1.0 / 60.0
	for _i in 120:
		await get_tree().physics_frame
		body.velocity.y -= 9.8 * dt
		body.move_and_slide()
	var fell := at.y - body.global_position.y
	body.queue_free()
	return fell


func _clusters(exposed: Array, bounds: AABB) -> Array:
	var left := {}
	for h in exposed:
		left[h[0]] = h[1]
	var out := []
	while not left.is_empty():
		var start: Vector2i = left.keys()[0]
		var stack := [start]
		var cells := 0
		var sum := Vector3.ZERO
		while not stack.is_empty():
			var k: Vector2i = stack.pop_back()
			if not left.has(k):
				continue
			var y: float = left[k]
			left.erase(k)
			cells += 1
			sum += Vector3(bounds.position.x + (k.x + 0.5) * cell, y, bounds.position.z + (k.y + 0.5) * cell)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				stack.append(k + d)
		var c := sum / cells
		out.append({"cells": cells, "at": [snappedf(c.x, 0.1), snappedf(c.y, 0.1), snappedf(c.z, 0.1)]})
	out.sort_custom(func(a, b): return int(a["cells"]) > int(b["cells"]))
	return out.slice(0, 20)
