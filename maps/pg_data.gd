extends "../game/playlot_map.gd"

const PlaylotGeometry := preload("../game/playlot_geometry.gd")
const PlaylotMaterials := preload("../game/playlot_materials.gd")
const PlaylotBoxBatch := preload("../game/playlot_box_batch.gd")

## A map that is a document: the one scene every custom sandbox map is built by.
##
## [b]Why a document and not a script.[/b] The built-in maps are `_build()`s full of
## constants, which is right for a map that ships inside this game. A map written for one
## server and delivered beside the game is a different thing: it lives in another pack
## (playlot-maps), mounted at its own prefix, and a script there that `extends`
## this game's map base by path names a path that is only right in one of the two places it
## runs — the family's mount constraint. A JSON document of boxes is data: both packs can be
## anywhere, a person can read it when a map will not load, and dot-map's catalogue lists it
## without loading anything.
##
## The document ([constant FORMAT] 1):
##
## [codeblock]
## {"format": 1, "kind": "playground_map", "id": "pgc_plots", "name": "Build Plots",
##  "map_kind": "sandbox", "tier": 1, "author": "...",
##  "spawn": [0, 1, 0], "spawn_yaw": 0,
##  "boxes": [{"at": [x, y, z], "size": [x, y, z], "colour": "floor" | "#rrggbb",
##             "turn": [ax, ay, az, degrees], "material": "ice"}],
##  "declared": [{"min": [x, y, z], "max": [x, y, z], "why": "..."}],
##  "props": [{"id": "door", "at": [x, y, z], "yaw": 90, "frozen": true,
##             "tint": "#rrggbb", "scale": 1.5,
##             "physics": {"gravity": true, "weight": 1, "friction": 0.2, "bounce": 0}}],
##  "wires": [{"from": 0, "out": "pressed", "to": 1, "in": "toggle"}],
##  "lighting": {"sun": {...}, "fog": {...}, "sky_top": [r, g, b]}}
## [/codeblock]
##
## `lighting` (optional) is a dot-lighting document, the keys `DotLightDocument` reads plus
## this game's `sky_top`; a map without one gets the game's daylight
## (`PlaylotLighting.DAYLIGHT`).
##
## A box's `material` (optional, 2026-10-07) is one of dot-physics' standard surfaces
## (`PlaylotMaterials`): concrete, metal, wood, glass, dirt, grass, sand, snow, ice, rock,
## mud, rubber, and the liquids water and lava. A solid one is drawn in its material's look
## unless it names a colour, slides and bounces as that material, and is that material to a
## player walking on it. A LIQUID is built with no collider at all, as a see-through volume
## the map records ([method liquid_volumes]): something is IN water, not on it. A liquid
## box may not be turned, because a volume is asked about as an axis-aligned box. Foliage is
## not solid either, and not a liquid: drawn, walked through, hidden in, recorded nowhere.
##
## A box with a `brush` (optional) is a [DotMapBrush] instead: `"brush": "stairs"` (wedge, ramp,
## arch, cylinder, cone, spike, quarter_pipe, slab_holes), `size` is the brush's bounding box,
## `params` its [code]{steps, segments, thickness, holes}[/code], and `at`, `turn`, `colour` and
## `material` read as for a box. Convex pieces collide; the survey (boxes only) does not see them.
##
## `world` (optional, 2026-11-15) names the converted world pack a map converted from a BSP is
## drawn with (dot-map-convert's mesh route): textured faces, terrain and sky where the boxes are
## flat colour. It is hide-n-seek's key, `{"pack": "pg_world_<id>", "metres_per_unit": S,
## "offset": [x, y, z]}` (the converter's ground shift, undone), or only the pack's name. The
## pack is read from beside the document, `<doc dir>/world/<pack>/<id>.json` and `.bin`. A
## client draws it in place of the box meshes ([method load_world]); the boxes still collide, so
## physics, the survey and a server are unchanged, and a pack that is missing, will not read or
## was made at another scale leaves the boxes drawn with a WARN.
##
## `props` and `wires` are optional (2026-10-07), so every older document still reads. A prop
## is a catalogue id, put down by the SERVER when the map loads ([method map_props]) and owned
## by nobody in particular (`Playlot.MAP_OWNER`): a door with a button beside it, a stack
## of barrels, planks at the top of a slope. Frozen unless it says otherwise, because map
## furniture that falls over on load is not furniture. A wire joins two of them by index
## through dot-props' DotPropIO, exactly as the tool gun's Wire mode does.
##
## A box is centred on `at` (the [method PlaylotGeometry.box] convention) and turned
## about its own centre. `declared` is [method survey_declared]: ground only a noclip
## reaches, with the reason.
##
## [b]Built by [method configure_doc], not in `_ready`[/b], for `pg_generated`'s reason:
## dot-map instantiates the shared scene and adds it, and the document is only known from
## the catalogue entry, which [Playlot] hands over from its `map_changed` handler before
## anybody is spawned.

