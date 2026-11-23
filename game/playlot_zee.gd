extends RefCounted

const PlaylotPaths := preload("playlot_paths.gd")
const PlaylotWeaponDef := preload("weapons/playlot_weapon_def.gd")
const PlaylotZeeSelf := preload("playlot_zee.gd")
## Zee's art, models and sounds ([code]playlot_zee_art.gd[/code]).
const Art := preload("playlot_zee_art.gd")

## zee-gs-weapons in the sandbox, when the player has it: twenty-seven real weapons beside the toys.
##
## [b]A second kind of weapon, not a SWEP with a gun painted on.[/b] `PlaylotWeapon` is a
## prop tool: two edge-triggered buttons and a float delta, run where the input is. A zee
## weapon is gs-weapon's: a held-button command per integer tick, its own cadence, reload
## and ammunition, and an outcome full of shots that the game resolves. So the menu, the shop
## and the loadout see one list of [PlaylotWeaponDef]s, and `meta.zee` says which machinery is
## behind an entry.
##
## [b]Optional, and this file is the only door.[/b] The pack does not require zee-gs-weapons:
## the client shell does not carry it, and a Workshop subscription overlays it at
## `res://addons/zee_weapons/` before the game starts. So nothing under `game/` or `scenes/`
## names a Zee class: this file loads Zee's scripts by path after [method available], holds
## them untyped and calls them by name. Without zee, [method defs] is empty, [method arm]
## returns null, NPCs stand unarmed, the view and HUD draw no gun and the net schema is the
## same ([method net_specs] never asks zee), so a server and a client may differ in having it.
## `examples/headless_zee_optional.gd` holds both halves.
##
## [b]A shot hurts only when the arena is on.[/b] A sandbox is not a deathmatch, and a
## weapon pack is not a reason to make it one: with `pg_arena 0` a shot shoves the prop it
## hits — something to do with a gun in a sandbox — and touches nobody. The arena's
## gs-combat resolves the same shot when it is on, through [member PlaylotNetBridge.shot_fn].

const CHANNEL := "playlot.zee"

## Where a subscribed (or linked) zee-gs-weapons lives. The one literal path to it in the game.
const ZEE_DIR := "res://addons/zee_weapons/"
## The script whose presence means zee is here.
const PROBE := "runtime/zee_weapon_rig.gd"

## Zee's rig roles (`ZeeWeaponRig.Role`), copied so a caller needs no Zee class to name one.
const ROLE_LOCAL := 0
const ROLE_REMOTE := 1
const ROLE_SERVER := 2

## Zee's hold poses and weapon tags (`ZeeWeaponArt.POSE_*`, `ZeeWeaponIds.TAG_*`).
const POSE_MELEE := &"melee"
const POSE_THROWN := &"thrown"
const TAG_MELEE := &"melee"
const TAG_THROWN := &"thrown"
const TAG_EXPLOSIVE := &"explosive"

## Prefixed, because two weapon lists share one id space here and both have a `launcher`.
const ID_PREFIX := "zee_"

## What one point of damage is worth in impulse, against a prop. A pistol's 26 shoves a crate
## about the way a gravity gun's punt does; a sniper's 90 throws a beach ball across the plate.
const IMPULSE_PER_DAMAGE := 0.9

## The menu's categories, from gs-weapon's slots.
const SLOT_CATEGORIES := {
	1: &"melee",
	2: &"sidearms",
	3: &"primaries",
	4: &"heavy",
	5: &"thrown",
}

## One colour per slot, for the generated icon: there is no thumbnail in the pack.
const SLOT_COLOURS := {
	1: Color(0.70, 0.56, 0.40),
	2: Color(0.56, 0.66, 0.80),
	3: Color(0.48, 0.72, 0.52),
	4: Color(0.82, 0.48, 0.40),
	5: Color(0.84, 0.74, 0.36),
}

## Tests set this to run the no-zee paths on a host that has zee linked. Call [method reset] after.
static var force_absent := false

## -1 unknown, 0 absent, 1 present.
static var _present := -1
## Zee scripts by path relative to [constant ZEE_DIR].
static var _scripts: Dictionary = {}


# --- Presence --------------------------------------------------------------------

