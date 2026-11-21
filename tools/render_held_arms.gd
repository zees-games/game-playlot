extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotViewGrip := preload("../game/playlot_view_grip.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Renders the offline client holding one weapon of each pose, the first-person arms on the grip, and prints the hand error.
##
## Run: `xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_held_arms.tscn -- <out dir>`

var _client: PlaylotClient = null


func _ready() -> void:
	PlaylotPresentation.use_scratch_settings("render_held_arms")
	_client = PlaylotClient.new()
	_client.name = "Client"
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	_run.call_deferred()


## Frame sequence after each still (GS_SHOT_FRAMES, set by the .sh); see GSShotSeq.
var _seq := GSShotSeq.new()


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(2.0).timeout
	_client.mouse_capture_override = true
	var chosen: Dictionary = {}
	for art in ZeeWeaponArtTable.all():
		if art.has_model() and not chosen.has(art.pose):
			chosen[art.pose] = art.id
	var failed := 0
	for pose: StringName in chosen:
		_client._set_tool(StringName("zee_%s" % chosen[pose]))
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		var err := (_client.view_arms as GSPlayerViewArms).hand_error(_client.held_grip)
		print("%s (%s): hand error %.3f m" % [pose, chosen[pose], err])
		failed += 0 if err >= 0.0 and err < (0.05 if pose in PlaylotViewGrip.ONE_HAND else (0.13 if pose == &"heavy" else 0.10)) else 1
		get_viewport().get_texture().get_image().save_png("%s/held_%s.png" % [out, pose])
		await _seq.record(get_tree(), "%s/held_%s.png" % [out, pose])
	print("held arms: %d failed" % failed)
	get_tree().quit(failed)