const CHANNEL := "playlot.maps"

const FORMAT := 1
## The document kind a map is written with. It keeps the name from before the Playlot rename,
## because documents already shared and game-murder-mystery's reader carry it.
const KIND := "playground_map"
## Every kind a reader takes: [constant KIND], and the Playlot name a document may be written with next.
const KINDS: Array[String] = [KIND, "playlot_map"]

## The most boxes one map may hold, or 0 for no bound (the default: a whole converted map holds
## tens of thousands). A host that loads strangers' documents sets one; a document past it fails
## [method validate] by name, it is never cut short.
static var max_boxes: int = 0

## Whether the drawn world's static props are baked into per-cell batches (DotMapPropBatch) instead of one node each. A flag so
## the bench can A/B the same build (`--batch-props 0|1`). On since pgc_deadcity draws 4110 -> 2567 calls with it.
static var batch_props: bool = true

## How far from the origin anything may be, in metres. The wire's own extent is larger.
const MAX_EXTENT := 2000.0

## The most props one map may put down. Each is a rigid body on every client.
const MAX_PROPS := 300

const NAMED_COLOURS := {
	"floor": PlaylotGeometry.COLOUR_FLOOR,
	"ramp": PlaylotGeometry.COLOUR_RAMP,
	"start": PlaylotGeometry.COLOUR_START,
	"end": PlaylotGeometry.COLOUR_END,
	"platform": PlaylotGeometry.COLOUR_PLATFORM,
	"boost": PlaylotGeometry.COLOUR_BOOST,
	"float": PlaylotGeometry.COLOUR_FLOAT,
}

## The folder beside a document its world packs sit in. [method add_map_docs] reads only the
## top level of a maps folder, so nothing under it is taken for a map.
const WORLD_DIR := "world"

## The document this was built from, or empty before [method configure_doc].
var doc: Dictionary = {}

## Whether this map draws its document's `world` pack in place of the box meshes. A headless
## server or test draws nothing, so it never reads one; a test that wants one sets this.
var draw_world: bool = DisplayServer.get_name() != "headless"

## Milliseconds of world build between frames ([DotFrameSlice]), so a map that loads during
## play does not freeze a frame on the web. 0 builds it in one call.
var world_slice_ms: int = 40

## The drawn world pack, or null while the boxes are what is seen.
var drawn_world: DotMapDrawnWorld = null

## The drawn world's credit line (its author, and the art whose licence asks for a name).
var world_credits: String = ""

var _doc_path := ""
var _world_loading := false
var _built := false
var _declared: Array = []
var _liquids: Array = []


func _ready() -> void:
	# Deliberately not `_build()`. See the class note.
	pass