## Whether zee-gs-weapons is installed here (linked, built in, or overlaid from the Workshop).
static func available() -> bool:
	if force_absent:
		return false
	if _present < 0:
		_present = 1 if ResourceLoader.exists(ZEE_DIR + PROBE) else 0
	return _present == 1


## Forgets the presence answer, the loaded scripts, the catalogue and the forced flag; for tests.
static func reset() -> void:
	force_absent = false
	_present = -1
	_scripts.clear()
	_catalogue = null
	_with_packs = null


## Zee's script at [param rel] under [constant ZEE_DIR], or null without zee.
static func zee_script(rel: String) -> Script:
	if not available():
		return null
	var cached: Variant = _scripts.get(rel)
	if cached is Script:
		return cached
	var path := ZEE_DIR + rel
	if not ResourceLoader.exists(path):
		return null
	var loaded := load(path) as Script
	_scripts[rel] = loaded
	return loaded


## [param method] on zee's script [param rel] with [param args], or [param fallback] without zee.
static func call_static(rel: String, method: StringName, args: Array = [], fallback: Variant = null) -> Variant:
	var s := zee_script(rel)
	if s == null:
		return fallback
	return s.callv(method, args)


## A new instance of zee's script [param rel], or null.
static func make(rel: String) -> Object:
	var s := zee_script(rel)
	return s.new() as Object if s != null else null


## Whether [param x] is, or extends, zee's script [param rel].
static func extends_zee(x: Variant, rel: String) -> bool:
	if not (x is Object) or not is_instance_valid(x):
		return false
	var want := zee_script(rel)
	if want == null:
		return false
	var s := (x as Object).get_script() as Script
	while s != null:
		if s == want:
			return true
		s = s.get_base_script()
	return false


## Whether [param x] is a live weapon rig.
static func is_rig(x: Variant) -> bool:
	return extends_zee(x, PROBE)


## [param node]'s `zee_rig`, when it is a live rig; else null.
static func rig_of(node: Object) -> Node:
	if node == null:
		return null
	var rig: Variant = node.get("zee_rig")
	return rig as Node if is_rig(rig) else null


## The rig's class name, for a [code]component()[/code] lookup by type name; empty without zee.
static func rig_class() -> StringName:
	var s := zee_script(PROBE)
	return s.get_global_name() if s != null else &""


static func is_world_model(x: Variant) -> bool:
	return extends_zee(x, "view/zee_world_model.gd")


static func is_view_model(x: Variant) -> bool:
	return extends_zee(x, "view/zee_view_model.gd")


# --- Catalogue -------------------------------------------------------------------

## The catalogue, built once. Every rig is handed this one rather than building its own.
## Empty without zee.
static var _catalogue: GSWeaponCatalogue = null


static func catalogue() -> GSWeaponCatalogue:
	if _catalogue == null:
		var built: Variant = call_static("content/zee_weapon_pack.gd", &"catalogue")
		_catalogue = built if built is GSWeaponCatalogue else GSWeaponCatalogue.new()
		# Built once at setup, under the loading cover; the first spawn then loads no script.
		_catalogue.warm_scripts()
	return _catalogue


## Pack weapons ([PlaylotWorkshop]) by zee id, and the catalogue that holds them besides the pack's own.
static var _pack_defs: Dictionary = {}
static var _with_packs: GSWeaponCatalogue = null
## Weapons a spawn provider's `weapon_defs()` gave ([PlaylotAddons]), by zee id. Kept apart from
## [member _pack_defs] because [method set_pack_defs] replaces that one on every Workshop sync, and
## a provider's weapons are not the Workshop's to drop.
static var _provider_defs: Dictionary = {}


## Teaches the rigs a weapon a spawn provider ships. [param def] is a [PlaylotWeaponDef] whose
## `meta.pack_def` is the pack's [GSWeaponDef].
static func add_provider_def(def: PlaylotWeaponDef, provider: Object = null) -> void:
	var pack_def: Variant = def.meta.get("pack_def")
	if pack_def is GSWeaponDef:
		_provider_defs[zee_id(def)] = pack_def
		if provider != null:
			_art_providers[zee_id(def)] = weakref(provider)
		_with_packs = null
		_learn_art()


