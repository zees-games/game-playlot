extends GSGamePerfBench

const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotData := preload("../maps/pg_data.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## The offline sandbox benchmark: dot-game's GSGamePerfBench (flags, recording, sidecar; see it) on the playlot client. Run it windowed with `tools/perf_bench.sh --box staging02` (gamedev, from a checkout).
## `--bots N` NPCs (wanderers, chasers, soldiers) and `--props N` props (crates, barrels, balls) dropped in a pile in front of the player, so the run has physics, NPC brains and draw work; `--map ID` another map first (default pg_flatgrass).

const NPC_IDS: Array[StringName] = [&"npc_wanderer", &"npc_chaser", &"npc_soldier"]
const PROP_IDS: Array[StringName] = [&"crate", &"barrel", &"beach_ball", &"plank"]

var _scratch: Variant = null


func _configure() -> void:
	client_scene = "res://game/playlot.tscn"
	map = "pg_flatgrass"
	mode = "sandbox"
	bots = 8
	_scratch = PlaylotPresentation.use_scratch_settings("perf_bench")


func _setup_client(c: Node) -> void:
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	c.set("config", config)
	# --fetch-content 1: the client downloads a content (world-pack) map from the content origin, so a pack map can be measured.
	c.set("fetch_content", str(args.get("fetch-content", "0")) == "1")
	c.set("mouse_capture_override", true)
	# --batch-props 1: the drawn world bakes its static props into per-cell batches (GSMapPropBatch) (the default); 0 keeps one node per prop.
	PlaylotData.batch_props = str(args.get("batch-props", "1")) == "1"


func _select(_game: Object) -> void:
	var pg: Node = client.get("playlot")
	var player: Node3D = client.get("player")
	if pg == null or player == null:
		say("no playlot or player")
		return
	if map != "" and map != "pg_flatgrass":
		var changed: GSResult = pg.call("change_map", StringName(map))
		say("change_map %s: %s" % [map, "ok" if changed.ok else changed.error.message])
		await wait(3.0)
		player = client.get("player")
		await _wait_world(pg)
	if args.has("cam"):
		_fix_camera(player)
		if str(args.get("ablate", "0")) == "1":
			await _ablate(pg)
	var props_n := int(args.get("props", 60))
	var eye: Vector3 = player.call("eye_position")
	var ahead: Vector3 = player.call("aim_direction")
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var side := ahead.cross(Vector3.UP)
	var centre := eye + ahead * 10.0
	var spawner: Object = pg.get("props")
	# The spawn rate limit is for players clicking; the pile arrives in one frame, as a map's props do (PlaylotWorld.spawn_map_props).
	var limits: Object = spawner.get("limits")
	var interval: float = limits.get("spawn_interval") if limits != null else 0.0
	if limits != null:
		limits.set("spawn_interval", 0.0)
	var made := 0
	for i in props_n:
		var at := centre + side * float(i % 6 - 3) * 1.2 + Vector3.UP * (1.0 + floorf(i / 6.0) * 1.1)
		if spawner.call("spawn", PROP_IDS[i % PROP_IDS.size()], &"map", at) != null:
			made += 1
	var npcs := 0
	for i in bots:
		var at := centre + ahead * (4.0 + float(i % 4) * 2.0) + side * (floorf(i / 4.0) - 1.0) * 3.0
		if spawner.call("spawn", NPC_IDS[i % NPC_IDS.size()], client.get("player_id"), at) != null:
			npcs += 1
	if limits != null:
		limits.set("spawn_interval", interval)
	say("spawned %d props, %d npcs" % [made, npcs])
	# `--still-figures 1`: the NPCs' people stop animating themselves, to price their animation (an ablation, not a game setting).
	if str(args.get("still-figures", "0")) == "1":
		await wait(0.5)
		var stilled := 0
		for figure: Node in pg.find_children("Figure", "", true, false):
			if "auto_animate" in figure:
				figure.set("auto_animate", false)
				stilled += 1
		say("stilled %d figures" % stilled)


## `--cam x,y,z --look x,y,z` (world metres): the frame is drawn from a fixed camera there instead of the player's eye, so a
## render A/B reads the same view every run (the pgc_fork overlook: `--map pgc_fork --cam 0,-110,330 --look 20,-170,0 --props 0 --bots 0`).
## The player is parked under it and stops simulating; the world, its props and its culling run as they do in play.
func _fix_camera(player: Node3D) -> void:
	var c := str(args["cam"]).split_floats(",")
	var l := str(args.get("look", "0,0,0")).split_floats(",")
	var at := Vector3(c[0], c[1], c[2])
	var cam := Camera3D.new()
	cam.name = "BenchCamera"
	# The play camera's reach and lens unless asked: its far is the view distance setting, which bounds what is drawn.
	var play := get_viewport().get_camera_3d()
	cam.far = float(args.get("far", str(play.far if play != null else 4000.0)))
	cam.fov = float(args.get("fov", str(play.fov if play != null else 75.0)))
	add_child(cam)
	cam.look_at_from_position(at, Vector3(l[0], l[1], l[2]))
	player.global_position = at
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_cam = cam
	cam.make_current()
	say("fixed camera at %s looking at %s" % [at, Vector3(l[0], l[1], l[2])])


var _cam: Camera3D = null
var _data: Node = null


## `--ablate 1` (with `--cam`): before the warm-up, prices each part of the drawn world at the fixed camera by hiding it for a
## while and reading frame time and the visible and shadow passes' draws and primitives (a diagnosis; the run then measures as usual).
func _ablate(pg: Node) -> void:
	await wait(5.0)
	var root: Node3D = null
	if _data != null and _data.get("drawn_world") != null:
		root = (_data.get("drawn_world") as Object).get("root")
	var parts: Array = []
	if root != null:
		for c in root.get_children():
			if c is Node3D:
				var mis := c.find_children("*", "GeometryInstance3D", true, false).size()
				say("ablate part %s %s geometry=%d" % [c.name, c.get_class(), mis])
				parts.append(c)
	var lights: Array = pg.find_children("*", "DirectionalLight3D", true, false) + pg.find_children("*", "OmniLight3D", true, false) + pg.find_children("*", "SpotLight3D", true, false)
	var shadowed: Array = lights.filter(func(l: Light3D) -> bool: return l.shadow_enabled and l.is_visible_in_tree())
	say("ablate lights=%d shadowed=%d" % [lights.size(), shadowed.size()])
	await _ablate_row("all")
	for l: Light3D in shadowed:
		l.shadow_enabled = false
	await _ablate_row("no shadows")
	for l: Light3D in shadowed:
		l.shadow_enabled = true
	# The parts with the most geometry one at a time, then all of them.
	for c: Node3D in parts:
		c.visible = false
		await _ablate_row("no " + str(c.name))
		c.visible = true
	for c: Node3D in parts:
		c.visible = false
	await _ablate_row("no world at all")
	for c: Node3D in parts:
		c.visible = true


func _ablate_row(label: String) -> void:
	await wait(2.0)
	var vp := get_viewport()
	var t0 := Time.get_ticks_usec()
	var n := 90
	var dc := 0.0
	var pr := 0.0
	var ob := 0.0
	var sdc := 0.0
	var spr := 0.0
	for i in n:
		await get_tree().process_frame
		dc += vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		pr += vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		ob += vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
		sdc += vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		spr += vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	say("ablate %-24s ms=%.2f fps=%.1f draws=%d prims=%d objects=%d shadow_draws=%d shadow_prims=%d" % [label, ms, 1000.0 / ms, dc / n, pr / n, ob / n, sdc / n, spr / n])


## A map with a world pack draws its boxes until the pack is built (sliced over frames), so a
## render A/B waits for it: `--world-wait S` seconds at most (default 600, 0 skips), then says
## how long it took or that it timed out (the run then measures the boxes, and says so).
func _wait_world(pg: Node) -> void:
	var limit := float(args.get("world-wait", "600"))
	if limit <= 0.0:
		return
	var t0 := Time.get_ticks_msec()
	var data: Node = null
	while (Time.get_ticks_msec() - t0) / 1000.0 < limit:
		if data == null:
			for n: Node in pg.find_children("*", "Node3D", true, false):
				if "drawn_world" in n and "draw_world" in n:
					data = n
					break
		if data == null or not bool(data.get("draw_world")) or (data.get("doc") as Dictionary).get("world") == null:
			if (Time.get_ticks_msec() - t0) > 3000:
				say("no world pack to wait for")
				return
		elif data.get("drawn_world") != null:
			_data = data
			say("world pack drawn after %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
			return
		await wait(0.5)
	say("world pack NOT drawn after %.0f s; the boxes are measured" % limit)


func _process(_delta: float) -> void:
	# The client's own camera takes `current` back when it respawns or reframes; the bench view wins every frame.
	if _cam != null and not _cam.current:
		_cam.make_current()


## `--render-scan 1`: the report's render.top_draw (materials and meshes by draws and triangles); one scene walk at the end of the recording.
func _record_begin() -> void:
	if str(args.get("mesh-census", "0")) == "1":
		_mesh_census()
	if str(args.get("render-scan", "0")) == "1" and profiler != null:
		profiler.config.perf_render_scan = true


func _sidecar_extra(_game: Object) -> Dictionary:
	var extra := {"props": int(args.get("props", 60)), "npcs": bots}
	if _cam != null:
		extra["camera"] = [str(_cam.global_position), str(-_cam.global_basis.z), _cam.far, _cam.fov]
	return extra


## `--mesh-census 1`: says what every visible mesh instance is (mesh class, material kind, what owns it), biggest groups first, so the
## draws a batch left behind have a name: "BoxMesh opaque under StaticBody3D pg_box" is a box the batcher refused.
func _mesh_census() -> void:
	var groups := {}
	var total := 0
	for node: Node in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		total += 1
		var mat: Material = mi.material_override
		if mat == null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		var kind := "none"
		if mat is StandardMaterial3D:
			kind = "alpha" if (mat as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else "opaque"
		elif mat != null:
			kind = mat.get_class()
		var up := mi.get_parent()
		var owner_desc := up.get_class()
		if up.has_meta(&"pg_box"):
			owner_desc += " pg_box"
		if up.has_meta(&"pg_material"):
			owner_desc += " mat=" + str(up.get_meta(&"pg_material"))
		var key := "%s %s under %s of %s" % [mi.mesh.get_class(), kind, owner_desc, up.get_parent().name if up.get_parent() != null else ""]
		groups[key] = int(groups.get(key, 0)) + 1
	var keys := groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return groups[a] > groups[b])
	say("mesh census: %d visible mesh instances" % total)
	for k: String in keys.slice(0, 30):
		say("census %4d  %s" % [groups[k], k])