## Reads [param path] and builds the map it describes. Idempotent. A document that does not
## read leaves the fallback floor, so a broken custom map is a flat plate with a WARN rather
## than a player falling through nothing.
func configure_doc(path: String) -> DotResult:
	if _built:
		return DotResult.success(self)
	_built = true

	var read := read_doc(path)
	if not read.ok:
		DotLog.warn(CHANNEL, "a map document did not load; building a bare floor",
			{"path": path, "why": read.error.message})
		_build_fallback()
		return read

	doc = read.value
	_doc_path = path
	_liquids = build_into(self, doc)
	PlaylotBoxBatch.build(self)
	if _shades_boxes():
		add_contact_shade()
	fallback_spawn = _vec(doc.get("spawn", [0, 1, 0]))
	_declared = declared_of(doc)
	if draw_world and not world_spec(doc).is_empty():
		# Not awaited: the boxes are the map from here on, and the pack replaces their look when
		# it has been read and built.
		load_world()
	return DotResult.success(self)


# --- The drawn world ------------------------------------------------------------

## Whether the box meshes are what is seen, so they want dot-lighting's contact shade. A
## document with a world pack is seen through the pack ([method attach_world] drops the shade),
## and a headless server sees nothing: building the shade there is all cost. It is not cheap:
## gm_fork's 21,329 boxes took two minutes of it on the build box, and timed out a suite. A
## pack that does not load gets the shade then ([method _boxes_stay_drawn]).
func _shades_boxes() -> bool:
	if world_spec(doc).is_empty():
		return true
	return not draw_world and DisplayServer.get_name() != "headless"


## The world pack did not load, so the boxes stay what is seen: shade them as a map without a
## pack would have been.
func _boxes_stay_drawn() -> void:
	if get_node_or_null(^"ContactShade") == null:
		add_contact_shade()


## The document's `world` as `{pack, offset: Vector3, metres_per_unit: float (0 unchecked)}`,
## or empty when it names none. Read from a checked document.
static func world_spec(d: Dictionary) -> Dictionary:
	var raw: Variant = d.get("world")
	if raw is String:
		return {"pack": raw, "offset": Vector3.ZERO, "metres_per_unit": 0.0}
	if raw is Dictionary:
		var w: Dictionary = raw
		return {
			"pack": str(w["pack"]),
			"offset": _vec(w["offset"]) if w.has("offset") else Vector3.ZERO,
			"metres_per_unit": float(w.get("metres_per_unit", 0.0)),
		}
	return {}


## Where the pack of [param spec] for map [param id] is, beside the document at [param doc_path]:
## the path without `.json`, as [method DotMapBspMesh.load_prefix] takes it.
static func world_prefix(doc_path: String, spec: Dictionary, id: String) -> String:
	return doc_path.get_base_dir().path_join(WORLD_DIR).path_join(str(spec["pack"])).path_join(id)


## Reads the document's world pack and draws it in place of the box meshes (dot-map's
## [DotMapDrawnWorld], as hide-n-seek and zombie-zone draw theirs). Succeeds with true when the
## world is drawn, false when there is none to draw; anything else leaves the boxes drawn.
func load_world() -> DotResult:
	var spec := world_spec(doc)
	if not draw_world or spec.is_empty() or drawn_world != null or _world_loading:
		return DotResult.success(false)
	var id := str(doc["id"])
	var prefix := world_prefix(_doc_path, spec, id)
	if not FileAccess.file_exists(prefix + ".json"):
		DotLog.warn(CHANNEL, "a map names a world pack that is not here; its boxes are drawn",
			{"map": id, "at": prefix})
		_boxes_stay_drawn()
		return DotResult.fail(DotError.CODE_IO, "No world pack at %s." % prefix)
	_world_loading = true
	var read: DotResult = await DotMapDrawnWorld.read(prefix, DotRegistry.get_service(&"dot_cloud_client"))
	if not read.ok:
		_world_loading = false
		DotLog.warn(CHANNEL, "a map's world pack would not read; its boxes are drawn",
			{"map": id, "at": prefix, "why": read.error.message})
		_boxes_stay_drawn()
		return read
	var world: DotMapBspMesh = read.value
	var wanted := float(spec["metres_per_unit"])
	var made := float((world.manifest.get("units", {}) as Dictionary).get("metres_per_unit", 0.0))
	if wanted > 0.0 and absf(made - wanted) > 1e-5:
		_world_loading = false
		DotLog.warn(CHANNEL, "a map's world pack was made at another scale; its boxes are drawn",
			{"map": id, "pack": made, "doc": wanted})
		_boxes_stay_drawn()
		return DotResult.fail(DotError.CODE_INVALID, "World pack %s is at %s metres a unit, the document %s." % [prefix, made, wanted])
	var drawn: DotMapDrawnWorld = await attach_world(world, spec["offset"], is_original(spec))
	_world_loading = false
	return DotResult.success(drawn != null)


