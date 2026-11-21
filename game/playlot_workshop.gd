extends RefCounted

const PlaylotPaths := preload("playlot_paths.gd")
const PlaylotSpawnables := preload("playlot_spawnables.gd")
const PlaylotTrails := preload("playlot_trails.gd")
const PlaylotWeaponDef := preload("weapons/playlot_weapon_def.gd")
const PlaylotZee := preload("playlot_zee.gd")

## The Workshop in solo play: what a player subscribed to, offered on the Q menu.
##
## [b]One adapter, because only the weapon half has an addon behind it.[/b] gs-weapon's
## [GSWeaponCatalogue] follows the content index itself, so weapons come from its
## [method GSWeaponCatalogue.listings]. gs-props and gs-npc have no `follow_content` yet, so the
## prop, npc and entity entries are read off [GSContentIndex] here and turned into the
## [GSPropDef]s the sandbox already spawns. [b]Follow-up for the addons:[/b] when
## [GSPropCatalogue] and [GSNpcCatalogue] grow `follow_content`, the `_prop_def` half of this file
## goes and what stays is the sandbox-specific part (an entity is a prop that runs a script).
##
## [b]Pack entries are added to the game's own lists and tagged, never kept in a second list.[/b]
## A pack prop is an ordinary row in the prop catalogue (so the spawner, the budget, undo and a
## saved build all treat it as one) with `meta.pack`; a pack weapon is an ordinary
## [PlaylotWeaponDef] in `Playlot.weapons`. The Q menu filters the tagged ones out of its own
## tabs and shows them in a tab per pack ([method rows]).
##
## [b]Solo only, and not because this class checks.[/b] The caller decides to follow at all: a
## dedicated server and a connected client never do, and the index's session tag then hides
## everything again for a solo game that goes online ([method GSContentIndex.set_session]). Ids
## are prefixed [constant ID_PREFIX] so a pack can never replace one of the game's own.

const CHANNEL := "playlot.workshop"

## Prefixed onto every pack row's id. A pack that ships a `crate` does not get to shadow ours.
const ID_PREFIX := "ws_"

## The kinds of pack row this game turns into something spawnable.
const SPAWN_KINDS: Array[StringName] = [&"prop", &"npc", &"entity"]

## Colour of a pack weapon's generated icon when its pack ships no thumbnail.
const FALLBACK_COLOUR := Color(0.62, 0.68, 0.78)

## The visible pack content changed in any way, including a session switch.
signal changed

var index: GSContentIndex = null

## The pack weapons, read through gs-weapon. No code weapons: the game's own stay in `weapons`.
var weapon_catalogue: GSWeaponCatalogue = null

## The pack trails (kind `trail`), worn rather than spawned. See [code]playlot_trails.gd[/code].
var trails := PlaylotTrails.new()

var _props: GSPropCatalogue = null
var _weapons: Array[PlaylotWeaponDef] = []
var _added_props: Array[StringName] = []
var _rows: Array[Dictionary] = []
var _signature: String = ""


## Follows [param p_index] (default: the shared one), filling [param p_props] and
## [param p_weapons] in place so whatever holds those arrays keeps the same ones.
func follow(
	p_index: GSContentIndex, p_props: GSPropCatalogue, p_weapons: Array[PlaylotWeaponDef]
) -> void:
	unfollow()
	index = p_index if p_index != null else GSContentIndex.shared()
	_props = p_props
	_weapons = p_weapons
	weapon_catalogue = GSWeaponCatalogue.new()
	weapon_catalogue.follow_content(index)
	weapon_catalogue.listings_changed.connect(sync)
	index.pack_added.connect(_on_index_changed)
	index.session_changed.connect(_on_index_changed)
	sync()


func unfollow() -> void:
	if index != null:
		if index.pack_added.is_connected(_on_index_changed):
			index.pack_added.disconnect(_on_index_changed)
		if index.session_changed.is_connected(_on_index_changed):
			index.session_changed.disconnect(_on_index_changed)
	if weapon_catalogue != null:
		weapon_catalogue.listings_changed.disconnect(sync)
		weapon_catalogue.unfollow_content()
	index = null
	weapon_catalogue = null
	_clear()
	if _signature != "":
		_signature = ""
		changed.emit()


