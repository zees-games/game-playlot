extends RefCounted

const PlaylotPaths := preload("playlot_paths.gd")
const PlaylotZee := preload("playlot_zee.gd")
const PlaylotWeaponDef := preload("weapons/playlot_weapon_def.gd")

## Zee's art, models and sounds, when the player has zee: the held gun others see, the
## first-person hands, the scope, the art table, the ads rules and the shot sounds.
##
## Reached as `PlaylotZee.Art`; like the rest of [code]playlot_zee.gd[/code] it loads zee by path
## after the presence check and answers null, empty or nothing without it.

## What everybody else sees in [param player]'s hands: [param def]'s gun, or nothing.
##
## Zee's world model on the character's `right_hand` mount, built on a CLIENT from the
## server's WEAPON event, so a remote player's gun is drawn, kicks when
## [PlaylotPlayerNet]'s fire counter moves, and goes when they put it away. Idempotent:
## the same weapon twice keeps the model it has. Nothing without zee.
static func show_held(player: Node, def: PlaylotWeaponDef) -> void:
	if player == null:
		return

	var held: Variant = player.get("zee_world")
	var model: Variant = held if PlaylotZee.is_world_model(held) else null

	if not PlaylotZee.is_zee(def) or not PlaylotZee.available():
		if model != null:
			(model as Node).queue_free()
		player.set("zee_world", null)
		return

	var id := PlaylotZee.zee_id(def)
	if model != null and model.equipped() == id:
		return

	var art: Variant = art_for(id)
	if art == null:
		return

	if model == null:
		model = new_world_model()
		if model == null:
			return
		if not model.attach_to(player.get("character")):
			(model as Node).free()
			return
		player.set("zee_world", model)

	var _equipped: Variant = model.equip(art)


## A fresh world model (a [Node3D]), or null.
static func new_world_model() -> Node3D:
	var model := PlaylotZee.make("view/zee_world_model.gd") as Node3D
	if model != null:
		model.name = "ZeeHeld"
	return model


## A fresh first-person view model (a [Node3D]), or null.
static func new_view_model() -> Node3D:
	return PlaylotZee.make("view/zee_view_model.gd") as Node3D


## Zee's scope overlay (a [Control]), or null.
static func new_scope_overlay() -> Control:
	return PlaylotZee.make("view/zee_scope_overlay.gd") as Control


## Zee's art for weapon [param id], or null.
static func art_for(id: StringName) -> Resource:
	var table: Variant = PlaylotZee.call_static("art/zee_weapon_art_table.gd", &"table", [], {})
	var art: Variant = (table as Dictionary).get(id) if table is Dictionary else null
	return art as Resource if PlaylotZee.extends_zee(art, "art/zee_weapon_art.gd") else null


## Zee's whole weapon table (id -> art), or {}.
static func weapon_table() -> Dictionary:
	var table: Variant = PlaylotZee.call_static("content/zee_weapon_pack.gd", &"table", [], {})
	return table if table is Dictionary else {}


## The game's ads rules (zee's `load_config()`), or null.
static func load_ads_rules() -> Resource:
	var rules: Variant = PlaylotZee.call_static("content/zee_ads_rules.gd", &"load_config")
	return rules as Resource if rules is Resource else null


## Zee's shot effects to warm under the loading cover, or [].
static func shot_fx_warm() -> Array:
	var warm: Variant = PlaylotZee.call_static("view/zee_shot_fx.gd", &"warm", [], [])
	return warm if warm is Array else []


## Points zee's art at this game's copy of it: `res://assets/` built in, the mount in a pack.
static func use_this_games_art() -> void:
	var _set: Variant = PlaylotZee.call_static("art/zee_model_cache.gd", &"set_asset_root", [PlaylotPaths.root()])


## Puts zee's art back where a built-in game keeps it, for whatever the shell loads next.
static func release_art() -> void:
	var _set: Variant = PlaylotZee.call_static("art/zee_model_cache.gd", &"set_asset_root", ["res://"])


# --- Sound -----------------------------------------------------------------------

const SHOT_LAYERS := "view/zee_shot_layers.gd"
const WEAPON_SOUND := "view/zee_weapon_sound.gd"


## Whether zee's layered shot player can run (zee and gs-audio both here).
static func shot_layers_available() -> bool:
	return PlaylotZee.call_static(SHOT_LAYERS, &"available", [], false) == true


## A fresh layered shot player (a [Node]), or null.
static func new_shot_layers() -> Node:
	return PlaylotZee.make(SHOT_LAYERS) as Node


## gs-audio's shot class for zee's sound class [param weapon_class], or empty.
static func layer_shot_class(weapon_class: StringName) -> StringName:
	return StringName(str(PlaylotZee.call_static(SHOT_LAYERS, &"shot_class", [weapon_class], &"")))


## Zee's sound class for [param id] and [param kind], or empty.
static func sound_class_for(id: StringName, kind: Variant) -> StringName:
	return StringName(str(PlaylotZee.call_static(WEAPON_SOUND, &"class_for", [id, kind], &"")))


## Zee's sound for [param id] and [param kind], or null.
static func sound_stream_for(id: StringName, kind: Variant) -> AudioStream:
	var stream: Variant = PlaylotZee.call_static(WEAPON_SOUND, &"stream_for", [id, kind])
	return stream as AudioStream if stream is AudioStream else null