## Lays [param world] over the map at [param offset] and hides what it replaces: every box and
## brush mesh but a see-through one (glass the pack does not draw, and a pane that breaks
## must vanish), and the contact shade under them. Their bodies stay: the pack is only what is
## seen. Liquids stay drawn. Null when the map went away during the build.
## [param original] draws the map's own textures the pack carries (the `_orig` variant).
## Props and vegetation the pack places are drawn too.
func attach_world(world: DotMapBspMesh, offset: Vector3, original: bool = false) -> DotMapDrawnWorld:
	var environment: Environment = null
	var lamps: Array = []
	for child in get_children():
		if child is WorldEnvironment:
			environment = (child as WorldEnvironment).environment
		elif child is OmniLight3D:
			lamps.append(child)
	var options := {
		"transform": Transform3D(Basis.IDENTITY, offset),
		"environment": environment,
		"lamps": lamps,
		"cloud": DotRegistry.get_service(&"dot_cloud_client"),
		"props": true,
		"batch_props": batch_props,
		"original_textures": original,
	}
	var drawn: DotMapDrawnWorld = null
	if world_slice_ms > 0:
		drawn = await DotMapDrawnWorld.attach_async(self, world, options, DotFrameSlice.new(world_slice_ms))
	else:
		drawn = DotMapDrawnWorld.attach(self, world, options)
	if drawn == null:
		return null
	var hidden := hide_box_meshes()
	var shade := get_node_or_null(^"ContactShade")
	if shade != null:
		remove_child(shade)
		shade.queue_free()
	drawn_world = drawn
	world_credits = drawn.credits
	DotLog.info(CHANNEL, "the map is drawn from its world pack",
		{"map": str(doc.get("id", "")), "hidden": hidden, "lit": drawn.lit != null, "credits": world_credits})
	return drawn


## Hides the meshes of this map's boxes and brushes, but a see-through one's, and returns how
## many. Their collision shapes are untouched.
func hide_box_meshes() -> int:
	var hidden := 0
	for child in get_children():
		if child.is_in_group(PlaylotBoxBatch.GROUP):
			if (child as Node3D).visible:
				(child as Node3D).visible = false
				hidden += child.get_child_count()
			continue
		if not (child is StaticBody3D and child.has_meta(&"pg_box")):
			continue
		if PlaylotMaterials.look(String(PlaylotMaterials.material_of(child)), Color.WHITE).a < 0.999:
			continue
		for part in child.get_children():
			if part is GeometryInstance3D and (part as GeometryInstance3D).visible:
				(part as GeometryInstance3D).visible = false
				hidden += 1
	return hidden


## The yaw a player spawns facing, in degrees. Read by [Playlot] beside the spawn.
func spawn_yaw() -> float:
	return float(doc.get("spawn_yaw", 0.0))


func spawn_yaw_for(_track: int) -> float:
	return spawn_yaw()


func survey_declared() -> Array:
	return _declared


## The liquids in this map: `[{box: AABB, material, index}]`, world space (a map's node is
## at the origin). What Playlot asks for lava and water.
func liquid_volumes() -> Array:
	return _liquids


## The props this map puts down when it loads. See the class note; spawned by [Playlot].
func map_props() -> Array:
	return doc.get("props", [])


func map_wires() -> Array:
	return doc.get("wires", [])


## The toys this map puts down (dot-props' placements), from the document's `toys`.
func map_toys() -> Array:
	return doc.get("toys", [])


