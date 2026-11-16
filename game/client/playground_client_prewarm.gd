extends Node

## Builds, under the loading cover, what the first spawn, shot and menu would build in play (web
## WebGL compiles a shader, loads a scene and compiles a script on the frame that first needs it),
## then frees it and hands the gate what it draws. Presentation only: nothing reaches the sim.

const PlaygroundConfig := preload("../playground_config.gd")
const PlaygroundIcons := preload("../playground_icons.gd")
const PlaygroundProp := preload("../playground_prop.gd")
const PlaygroundSpawnables := preload("../playground_spawnables.gd")
const PlaygroundWeaponIcons := preload("../playground_weapon_icons.gd")
const PlaygroundZee := preload("../playground_zee.gd")
const PlaygroundWeaponDef := preload("../weapons/playground_weapon_def.gd")

const CHANNEL := "playground.prewarm"

## The gate's hold while this runs.
const HOLD := &"prewarm"

## The per-frame budget asked of [method DotLoadGate.slice_msec]. A wider slice under the cover measured slower:
## the gate's own draw, after its time-out, shared each frame with it.
const SLICE_MS := 8

## Range of the light held on the camera under the cover, in metres: it reaches what the host draws in front of it.
const PROBE_RANGE := 2.0

## Ids built even when the catalogue's shapes would not reach them: what the Launcher fires
## with nothing armed and what the spawn menu has selected before anybody picks.
const ALWAYS := [&"ball", &"crate"]

enum Phase { PROPS, SHOT_FX, MUZZLE, BLOOD, WEAPONS, FX, ICONS, DONE }

## Fired on the frame after a pause: the run waits on this node, so a freed node is never resumed.
signal _frame

var gate: DotLoadGate = null
var config: PlaygroundConfig = null
var catalogue: DotPropCatalogue = null
var fx_catalogue: DotFxCatalogue = null
## The presentation's blood, whose decal settings the warmed splat copies. Null warms no blood.
var blood: DotFxBlood = null
## The client's shared layered shot (playground_shot_sound.gd), built in the SHOT_FX phase. Null builds none.
var shot_sound: Node = null

## True once every phase has run and the hold is released.
var finished: bool = false

## Materials and meshes handed to the gate, counted across phases.
var warmed: int = 0

## Milliseconds each phase took, by name: what the log line reports and a test reads.
var phase_ms: Dictionary = {}

## Items not handed because one with the same shader and vertex format already was: each would only lengthen the
## host's draw under the cover, compiling nothing new.
var skipped: int = 0

## Frames the cover-held phases took to run: on a software WebGL each costs hundreds of ms.
var cover_frames: int = 0

## When true, [member profile] collects microseconds per step and per item ("prop.load", "item:PROPS:<id>"...).
var profiling: bool = false
## Step or item name -> total microseconds, filled while [member profiling] is on.
var profile: Dictionary = {}
var _lap_at := 0

var _slice: DotFrameSlice = null
var _spare_view: ZeeViewModel = null
var _parts_warmed := false
## True while [constant HOLD] is held.
var _covering := false
## Shader keys (and mesh keys) handed so far.
var _keys := {}
## Material instance id -> its key, so a material shared by many items is keyed once.
var _key_cache := {}
## What stays drawn on the camera until the gate opens: the muzzle flashes and the light probe.
var _on_camera: Array[Node] = []
## Artwork icons are loaded with `load()` and not cached by the icon code: kept here until the
## game is over, so the spawn menu's first open finds them in the resource cache.
var _held_icons: Array[Texture2D] = []
## The viewport whose 3D drawing is off under the cover ([member PlaygroundConfig.prewarm_hide_world]), else null.
var _hidden_view: Viewport = null
## True once the 3D world was left undrawn under the cover: what a test reads.
var hid_world: bool = false


## Starts the work and holds [member gate] until all but the icons are done. Returns false (nothing held) when
## [member config] turns it off.
func start() -> bool:
	profiling = profiling or OS.get_cmdline_user_args().has("--prewarm-profile")
	if config != null and not config.prewarm:
		finished = true
		return false
	if gate != null:
		gate.hold(HOLD, "Getting things ready")
		_covering = true
		_hide_world()
	_run()
	return true