## Provider objects by zee id (weak: [PlaylotAddons] keeps them), for their `weapon_art()` / `art_rows()`.
static var _art_providers: Dictionary = {}


## Every pack and provider weapon gets art in zee's table, so each draws a first-person model on the avatar's arms and a gun in a remote player's hand. Without it a weapon zee has no art for (the
## arena pack's `lmg`) drew nothing at all. The provider's own art when it ships `weapon_art()`, else zee's gun of the same tier dressed with the provider's model (`art_rows()`).
## A provider's `weapon_art()` and `art_rows()` build its whole pack, so they are asked once per provider here rather than
## once per weapon (asked per weapon they cost about 1.5 s of one frame the first time zee's art table is built in PLAYLOT).
static func pack_art() -> Array:
	var out: Array = []
	if not available():
		return out
	var asked := {}
	for table: Dictionary in [_pack_defs, _provider_defs]:
		for id: StringName in table:
			var def: GSWeaponDef = table[id]
			var ref: Variant = _art_providers.get(id)
			var provider: Object = (ref as WeakRef).get_ref() if ref is WeakRef else null
			var art: Variant = _art_for(def, provider, asked)
			if art != null:
				out.append(art)
	return out


## [param asked] caches each provider's answers (instance id -> {arts, rows}) for one [method pack_art] call.
static func _art_for(def: GSWeaponDef, provider: Object, asked: Dictionary = {}) -> Variant:
	var answers: Dictionary = {}
	if provider != null:
		var key := provider.get_instance_id()
		if not asked.has(key):
			asked[key] = _provider_answers(provider)
		answers = asked[key]
	var art: Variant = (answers.get("arts", {}) as Dictionary).get(def.id)
	if extends_zee(art, "art/zee_weapon_art.gd"):
		return art
	var rows: Variant = answers.get("rows", {})
	var copy: Variant = call_static("content/zee_pack_source.gd", &"_base_for", [def])
	if copy == null:
		return null
	copy.set(&"id", def.id)
	var row: Dictionary = (rows as Dictionary).get(def.id, {}) if rows is Dictionary else {}
	var _dressed: Variant = call_static("art/zee_art_dress.gd", &"apply", [copy, row])
	return copy


## A provider's arts by id (its first art per id wins, as the per-weapon scan did) and its art rows.
static func _provider_answers(provider: Object) -> Dictionary:
	var arts := {}
	if provider.has_method(&"weapon_art"):
		for art: Variant in provider.call(&"weapon_art"):
			if extends_zee(art, "art/zee_weapon_art.gd"):
				var id: StringName = (art as Object).get(&"id")
				if not arts.has(id):
					arts[id] = art
	var rows: Variant = provider.call(&"art_rows") if provider.has_method(&"art_rows") else {}
	return {"arts": arts, "rows": rows}


## (Re)joins [method pack_art] to zee's art table; adding a source drops the table's cache.
static func _learn_art() -> void:
	var _added: Variant = call_static(
		"art/zee_weapon_art_table.gd", &"add_source", [&"playlot_packs", Callable(PlaylotZeeSelf, &"pack_art")]
	)


## The pack's definition of the weapon [param id]: the zee catalogue's, a Workshop weapon's or a provider's.
static func pack_def(id: StringName) -> GSWeaponDef:
	if catalogue().has(id):
		return catalogue().get_def(id)
	return _pack_defs.get(id, _provider_defs.get(id))


## Replaces the Workshop weapons the rigs may be given. [param defs] are [PlaylotWeaponDef]s whose
## `meta.pack_def` is the pack's [GSWeaponDef].
static func set_pack_defs(defs: Array) -> void:
	_pack_defs.clear()
	_with_packs = null
	for def: PlaylotWeaponDef in defs:
		var pack_def: Variant = def.meta.get("pack_def")
		if pack_def is GSWeaponDef:
			_pack_defs[zee_id(def)] = pack_def
	_learn_art()


