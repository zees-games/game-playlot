extends RefCounted

## Workshop trails in solo play: the `trail` entries of subscribed packs, loaded into one
## dot-trail registry and worn by the local player as a ribbon.
##
## [b]dot-trail is the host's, not this game's.[/b] The shell carries the addon and a pack cannot
## ship its classes, so they are reached by name ([method script_named]) the way the shell's trail
## link does. A host without dot-trail lists no pack trails and logs why, instead of failing to parse.
##
## [b]A trail pack is data.[/b] Its `provides.json` names one `trail` entry per trail with
## `def: trails.json`; the directory that file sits in is loaded with `DotTrailStore.load_dir`,
## which reads the images as bytes (a data pack is not imported, so they are not resources).

const CHANNEL := "playlot.trails"

## The index kind this reads. Also listed in `accepts.kinds` so the site offers trail packs.
const KIND := &"trail"

## Name of the emitter node on the wearer, so equipping again replaces rather than stacks.
const EMITTER_NAME := "PackTrail"

const CLASSES: Array[String] = ["DotTrailRegistry", "DotTrailStore", "DotTrailEmitter"]

## The registry the last [method load_from] filled, or null.
var registry: RefCounted = null


## The script of global class [param class_id], or null when the host does not carry it.
static func script_named(class_id: String) -> Script:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == class_id:
			return load(str(entry.get("path", ""))) as Script
	return null


## Whether the host carries the dot-trail classes this needs.
static func available() -> bool:
	for class_id in CLASSES:
		if script_named(class_id) == null:
			return false
	return true


## Loads every visible `trail` entry of [param index] into a fresh registry and returns the entries
## whose trail loaded. Each pack directory is read once however many entries point into it.
func load_from(index: DotContentIndex) -> Array[DotContentEntry]:
	var out: Array[DotContentEntry] = []
	registry = null
	if index == null:
		return out
	var entries := index.entries(KIND)
	if entries.is_empty():
		return out
	if not available():
		DotLog.warn(CHANNEL, "pack trails need dot-trail in the host; not listed", {"entries": entries.size()})
		return out
	var fresh: RefCounted = script_named("DotTrailRegistry").new()
	var store: RefCounted = script_named("DotTrailStore").new(fresh)
	var dirs := {}
	for entry in entries:
		var dir := entry.path("def").get_base_dir()
		if dir == "" or dirs.has(dir):
			continue
		dirs[dir] = true
		var loaded: DotResult = store.call(&"load_dir", dir)
		if not loaded.ok:
			DotLog.warn(CHANNEL, "a trail pack could not be read", {"pack": entry.content_id, "why": loaded.error.message})
	for entry in entries:
		if fresh.call(&"get_def", entry.id) != null:
			out.append(entry)
		else:
			DotLog.debug(CHANNEL, "a trail entry names no loaded trail", {"key": entry.key})
	registry = fresh
	return out


## The trail's image as a texture for a menu card; null headless or when unknown.
func icon(trail_id: String) -> Texture2D:
	if registry == null or DisplayServer.get_name() == "headless":
		return null
	return registry.call(&"texture_for", trail_id) as Texture2D


## Puts trail [param trail_id] on [param wearer], replacing the one it wore. "" or "off" takes it off.
func equip(wearer: Node3D, trail_id: String) -> DotResult:
	if wearer == null or not is_instance_valid(wearer):
		return DotResult.fail(DotError.CODE_STATE, "no player to wear a trail")
	var worn := wearer.get_node_or_null(EMITTER_NAME)
	if trail_id == "" or trail_id == "off":
		if worn != null:
			worn.queue_free()
		return DotResult.success("off")
	if registry == null:
		return DotResult.fail(DotError.CODE_STATE, "no trail packs are mounted")
	var allowed: DotResult = registry.call(&"may_equip", trail_id, PackedStringArray())
	if not allowed.ok:
		return allowed
	if worn == null:
		worn = script_named("DotTrailEmitter").new() as Node3D
		worn.name = EMITTER_NAME
		worn.set(&"registry", registry)
		wearer.add_child(worn)
	else:
		worn.set(&"registry", registry)
	worn.call(&"set_trail", allowed.value)
	DotLog.info(CHANNEL, "trail equipped", {"trail": trail_id})
	return DotResult.success(trail_id)


## The loaded trail ids, for the console.
func ids() -> PackedStringArray:
	return PackedStringArray() if registry == null else registry.call(&"ids")