## Every phase in turn, pausing a frame whenever the gate's budget is spent: at least one item a
## frame, so a budget of 0 still finishes.
func _run() -> void:
	for phase in range(Phase.DONE):
		if phase == Phase.ICONS:
			_release_cover()
		var began := Time.get_ticks_usec()
		for item in _items_for(phase as Phase):
			if _slice == null:
				_slice = DotFrameSlice.new(gate.slice_msec(SLICE_MS) if gate != null else SLICE_MS)
			_warm_one(phase as Phase, item)
			if _slice.due():
				_slice = null
				if _covering:
					cover_frames += 1
				get_tree().process_frame.connect(_frame.emit, CONNECT_ONE_SHOT)
				await _frame
		phase_ms[Phase.keys()[phase]] = (Time.get_ticks_usec() - began) / 1000
	_finish()


## The spare view lives outside the tree, so nothing frees it with this node: a game that ends
## before the warm-up does (a test, a quit on the loading screen) would leak it and its meshes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_spare_view()
		_show_world()


## Turns off 3D drawing while the hold covers the screen: nothing here needs it (the gate draws the warmed items
## after every hold is gone), and on software GL each covered frame drew the whole map. The gate's own signals
## turn it back on too, because its time-out drops this hold while the work is still running.
func _hide_world() -> void:
	if config == null or not config.prewarm_hide_world or not is_inside_tree() or get_viewport().disable_3d:
		return
	_hidden_view = get_viewport()
	_hidden_view.disable_3d = true
	hid_world = true
	for sig: Signal in [gate.ready_to_show, gate.opened]:
		if not sig.is_connected(_show_world):
			sig.connect(_show_world, CONNECT_ONE_SHOT)


func _show_world() -> void:
	if _hidden_view != null and is_instance_valid(_hidden_view):
		_hidden_view.disable_3d = false
	_hidden_view = null


func _free_spare_view() -> void:
	if _spare_view != null and is_instance_valid(_spare_view):
		_spare_view.free()
	_spare_view = null


## Icons are loaded and drawn on the CPU, not compiled for the GPU, so the cover does not wait for
## them: on a software WebGL they took 26 s of a 41 s hold. They finish in play, a slice a frame.
func _release_cover() -> void:
	_free_spare_view()
	_covering = false
	_show_world()
	_hold_light_probe()
	DotLog.info(CHANNEL, "warmed under the cover", {"items": warmed, "skipped": skipped, "frames": cover_frames,
		"ms": phase_ms.duplicate()})
	if gate != null:
		gate.release(HOLD)


func _finish() -> void:
	finished = true
	_covering = false
	_free_spare_view()
	_show_world()
	DotLog.info(CHANNEL, "warmed the icons in play", {"ms": phase_ms.get("ICONS", 0)})
	if profiling:
		_print_profile()
	if gate != null:
		gate.release(HOLD)


## The profile, slowest first, one "prewarm profile:" line per entry (a tool's output, so print).
func _print_profile() -> void:
	var keys := profile.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(profile[a]) > int(profile[b]))
	print("prewarm profile: phases ms=%s cover_frames=%d" % [phase_ms, cover_frames])
	for key: String in keys:
		print("prewarm profile: %8.1f ms  %s" % [int(profile[key]) / 1000.0, key])


func _items_for(phase: Phase) -> Array:
	match phase:
		Phase.PROPS:
			return _prop_defs()
		Phase.SHOT_FX, Phase.BLOOD:
			return [null]
		Phase.MUZZLE:
			return [null] if _shot_effects() else []
		Phase.WEAPONS:
			var out: Array = []
			for def in PlaygroundZee.defs():
				if PlaygroundZee.is_zee(def):
					var art := ZeeWeaponArtTable.get_art(PlaygroundZee.zee_id(def))
					if art != null:
						out.append(art)
			return out
		Phase.FX:
			var out: Array = []
			if fx_catalogue != null:
				for id in fx_catalogue.ids():
					var def := fx_catalogue.find(id)
					if def != null and def.scene_path != "":
						out.append(def.scene_path)
			return out
		Phase.ICONS:
			var out: Array = []
			for def in _all_props():
				out.append(def)
			for def in PlaygroundZee.defs():
				out.append(def)
			return out
	return []


