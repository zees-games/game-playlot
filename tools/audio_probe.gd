extends GSAudioSceneProbe

const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Asks whether this game actually makes a noise, on a machine that has a sound card. Every assertion about its audio once passed while the game was silent (the catalogue named `.ogg` files nobody had produced; a headless run builds a null sink). The loop is GSAudioSceneProbe; this names the cues. Run through `tools/audio_probe.sh`, not `--headless`.


func _prepare() -> void:
	# A render must not save into a player's settings file, nor draw from it.
	var _scratch := PlaylotPresentation.use_scratch_settings("audio_probe")
	GSLog.set_level(GSLog.Level.WARN)


func _make_node() -> Node:
	return PlaylotPresentation.new()


func _audio_of(node: Node) -> Object:
	return node.get("audio")


## One of each kind this game makes.
func _probe_ids() -> Array[StringName]:
	return [&"prop_spawn", &"prop_land", &"buy", &"refused"]