func _build_fallback() -> void:
	PlaylotGeometry.light(self)
	PlaylotGeometry.box(self, Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	fallback_spawn = Vector3(0.0, 1.0, 0.0)


# --- The document --------------------------------------------------------------

## Reads and checks a map document.
static func read_doc(path: String) -> DotResult:
	if not FileAccess.file_exists(path):
		return DotResult.fail(DotError.CODE_IO, "No map document at %s." % path)
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "%s is not a JSON object." % path)
	return validate(parsed)


## Whether a document's world [param spec] (from [method world_spec]) is the original variant:
## its pack ends in dot-map's `_orig` mark and carries the map's own textures.
static func is_original(spec: Dictionary) -> bool:
	return str(spec.get("pack", "")).ends_with(DotMapLocalMaps.ORIG_MARK)


## Whether a document is one this builds. Every field is checked before anything is built,
## so a bad map is refused whole rather than half drawn.
static func validate(d: Dictionary) -> DotResult:
	if int(d.get("format", 0)) != FORMAT or not KINDS.has(str(d.get("kind", ""))):
		return DotResult.fail(DotError.CODE_VERSION,
			"Not a playlot map document of format %d." % FORMAT)
	var id := str(d.get("id", ""))
	if not id.is_valid_identifier():
		return DotResult.fail(DotError.CODE_INVALID, "A map id must be an identifier, not \"%s\"." % id)
	if not _is_vec(d.get("spawn")):
		return DotResult.fail(DotError.CODE_INVALID, "Map %s has no spawn." % id)
	var boxes: Variant = d.get("boxes")
	if not (boxes is Array) or (boxes as Array).is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "Map %s needs at least 1 box." % id)
	if max_boxes > 0 and (boxes as Array).size() > max_boxes:
		return DotResult.fail(DotError.CODE_INVALID, "Map %s has %d boxes, past this host's max_boxes %d." % [
			id, (boxes as Array).size(), max_boxes])
	for i in (boxes as Array).size():
		var b: Variant = boxes[i]
		if not (b is Dictionary) or not _is_vec(b.get("at")) or not _is_vec(b.get("size")):
			return DotResult.fail(DotError.CODE_INVALID, "Map %s: box %d needs at and size." % [id, i])
		var size := _vec(b["size"])
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			return DotResult.fail(DotError.CODE_INVALID, "Map %s: box %d has no volume." % [id, i])
		if _vec(b["at"]).length() > MAX_EXTENT:
			return DotResult.fail(DotError.CODE_INVALID, "Map %s: box %d is out of the world." % [id, i])
		if b.has("turn") and not (b["turn"] is Array and (b["turn"] as Array).size() == 4):
			return DotResult.fail(DotError.CODE_INVALID, "Map %s: box %d's turn is [axis x, y, z, degrees]." % [id, i])
		if b.has("brush"):
			var spec := {"kind": str(b["brush"]), "size": b["size"], "params": b.get("params", {})}
			var ok := DotMapBrush.validate(spec)
			if not ok.ok:
				return DotResult.fail(DotError.CODE_INVALID, "Map %s: box %d's brush: %s" % [id, i, ok.error.message])
			if PlaylotMaterials.is_volume(str(b.get("material", ""))):
				return DotResult.fail(DotError.CODE_INVALID, "Map %s: box %d is a brush and a liquid; a brush is solid." % [id, i])
		if b.has("material"):
			var material := str(b["material"])
			if not PlaylotMaterials.is_known(material):
				return DotResult.fail(DotError.CODE_INVALID, "Map %s: box %d is made of %s, which is not a material." % [id, i, material])
			if PlaylotMaterials.is_liquid(material) and b.has("turn"):
				return DotResult.fail(DotError.CODE_INVALID, "Map %s: box %d is %s and turned; a liquid is an axis-aligned volume." % [id, i, material])
	if d.has("lighting") and not (d["lighting"] is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "Map %s: lighting is a dot-lighting document (an object)." % id)
	if d.has("world"):
		var bad := _world_fault(d["world"])
		if bad != "":
			return DotResult.fail(DotError.CODE_INVALID, "Map %s: world %s" % [id, bad])
	var props: Variant = d.get("props", [])
	if not (props is Array) or (props as Array).size() > MAX_PROPS:
		return DotResult.fail(DotError.CODE_INVALID, "Map %s: props is a list of at most %d." % [id, MAX_PROPS])
	for i in (props as Array).size():
		var p: Variant = props[i]
		if not (p is Dictionary) or str(p.get("id", "")) == "" or not _is_vec(p.get("at")):
			return DotResult.fail(DotError.CODE_INVALID, "Map %s: prop %d needs an id and at." % [id, i])
		if _vec(p["at"]).length() > MAX_EXTENT:
			return DotResult.fail(DotError.CODE_INVALID, "Map %s: prop %d is out of the world." % [id, i])
	var wires: Variant = d.get("wires", [])
	if not (wires is Array):
		return DotResult.fail(DotError.CODE_INVALID, "Map %s: wires is a list." % id)
	for i in (wires as Array).size():
		var w: Variant = wires[i]
		var count := (props as Array).size()
		if not (w is Dictionary) or int(w.get("from", -1)) < 0 or int(w.get("from", -1)) >= count \
				or int(w.get("to", -1)) < 0 or int(w.get("to", -1)) >= count \
				or str(w.get("out", "")) == "" or str(w.get("in", "")) == "":
			return DotResult.fail(DotError.CODE_INVALID, "Map %s: wire %d needs from, out, to and in, naming props." % [id, i])
	return DotResult.success(d)