func _on_index_changed(_a: Variant = null, _b: Variant = null) -> void:
	sync()


## What the Q menu shows, one dictionary per pack row: `kind`, `id` (what the menu emits),
## `name`, `pack` (content id), `pack_title`, `category` (display name), `icon` (a texture, or
## null for the menu to draw one), `tip`. A `trail` row also carries `trail`, the trail's own id.
func rows() -> Array[Dictionary]:
	return _rows


func _clear() -> void:
	if _props != null:
		for id in _added_props:
			_props.remove(id)
	_added_props.clear()
	for i in range(_weapons.size() - 1, -1, -1):
		if _weapons[i].meta.has("pack"):
			_weapons.remove_at(i)
	_rows = []
	PlaylotZee.set_pack_defs([])


## Rebuilds the pack rows from the index for its current session. Idempotent: the signal goes out
## only when the visible set changed.
func sync() -> void:
	if index == null:
		return
	_clear()
	var titles := _category_names()

	for listing in weapon_catalogue.listings():
		if not listing.is_delivered() or listing.def == null:
			continue
		var def := _weapon_def(listing)
		_weapons.append(def)
		_rows.append(_row(&"weapon", def.id, listing.display_name, listing.content_id,
			listing.pack_title, titles.get(listing.content_id + "/" + listing.category, listing.category),
			listing.icon(), def.description, def))
	PlaylotZee.set_pack_defs(_weapons.filter(func(d: PlaylotWeaponDef) -> bool: return d.meta.has("pack")))

	for kind in SPAWN_KINDS:
		for entry in index.entries(kind):
			var def := _prop_def(entry)
			if def == null:
				continue
			if _props.has(def.id):
				continue
			var added := _props.add(def)
			if not added.ok:
				GSLog.warn(CHANNEL, "a pack row could not be catalogued", {
					"key": entry.key, "why": added.error.message,
				})
				continue
			_added_props.append(def.id)
			var icon: Texture2D = null
			if def.icon_path != "" and ResourceLoader.exists(def.icon_path):
				icon = load(def.icon_path) as Texture2D
			_rows.append(_row(kind, def.id, def.name_or_id(), entry.content_id, entry.pack_title,
				titles.get(entry.content_id + "/" + entry.category, entry.category), icon, "", def))

	for entry in trails.load_from(index):
		_rows.append(_row(PlaylotTrails.KIND, StringName(ID_PREFIX + "trail_" + entry.id), entry.name if entry.name != "" else entry.id,
			entry.content_id, entry.pack_title, titles.get(entry.content_id + "/" + entry.category, entry.category),
			trails.icon(entry.id), "Wear it: click, or `trail %s` in the console" % entry.id, null))
		_rows[_rows.size() - 1]["trail"] = entry.id

	var sig := ",".join(_rows.map(func(r: Dictionary) -> String: return String(r["id"])))
	if sig == _signature:
		return
	_signature = sig
	GSLog.debug(CHANNEL, "pack content changed", {"rows": _rows.size(), "session": String(index.session())})
	changed.emit()


func _row(
	kind: StringName, id: StringName, p_name: String, pack: String, title: String,
	category: String, icon: Texture2D, text: String, def: Object
) -> Dictionary:
	return {
		"kind": kind, "id": id, "name": p_name, "pack": pack,
		"pack_title": title if title != "" else pack, "category": category if category != "" else "Other",
		"icon": icon, "def": def,
		"tip": "%s\n%s%s\nFrom %s" % [p_name, String(kind).capitalize(), ("\n" + text) if text != "" else "", title if title != "" else pack],
	}


## Category display names from every visible pack's `provides.categories`, keyed
## `<content_id>/<category id>`.
func _category_names() -> Dictionary:
	var out := {}
	for pack in index.packs():
		var provides: Variant = pack.get("provides", {})
		if not (provides is Dictionary):
			continue
		for each: Variant in (provides as Dictionary).get("categories", []):
			if each is Dictionary:
				out["%s/%s" % [pack.get("content_id", ""), (each as Dictionary).get("id", "")]] = str((each as Dictionary).get("name", ""))
	return out


