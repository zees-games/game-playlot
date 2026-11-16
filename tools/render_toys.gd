extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Renders the offline client with each toy and tool in hand, first person, one PNG each.
##
## Run: `xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_toys.tscn -- <out dir>`

const TOYS: Array[StringName] = [&"phys", &"grav", &"launcher", &"toolgun", &"remover", &"impulse"]

var _client: PlaylotClient = null


func _ready() -> void:
	PlaylotPresentation.use_scratch_settings("render_toys")
	_client = PlaylotClient.new()
	_client.name = "Client"
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	_run.call_deferred()


## Frame sequence after each still (GS_SHOT_FRAMES, set by the .sh); see DotShotSeq.
var _seq := DotShotSeq.new()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(2.0).timeout
	_client.mouse_capture_override = true
	var failed := 0
	for id in TOYS:
		_client._set_tool(id)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var ok := _client.toy_view != null and is_instance_valid(_client.toy_view)
		print("%s: toy view %s" % [id, "present" if ok else "MISSING"])
		failed += 0 if ok else 1
		get_viewport().get_texture().get_image().save_png("%s/toy_%s.png" % [out, id])
		await _seq.record(get_tree(), "%s/toy_%s.png" % [out, id])
	print("toys: %d failed" % failed)
	get_tree().quit(failed)