## Builds a checked document's boxes under [param parent], and returns its liquid volumes:
## `[{box: AABB, material: StringName, index: int}]`.
static func build_into(parent: Node3D, d: Dictionary) -> Array:
	PlaylotGeometry.light(parent, d.get("lighting", {}))
	var liquids: Array = []
	var volume_groups := {}
	var boxes: Array = d.get("boxes", [])
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		var material := str(b.get("material", ""))
		var colour := colour_of(b.get("colour", "floor")) if b.has("colour") or material == "" \
			else PlaylotMaterials.look(material, PlaylotGeometry.COLOUR_FLOOR)
		if material != "" and b.has("colour") and PlaylotMaterials.look(material, Color.WHITE).a < 0.999:
			# A see-through material keeps its transparency in a mapper's own colour.
			colour.a = PlaylotMaterials.look(material, Color.WHITE).a
		var at := _vec(b["at"])
		var size := _vec(b["size"])
		if material != "" and PlaylotMaterials.is_volume(material):
			var vbasis := Basis.IDENTITY
			if b.has("turn"):
				var t: Array = b["turn"]
				var axis := Vector3(float(t[0]), float(t[1]), float(t[2]))
				if axis.length() > 0.0:
					vbasis = Basis(axis.normalized(), deg_to_rad(float(t[3])))
			var cell := Vector2i(floori(at.x / VOLUME_CELL), floori(at.z / VOLUME_CELL))
			var key := [colour, cell]
			if not volume_groups.has(key):
				volume_groups[key] = {"first": i, "xforms": [], "sizes": [], "colour": colour}
			(volume_groups[key]["xforms"] as Array).append(Transform3D(vbasis, at))
			(volume_groups[key]["sizes"] as Array).append(size)
			if PlaylotMaterials.is_liquid(material):
				liquids.append({"box": AABB(at - size * 0.5, size), "material": StringName(material), "index": i})
			continue
		var basis := Basis.IDENTITY
		if b.has("turn"):
			var t: Array = b["turn"]
			var axis := Vector3(float(t[0]), float(t[1]), float(t[2]))
			if axis.length() > 0.0:
				basis = Basis(axis.normalized(), deg_to_rad(float(t[3])))
		var body: StaticBody3D
		if b.has("brush"):
			body = DotMapBrush.build_body({"kind": str(b["brush"]), "size": b["size"],
				"params": b.get("params", {})}, PlaylotGeometry._material(colour))
			body.transform = Transform3D(basis, at)
			parent.add_child(body)
		else:
			body = PlaylotGeometry.box(parent, at, size, colour, basis)
		body.set_meta(&"pg_box", i)
		if material != "":
			PlaylotMaterials.apply(body, material)
	for group: Dictionary in volume_groups.values():
		parent.add_child(_volume_batch(group))
	return liquids