## A listing as the game's own weapon definition. A zee-shaped weapon is the one thing this game
## can hold besides its toys, so `meta.zee` names it for the rig, and `meta.pack_def` hands the rig
## the pack's definition for an id the built-in catalogue does not have ([method PlaylotZee.catalogue_for]).
func _weapon_def(listing: GSWeaponListing) -> PlaylotWeaponDef:
	var def := PlaylotWeaponDef.make(StringName(ID_PREFIX + String(listing.id)), listing.display_name, "")
	def.description = listing.def.description
	def.category = StringName(listing.category if listing.category != "" else "other")
	def.colour = PlaylotZee.SLOT_COLOURS.get(listing.slot, FALLBACK_COLOUR)
	def.meta = {
		"zee": String(listing.id), "slot": listing.slot, "pack": listing.content_id,
		"pack_title": listing.pack_title, "pack_def": listing.def,
	}
	return def


## One index entry of kind prop, npc or entity as a spawnable, or null when its shape is not one
## this game understands (logged at DEBUG: a newer pack on an older game is normal).
func _prop_def(entry: GSContentEntry) -> GSPropDef:
	var made: GSPropDef = null
	var kind := entry.kind
	var script_path := entry.path("script")
	var def_path := entry.path("def")
	var loaded: Resource = null
	if def_path != "" and ResourceLoader.exists(def_path):
		loaded = load(def_path)

	if loaded is GSPropDef:
		made = (loaded as GSPropDef).duplicate() as GSPropDef
	elif kind == &"prop" and entry.path("scene") != "":
		made = GSPropDef.make(StringName(entry.id), entry.path("scene"))
	elif kind != &"prop" and (script_path != "" or loaded is GSNpcDef):
		# An entity is a bare body running a script named by path; an npc def alone gets the
		# wanderer, the one NPC script that needs no tuning.
		made = GSPropDef.make(StringName(entry.id), PlaylotSpawnables.SCENE_ENTITY)
		if script_path == "":
			script_path = PlaylotPaths.rebase("res://game/entities/npc_wanderer.gd")
		made.meta = {"kind": "entity", "script": script_path, "shape": "box", "extent": [0.8, 1.7, 0.8]}
		made.mass = 80.0
		made.cost = 5
		if loaded is GSNpcDef:
			var npc_def := loaded as GSNpcDef
			made.meta["sight"] = npc_def.sight_range
			made.meta["hearing"] = npc_def.hearing_range
	else:
		GSLog.debug(CHANNEL, "a pack row has a shape this game does not spawn", {"key": entry.key})
		return null

	made.id = StringName(ID_PREFIX + entry.id)
	made.display_name = entry.name if entry.name != "" else made.display_name
	if kind != &"prop":
		made.category = &"npcs" if kind == &"npc" else &"entities"
		made.limit_group = &"npcs" if kind == &"npc" else &"entities"
		if not made.meta.has("kind"):
			made.meta["kind"] = "entity"
	made.icon_path = entry.path("thumbnail")
	made.meta["pack"] = entry.content_id
	made.meta["pack_title"] = entry.pack_title
	return made


## The `map_kind`s of subscribed maps this game lists: `accepts.map_kinds` in `provides.json`, which
## is also what the site offers a pack by, so there is one list.
static func accepted_map_kinds() -> PackedStringArray:
	var out := PackedStringArray()
	var path := PlaylotPaths.rebase("res://provides.json")
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var accepts: Variant = (parsed as Dictionary).get("accepts") if parsed is Dictionary else null
	var kinds: Variant = (accepts as Dictionary).get("map_kinds") if accepts is Dictionary else null
	if not (kinds is Array):
		kinds = ["sandbox", "surf", "bhop"]
	for kind: Variant in (kinds as Array):
		out.append(str(kind))
	return out