## The catalogue a rig holding [param def] is built over: the pack's own, plus Workshop weapons it
## does not already have (code wins an id, as in gs-weapon). A copy rather than an addition to
## [method catalogue], so a solo subscription never leaks into a table a server also reads.
static func catalogue_for(def: PlaylotWeaponDef) -> GSWeaponCatalogue:
	if not available() or def == null or not def.meta.has("pack_def") or catalogue().has(zee_id(def)):
		return catalogue()
	if _with_packs == null:
		_with_packs = call_static("content/zee_weapon_pack.gd", &"catalogue")
		for table: Dictionary in [_pack_defs, _provider_defs]:
			for id: StringName in table:
				if not _with_packs.has(id):
					_with_packs.add(table[id])
		_with_packs.warm_scripts()
	return _with_packs


## The pack, as this game's weapon definitions; empty without zee. Read off the catalogue, so a
## weapon the pack adds arrives in the menu without a line here.
static func defs() -> Array[PlaylotWeaponDef]:
	var out: Array[PlaylotWeaponDef] = []
	if not available():
		return out
	var cat := catalogue()
	var ids: Variant = call_static("content/zee_weapon_ids.gd", &"all", [], [])

	for id: StringName in ids:
		var weapon := cat.get_def(id)

		if weapon == null:
			continue

		var def := PlaylotWeaponDef.make(
			StringName(ID_PREFIX + String(id)), weapon.display_name, ""
		)
		def.description = weapon.description
		def.category = SLOT_CATEGORIES.get(weapon.slot, &"zee")
		def.colour = SLOT_COLOURS.get(weapon.slot, Color(0.62, 0.68, 0.78))
		def.meta = {"zee": String(id), "slot": weapon.slot}
		out.append(def)

	return out


## The game's definition for weapon id [param id] (`zee_smg`), or null.
static func find_def(id: StringName) -> PlaylotWeaponDef:
	for def in defs():
		if def.id == id:
			return def
	return null


static func is_zee(def: PlaylotWeaponDef) -> bool:
	return def != null and def.meta.has("zee")


static func zee_id(def: PlaylotWeaponDef) -> StringName:
	return StringName(str(def.meta.get("zee", ""))) if def != null else &""


# --- Rigs ------------------------------------------------------------------------

## Puts a rig on [param player] holding [param def], replacing whatever rig was there. Null
## without zee (the player keeps no rig).
##
## [param role] is the rig's ([constant ROLE_SERVER] draws nothing, [constant ROLE_LOCAL] draws
## into [param view_model]). [param authority] is false only on a connected client, whose rig
## animates the hands and decides nothing — the server's rig is the one whose shots land.
## [param ads_rules] is the game's zee ads rules (`Art.load_ads_rules()`; null keeps the art's own).
static func arm(
	player: Node3D,
	def: PlaylotWeaponDef,
	role: int,
	authority: bool,
	tick_rate: int,
	tick: int,
	view_model: Node3D = null,
	ads_rules: Resource = null
) -> Node:
	disarm(player)

	var rig: Variant = make(PROBE)
	if rig == null:
		return null

	rig.name = "ZeeWeapons"
	rig.role = role
	rig.authority = authority
	rig.tick_rate = tick_rate
	# The held weapon lowers at every brush that stops the player, fences and clip included.
	var ctl: Variant = player.get("controller")
	rig.wall_extra_mask = ctl.tunables.collision_mask if ctl != null else 0
	rig.catalogue = catalogue_for(def)
	rig.player_ref = GSNodeRef.of_path(player.get_path())
	rig.ads_rules = ads_rules

	if view_model != null:
		rig.view_model_ref = GSNodeRef.of_path(view_model.get_path())

	player.add_child(rig)

	var ready_now: GSResult = rig.setup()

	if not ready_now.ok:
		GSLog.warn(CHANNEL, "a weapon rig would not set up", {
			"weapon": String(def.id), "why": ready_now.error.message,
		})
		player.remove_child(rig)
		rig.free()
		return null

	var id := zee_id(def)
	var given: GSResult = rig.give(id)

	if not given.ok:
		GSLog.warn(CHANNEL, "the rig refused a weapon", {
			"weapon": String(id), "why": given.error.message,
		})

	var arsenal: GSWeaponArsenal = rig.arsenal
	var weapon := arsenal.catalogue.get_def(id)

	if weapon != null:
		# equip, not select: select refuses while the arsenal is disabled (a spawn freeze).
		if not arsenal.equip(weapon.slot):
			var _selected := arsenal.select(weapon.slot, tick)

	player.set("zee_rig", rig)
	return rig


