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

## The per-frame budget asked of [method DotLoadGate.slice_msec].
const SLICE_MS := 8

## Ids built even when the catalogue's shapes would not reach them: what the Launcher fires
## with nothing armed and what the spawn menu has selected before anybody picks.
const ALWAYS := [&"ball", &"crate"]

enum Phase { PROPS, SHOT_FX, WEAPONS, FX, ICONS, DONE }

## Fired on the frame after a pause: the run waits on this node, so a freed node is never resumed.
signal _frame

var gate: DotLoadGate = null
var config: PlaygroundConfig = null
var catalogue: DotPropCatalogue = null
var fx_catalogue: DotFxCatalogue = null

## True once every phase has run and the hold is released.
var finished: bool = false

## Materials and meshes handed to the gate, counted across phases.
var warmed: int = 0

## Milliseconds each phase took, by name: what the log line reports and a test reads.
var phase_ms: Dictionary = {}

var _slice: DotFrameSlice = null
var _spare_view: ZeeViewModel = null
var _parts_warmed := false
## Artwork icons are loaded with `load()` and not cached by the icon code: kept here until the
## game is over, so the spawn menu's first open finds them in the resource cache.
var _held_icons: Array[Texture2D] = []


## Starts the work and holds [member gate] until it is done. Returns false (nothing held) when
## [member config] turns it off.
func start() -> bool:
	if config != null and not config.prewarm:
		finished = true
		return false
	if gate != null:
		gate.hold(HOLD, "Getting things ready")
	_run()
	return true


## Every phase in turn, pausing a frame whenever the gate's budget is spent: at least one item a
## frame, so a budget of 0 still finishes.
func _run() -> void:
	for phase in range(Phase.DONE):
		var began := Time.get_ticks_usec()
		for item in _items_for(phase as Phase):
			if _slice == null:
				_slice = DotFrameSlice.new(gate.slice_msec(SLICE_MS) if gate != null else SLICE_MS)
			_warm_one(phase as Phase, item)
			if _slice.due():
				_slice = null
				get_tree().process_frame.connect(_frame.emit, CONNECT_ONE_SHOT)
				await _frame
		phase_ms[Phase.keys()[phase]] = (Time.get_ticks_usec() - began) / 1000
	_finish()


## The spare view lives outside the tree, so nothing frees it with this node: a game that ends
## before the warm-up does (a test, a quit on the loading screen) would leak it and its meshes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_spare_view()


func _free_spare_view() -> void:
	if _spare_view != null and is_instance_valid(_spare_view):
		_spare_view.free()
	_spare_view = null


func _finish() -> void:
	finished = true
	_free_spare_view()
	DotLog.info(CHANNEL, "warmed under the cover", {"items": warmed, "ms": phase_ms})
	if gate != null:
		gate.release(HOLD)


func _items_for(phase: Phase) -> Array:
	match phase:
		Phase.PROPS:
			return _prop_defs()
		Phase.SHOT_FX:
			return [null]
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
## and size, so one per mesh draws every shader they use. Model props load a scene file each and
## are built only when [member PlaygroundConfig.prewarm_model_props] says so.
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
	match phase:
		Phase.PROPS:
			_warm_prop(item as DotPropDef)
		Phase.SHOT_FX:
			_hand(ZeeShotFx.warm())
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
	if not scene is PackedScene:
		return
	if PlaygroundSpawnables.kind_of(def) == PlaygroundSpawnables.Kind.ENTITY:
		var _script := PlaygroundSpawnables.load_script(def)
	var node := (scene as PackedScene).instantiate()
	# An entity's scene is a bare body. Its own script would run its brain on configure's
	# heels; the prop script it extends builds the same mesh and figure and nothing else.
	if not node.has_method(&"configure") and node is RigidBody3D:
		node.set_script(PlaygroundProp)
	if node.has_method(&"configure"):
		node.call(&"configure", def)
	var figure := node.get_node_or_null(^"Figure")
	if figure != null:
		var _surfaces := DotSkinSurfaces.warm(figure)
	_hand(DotRenderWarmup.collect(node))
	node.free()


## Draws the weapon into a spare view model and drops it again: the model file loads, its
## materials are made, and the reload parts are built once.
func _warm_weapon(art: ZeeWeaponArt) -> void:
	if art == null:
		return
	if _spare_view == null:
		_spare_view = ZeeViewModel.new()
		_spare_view.name = "PrewarmView"
	var equipped := _spare_view.equip(art)
	if equipped.ok:
		_hand(DotRenderWarmup.collect(_spare_view))
	_spare_view.clear()
	if not _parts_warmed:
		_parts_warmed = true
		_spare_view.prewarm(art)


func _warm_fx_scene(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var scene: Variant = load(path)
	if not scene is PackedScene:
		return
	var node := (scene as PackedScene).instantiate()
	_hand(DotRenderWarmup.collect(node))
	node.free()


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


func _hand(items: Array) -> void:
	if items.is_empty():
		return
	warmed += items.size()
	if gate != null:
		gate.warm_up(items)