## Every entity and vehicle, and one plain prop of each shape: plain props differ only in colour
## and size, so one per mesh draws every shader they use. Model props load a scene file each; they are
## left out when [member PlaygroundConfig.prewarm_model_props] is off.
func _prop_defs() -> Array:
	var out: Array = []
	var shapes := {}
	for def in _all_props():
		var kind := PlaygroundSpawnables.kind_of(def)
		var model := PlaygroundProp.model_of(def) != ""
		if kind != PlaygroundSpawnables.Kind.PROP:
			out.append(def)
		elif model:
			if config != null and config.prewarm_model_props:
				out.append(def)
		elif ALWAYS.has(def.id) or not shapes.has(PlaygroundProp.shape_of(def)):
			shapes[PlaygroundProp.shape_of(def)] = true
			out.append(def)
	return out


func _all_props() -> Array[DotPropDef]:
	var out: Array[DotPropDef] = []
	if catalogue == null:
		return out
	var seen := {}
	for category in catalogue.categories():
		for def in catalogue.in_category(StringName(category)):
			if def != null and not seen.has(def.id):
				seen[def.id] = true
				out.append(def)
	return out


func _warm_one(phase: Phase, item: Variant) -> void:
	var began := Time.get_ticks_usec() if profiling else 0
	_lap_at = began
	_warm_one_inner(phase, item)
	if profiling:
		var key := "item:%s:%s" % [Phase.keys()[phase], _item_name(item)]
		profile[key] = int(profile.get(key, 0)) + Time.get_ticks_usec() - began


static func _item_name(item: Variant) -> String:
	if item is DotPropDef:
		return str((item as DotPropDef).id)
	if item is Resource:
		var res := item as Resource
		return res.resource_path.get_file() if res.resource_path != "" else res.get_class()
	return str(item)


## Adds the time since the last lap to [param step] in [member profile].
func _lap(step: String) -> void:
	if not profiling:
		return
	var now := Time.get_ticks_usec()
	profile[step] = int(profile.get(step, 0)) + now - _lap_at
	_lap_at = now


func _warm_one_inner(phase: Phase, item: Variant) -> void:
	match phase:
		Phase.PROPS:
			_warm_prop(item as DotPropDef)
		Phase.SHOT_FX:
			_hand(ZeeShotFx.warm())
			if shot_sound != null and is_instance_valid(shot_sound):
				var _layers_ready: bool = shot_sound.call(&"warm")
		Phase.MUZZLE:
			_warm_muzzle_flashes()
		Phase.BLOOD:
			_warm_blood()
		Phase.WEAPONS:
			_warm_weapon(item as ZeeWeaponArt)
		Phase.FX:
			_warm_fx_scene(str(item))
		Phase.ICONS:
			_warm_icon(item)


## Builds the body a spawn would, outside the tree: its scene, its entity script (loaded and
## compiled, not attached), its mesh and, for an NPC, its figure.
func _warm_prop(def: DotPropDef) -> void:
	if def == null:
		return
	var scene: Variant = load(def.scene_path) if def.scene_path != "" and ResourceLoader.exists(def.scene_path) else null
	_lap("prop.load")
	if not scene is PackedScene:
		return
	if PlaygroundSpawnables.kind_of(def) == PlaygroundSpawnables.Kind.ENTITY:
		var _script := PlaygroundSpawnables.load_script(def)
	_lap("prop.script")
	var node := (scene as PackedScene).instantiate()
	_lap("prop.instantiate")
	# An entity's scene is a bare body. Its own script would run its brain on configure's
	# heels; the prop script it extends builds the same mesh and figure and nothing else.
	if not node.has_method(&"configure") and node is RigidBody3D:
		node.set_script(PlaygroundProp)
	if node.has_method(&"configure"):
		node.call(&"configure", def)
	_lap("prop.configure")
	var figure := node.get_node_or_null(^"Figure")
	if figure != null:
		var _surfaces := DotSkinSurfaces.warm(figure)
	_lap("prop.skin")
	_hand(DotRenderWarmup.collect(node))
	_lap("prop.collect")
	node.free()
	_lap("prop.free")


## Draws the weapon into a spare view model and drops it again: the model file loads, its
## materials are made, and the reload parts are built once.
func _warm_weapon(art: ZeeWeaponArt) -> void:
	if art == null:
		return
	if _spare_view == null:
		_spare_view = ZeeViewModel.new()
		_spare_view.name = "PrewarmView"
	var equipped := _spare_view.equip(art)
	_lap("weapon.equip")
	if equipped.ok:
		_hand(DotRenderWarmup.collect(_spare_view))
	_lap("weapon.collect")
	_spare_view.clear()
	_lap("weapon.clear")
	if not _parts_warmed:
		_parts_warmed = true
		_spare_view.prewarm(art)
		_lap("weapon.parts")