## Takes the rig off [param player], if there is one.
static func disarm(player: Node) -> void:
	if player == null:
		return

	var rig: Variant = player.get("zee_rig")

	if rig is Node and is_instance_valid(rig):
		var node := rig as Node
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()

	player.set("zee_rig", null)


## The rig's arsenal, or null.
static func arsenal_of(rig: Variant) -> GSWeaponArsenal:
	if not is_rig(rig):
		return null
	var arsenal: Variant = (rig as Object).get(&"arsenal")
	return arsenal as GSWeaponArsenal if arsenal is GSWeaponArsenal else null


## The definition the rig holds, or null.
static func current_def(rig: Variant) -> GSWeaponDef:
	if not is_rig(rig):
		return null
	var def: Variant = (rig as Object).call(&"current_def")
	return def as GSWeaponDef if def is GSWeaponDef else null


## One tick of [param rig] (`simulate_tick`), or null when it is no rig.
static func simulate(rig: Variant, command: GSWeaponCommand, tick: int, ctx: Variant = null) -> GSWeaponOutcome:
	if not is_rig(rig):
		return null
	var outcome: Variant
	if ctx == null:
		outcome = (rig as Object).call(&"simulate_tick", command, tick)
	else:
		outcome = (rig as Object).call(&"simulate_tick", command, tick, ctx)
	return outcome as GSWeaponOutcome if outcome is GSWeaponOutcome else null


## The rig's `role`, or -1.
static func role_of(rig: Variant) -> int:
	return int((rig as Object).get(&"role")) if is_rig(rig) else -1


# --- NPCs ----------------------------------------------------------------------

## Whether an NPC can use [param def]: a zee gun or melee weapon, not a thrown or
## explosive one. Grenades and rockets fly here ([PlaylotProjectiles]), but an NPC's
## brain aims along a straight line and has no throwing arc or blast-radius sense, so one
## holding a frag would bounce it off its own feet and a launcher would be fired point-blank.
## Always false without zee: an NPC then stands unarmed.
static func npc_can_use(def: PlaylotWeaponDef) -> bool:
	if not is_zee(def) or not available():
		return false

	var weapon := catalogue().get_def(zee_id(def))

	if weapon == null:
		return false

	return not (weapon.tags.has(TAG_THROWN) or weapon.tags.has(TAG_EXPLOSIVE))


## Keeps an NPC's weapon fed: the reserve back to a few magazines' worth whenever it runs
## low. An NPC out of ammunition standing still reads as broken, and nobody counts its shots.
static func top_up(rig: Node) -> void:
	var arsenal := arsenal_of(rig)

	if arsenal == null:
		return

	var def := current_def(rig)

	if def == null or def.ammo_type == &"":
		return

	if arsenal.ammo().count(def.ammo_type) < 60:
		var _added := arsenal.add_ammo(def.ammo_type, 120)


## Fills what [param rig] holds back up: a full magazine and at least the reserve a fresh one
## is given. True when anything changed. The server's answer to asking for (or walking over)
## the gun already in hand; the drawn gun on a client is brought to it by [method correct].
static func refill(rig: Node) -> bool:
	var arsenal := arsenal_of(rig)

	if arsenal == null or arsenal.current() == null:
		return false

	var def := current_def(rig)

	if def == null or def.ammo_type == &"":
		return false

	var held := arsenal.current()
	var changed := false

	if def.uses_magazine() and held.magazine < def.magazine:
		held.magazine = def.magazine
		changed = true

	if not def.infinite_reserve and arsenal.ammo().count(def.ammo_type) < def.reserve:
		arsenal.ammo().set_count(def.ammo_type, def.reserve)
		changed = true

	return changed


## How long the drawn gun must be quiet before the server's count may overwrite it: longer than
## a shot takes to reach the server and its snapshot to come back, so a correction never undoes
## a shot the server has not heard of yet. game-zombie-zone's `VIEW_RIG_SETTLE_SEC`.
const SETTLE_SEC := 0.6


