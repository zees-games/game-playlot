extends GSGameNetchaosClient

const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Playlot's side of `tools/netchaos.sh` (gs-game's GSGameNetchaosClient). No fire action: the pilot only walks and jumps.


func _configure() -> void:
	client_scene = "res://game/playlot.tscn"


func _prepare(label: String) -> Variant:
	return PlaylotPresentation.use_scratch_settings(label)


func _roster() -> Array:
	var out: Array = []
	var world = _client.get("playlot") if _client != null else null
	if world != null:
		out.append_array(world.players.values())
	var me = _client.get("player") if _client != null else null
	if me != null and not out.has(me):
		out.append(me)
	return out