## Side of a cell, in metres, that same-look liquid and foliage volumes are folded within.
const VOLUME_CELL := 64.0


## The volumes of one look in one cell, drawn as ONE mesh and nothing else: no body, so nothing
## stands on it and the survey (which reads static bodies) sees the bed under it. Named for the
## group's first box (`Liquid<index>`); the `liquid_volumes` records still list every box.
static func _volume_batch(group: Dictionary) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var unit := BoxMesh.new()
	var xforms: Array = group["xforms"]
	var sizes: Array = group["sizes"]
	for n in xforms.size():
		unit.size = sizes[n]
		var arrays := unit.get_mesh_arrays()
		var xf: Transform3D = xforms[n]
		var base := verts.size()
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			verts.append(xf * v)
		for nv: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
			normals.append(xf.basis * nv)
		uvs.append_array(arrays[Mesh.ARRAY_TEX_UV])
		for ix: int in arrays[Mesh.ARRAY_INDEX]:
			indices.append(base + ix)
	var data := []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = verts
	data[Mesh.ARRAY_NORMAL] = normals
	data[Mesh.ARRAY_TEX_UV] = uvs
	data[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	var mesh := MeshInstance3D.new()
	mesh.name = "Liquid%d" % int(group["first"])
	mesh.mesh = array_mesh
	mesh.material_override = PlaylotGeometry._material(group["colour"])
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Water, lava and foliage have no collider by design: a body is swum or pushed through,
	# not stood on, and the bed under it is solid. The audit's lenient pass would pass it on
	# the bed's shape; this says it is meant.
	mesh.set_meta(DotCollisionAudit.META, true)
	return mesh


## What is wrong with a document's `world`, or empty. A pack is a folder name, never a path, so a
## document cannot reach outside its own folder.
static func _world_fault(raw: Variant) -> String:
	var pack := ""
	if raw is String:
		pack = raw
	elif raw is Dictionary:
		var w: Dictionary = raw
		pack = str(w.get("pack", ""))
		if w.has("offset") and not _is_vec(w["offset"]):
			return "offset is [x, y, z]."
		if w.has("offset") and _vec(w["offset"]).length() > MAX_EXTENT:
			return "offset is out of the world."
		if w.has("metres_per_unit") and not (w["metres_per_unit"] is float or w["metres_per_unit"] is int):
			return "metres_per_unit is a number."
		if w.has("metres_per_unit") and float(w["metres_per_unit"]) <= 0.0:
			return "metres_per_unit is above 0."
	else:
		return "is a pack name or {pack, metres_per_unit, offset}."
	if pack == "" or not pack.is_valid_filename() or pack.begins_with("."):
		return "pack \"%s\" is not a folder name." % pack
	return ""


static func declared_of(d: Dictionary) -> Array:
	var out: Array = []
	for entry: Variant in d.get("declared", []):
		if entry is Dictionary and _is_vec(entry.get("min")) and _is_vec(entry.get("max")):
			var lo := _vec(entry["min"])
			out.append({"box": AABB(lo, _vec(entry["max"]) - lo), "why": str(entry.get("why", ""))})
	return out


static func colour_of(value: Variant) -> Color:
	var name := str(value)
	if NAMED_COLOURS.has(name):
		return NAMED_COLOURS[name]
	if name.begins_with("#") and Color.html_is_valid(name):
		return Color.html(name)
	return PlaylotGeometry.COLOUR_FLOOR


static func _is_vec(v: Variant) -> bool:
	return v is Array and (v as Array).size() == 3


static func _vec(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