## One tick of the drawn gun's quiet clock on [param player] (`zee_quiet`): reset by a trigger,
## a reload or a switch, else counted up by [param delta] simulated seconds.
static func note_drawn(player: Node, rig: Node, command: GSWeaponCommand, delta: float) -> void:
	var arsenal := arsenal_of(rig)
	if player == null or arsenal == null:
		return

	var busy := command != null and (command.is_pressed(GSWeaponCommand.BUTTON_ATTACK)
		or command.is_pressed(GSWeaponCommand.BUTTON_RELOAD))
	busy = busy or arsenal.is_reloading() or arsenal.is_switching()
	var quiet: float = float(player.get("zee_quiet")) if player.get("zee_quiet") != null else 0.0
	player.set("zee_quiet", 0.0 if busy else quiet + maxf(delta, 0.0))


## Brings a connected client's drawn [param rig] to the server's count ([param magazine],
## [param reserve], for [param slot]) once it has been quiet [constant SETTLE_SEC]. True when it
## changed anything.
##
## [b]The drawn gun predicts, so it can be wrong, and nothing used to put it right.[/b] A shot the
## server refused, a refill, a fresh rig on the server: each left the HUD on the client's own
## sum for good. Correcting on every snapshot instead would undo the shots still in flight and
## make the counter flicker up while you fire.
static func correct(rig: Node, magazine: int, reserve: int, slot: int, server_busy: bool, quiet: float) -> bool:
	var arsenal := arsenal_of(rig)
	if arsenal == null or server_busy or quiet < SETTLE_SEC:
		return false

	var held := arsenal.current()

	if held == null or slot != arsenal.current_slot() or arsenal.is_reloading() or arsenal.is_switching():
		return false

	var changed := false

	if held.def.uses_magazine() and held.magazine != magazine:
		held.magazine = clampi(magazine, 0, held.def.magazine)
		changed = true

	if held.def.ammo_type != &"" and not held.def.infinite_reserve \
			and arsenal.ammo().count(held.def.ammo_type) != reserve:
		arsenal.ammo().set_count(held.def.ammo_type, maxi(reserve, 0))
		changed = true

	return changed


static func rig_is_melee(rig: Node) -> bool:
	var def := current_def(rig)
	return def != null and def.tags.has(TAG_MELEE)


static func rig_is_automatic(rig: Node) -> bool:
	var def := current_def(rig)
	return def != null and (def.fire_mode == GSWeaponDef.Fire.AUTO or def.fire_mode == GSWeaponDef.Fire.HOLD)


static func rig_magazine_empty(rig: Node) -> bool:
	var arsenal := arsenal_of(rig)

	if arsenal == null or arsenal.current() == null:
		return false

	var def := current_def(rig)
	return def != null and def.ammo_type != &"" and arsenal.current().magazine_empty()