func _warm_fx_scene(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var scene: Variant = load(path)
	if not scene is PackedScene:
		return
	var node := (scene as PackedScene).instantiate()
	_hand(DotRenderWarmup.collect(node))
	node.free()


## dot-fx's muzzle flashes: every flash scene loaded and pinned, and one of each size drawn on the camera until
## the gate opens, so the first shot loads and compiles nothing. Without a camera the scenes are still pinned.
func _warm_muzzle_flashes() -> void:
	if not DotMuzzleFlash.available():
		return
	var first: int = DotMuzzleFlash.FOLDERS.keys()[0]
	if not ResourceLoader.exists("%s%s01.tscn" % [DotMuzzleFlash.ROOT, DotMuzzleFlash.FOLDERS[first]]):
		return
	var cam := _camera()
	if cam == null:
		var _pinned := DotMuzzleFlash.pin_scenes(1 << 30)
		return
	var rig := DotMuzzleFlash.prewarm(cam)
	if rig != null:
		rig.position = Vector3(0.0, 0.0, -0.5)
		_keep_on_camera(rig)


## One blood splat built the way a hit builds it (a quad and its material on the web, a Decal elsewhere), in a
## pool of its own with the presentation's settings, and handed to the gate.
func _warm_blood() -> void:
	if blood == null or not is_instance_valid(blood):
		return
	var pool := DotFxDecals.new()
	pool.apply_config(blood.decals.config)
	var _splat := pool.splatter(Vector3.ZERO, Vector3.UP)
	_hand(DotRenderWarmup.collect(pool))
	pool.free()


## A shadowless omni light on the camera from the hold's release until the gate opens: the host's draw of every
## material then compiles its lit-by-omni variant too, which a muzzle flash's light would otherwise compile in play.
func _hold_light_probe() -> void:
	var cam := _camera()
	if cam == null or gate == null or gate.is_open() or not _shot_effects():
		return
	var light := OmniLight3D.new()
	light.name = "PrewarmLightProbe"
	light.omni_range = PROBE_RANGE
	light.light_energy = 0.01
	light.shadow_enabled = false
	cam.add_child(light)
	_keep_on_camera(light)


## [member PlaygroundConfig.prewarm_shot_effects]; off without a config.
func _shot_effects() -> bool:
	return config != null and config.prewarm_shot_effects


## Keeps [param node] until the gate opens (or this node goes), then frees it.
func _keep_on_camera(node: Node) -> void:
	if _on_camera.is_empty() and gate != null and not gate.opened.is_connected(_drop_camera_nodes):
		gate.opened.connect(_drop_camera_nodes, CONNECT_ONE_SHOT)
	_on_camera.append(node)
	if gate == null or gate.is_open():
		_drop_camera_nodes.call_deferred()


func _drop_camera_nodes() -> void:
	for node in _on_camera:
		if is_instance_valid(node):
			node.queue_free()
	_on_camera.clear()


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _warm_icon(item: Variant) -> void:
	if item is DotPropDef:
		var icon := PlaygroundIcons.for_def(item as DotPropDef)
		if icon != null and not _held_icons.has(icon):
			_held_icons.append(icon)
	elif item is PlaygroundWeaponDef:
		var def := item as PlaygroundWeaponDef
		if PlaygroundZee.is_zee(def):
			var _sprite := PlaygroundWeaponIcons.shared.menu_texture(PlaygroundZee.zee_id(def))
		var _drawn := PlaygroundIcons.for_weapon(def)


## Hands the gate [param items], less any whose shader (a material) or shaders and vertex formats (a mesh) were
## handed already: [BaseMaterial3D]s with the same features share one shader, so drawing the second compiles nothing.
func _hand(items: Array) -> void:
	var fresh: Array = []
	for item: Variant in items:
		var key := DotRenderWarmup.item_key(item, _key_cache)
		if key != "" and _keys.has(key):
			skipped += 1
			continue
		if key != "":
			_keys[key] = true
		fresh.append(item)
	if fresh.is_empty():
		return
	warmed += fresh.size()
	if gate != null:
		gate.warm_up(fresh)