## Where every pellet of every shot in [param outcome] lands: `[{collider, point,
## direction, damage}]`, nearest hit per pellet, [param exclude] ignored.
##
## [b]Pellets, not the shot's direction.[/b] A shot made by a weapon has its spread already
## rolled into `pellets`, and tracing the direction instead puts every shotgun pellet down
## one line — a shotgun that is a rifle.
static func trace_outcome(
	space: PhysicsDirectSpaceState3D, outcome: GSWeaponOutcome, exclude: Array[RID]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if space == null or outcome == null:
		return out

	for shot: GSShot in outcome.shots:
		var directions: Array = shot.pellets if not shot.pellets.is_empty() else [shot.direction]
		var per_pellet := shot.damage

		for direction in directions:
			var dir: Vector3 = (direction as Vector3).normalized()
			var query := PhysicsRayQueryParameters3D.create(
				shot.origin, shot.origin + dir * maxf(shot.max_range, 1.0)
			)
			query.exclude = exclude
			var found := space.intersect_ray(query)

			if found.is_empty():
				continue

			out.append({
				"collider": found["collider"],
				"point": found["position"],
				"direction": dir,
				"damage": per_pellet,
				"distance": shot.origin.distance_to(found["position"]),
			})

	return out


## A tick's buttons and view as a weapon command.
##
## The same three bits every tool here rides on: USER_0 is fire, USER_1 the alt (a bash),
## USER_2 reload. The slot is the one the rig already holds; this game switches weapons by
## asking for one, not by a slot key. Buttons rather than a [GSFpsCommand] so the offline
## client, which has no command until its controller samples one, builds it the same way.
static func command_for(buttons: int, yaw: float, pitch: float, slot: int, aim: bool = false) -> GSWeaponCommand:
	var command := GSWeaponCommand.new()
	command.set_button(GSWeaponCommand.BUTTON_AIM, aim)
	command.set_button(GSWeaponCommand.BUTTON_ATTACK, (buttons & GSFpsCommand.BUTTON_USER_0) != 0)
	command.set_button(GSWeaponCommand.BUTTON_ALT, (buttons & GSFpsCommand.BUTTON_USER_1) != 0)
	command.set_button(GSWeaponCommand.BUTTON_RELOAD, (buttons & GSFpsCommand.BUTTON_USER_2) != 0)
	command.yaw = yaw
	command.pitch = pitch
	command.slot = slot
	return command


## The slot of the weapon a rig holds, or 0.
static func slot_of(rig: Node) -> int:
	var def := current_def(rig)
	return def.slot if def != null else 0


## Shoves the prop each shot hits. Returns how many it moved.
##
## [b]Through the gravity gun's own ray and ownership test[/b], so a shot can move exactly
## what a punt could: nothing frozen, nothing another player owns unless the server lets
## players touch each other's props. A second answer to "may I move that crate" would be
## a server where you cannot pick somebody's crate up and can shoot it across the map.
static func shove_props(
	player: Node, outcome: GSWeaponOutcome, may_touch_others: bool
) -> int:
	if outcome == null or player == null or not (player is Node3D):
		return 0

	var gun: GSGravGun = player.get("grav_gun")

	if gun == null or not (player as Node3D).is_inside_tree():
		return 0

	var space := (player as Node3D).get_world_3d().direct_space_state
	var moved := 0

	for shot: GSShot in outcome.shots:
		var direction := shot.direction.normalized()
		var reach := gun.reach
		gun.reach = shot.max_range
		var prop := gun.target(space, shot.origin, direction)
		gun.reach = reach

		if prop == null or not gun.may_act_on(prop, may_touch_others).ok:
			continue
		if prop.frozen or not (prop.node is RigidBody3D):
			continue

		var body := prop.node as RigidBody3D
		var damage := maxf(shot.total_damage(), shot.damage * float(maxi(shot.pellet_count, 1)))
		body.apply_central_impulse(direction * damage * IMPULSE_PER_DAMAGE)
		moved += 1

	return moved


# --- Views -----------------------------------------------------------------------

# --- Net -------------------------------------------------------------------------

## The weapon fields a carrier replicates: gs-weapon's, then zee's four.
##
## [b]Written out here rather than asked of zee[/b], so the schema is the same with zee and
## without it: a server without the addon and a client with it (or the reverse) still agree
## on every bit. These are `ZeeWeaponNet.specs()`; keep them in step.
static func net_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(GSWeaponNetSync.specs())
	out.append_array([
		{"property": &"net_fire_seq", "type": "UINT", "bits": 4, "owner_only": false, "interpolated": false},
		{"property": &"net_fire_kind", "type": "UINT", "bits": 3, "owner_only": false, "interpolated": false},
		{"property": &"net_reloading", "type": "BOOL", "bits": 1, "owner_only": false, "interpolated": false},
		{"property": &"net_switching", "type": "BOOL", "bits": 1, "owner_only": false, "interpolated": false},
	])
	return out


## Copies a rig's state onto the replicating [param target] (zee's `pull`); nothing without a rig.
static func net_pull(rig: Variant, target: Object) -> void:
	if not is_rig(rig) or target == null:
		return
	var _pulled: Variant = call_static("net/zee_weapon_net.gd", &"pull", [rig, target])


## Plays [param source]'s replicated state on a world [param model] (zee's `apply`), returning
## `{"seq": ...}` as zee does; without zee only the counter is read, so nothing replays later.
static func net_apply(source: Object, model: Variant, seen: int) -> Dictionary:
	if source == null:
		return {"seq": seen}
	if available() and (model == null or is_world_model(model)):
		var applied: Variant = call_static("net/zee_weapon_net.gd", &"apply", [source, model, seen])
		if applied is Dictionary:
			return applied
	return {"seq": int(source.get(&"net_fire_seq")) if source.get(&"net_fire_seq") != null else seen}
