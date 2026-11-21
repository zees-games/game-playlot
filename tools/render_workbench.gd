extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Renders the admin profile workbench through the real offline client into `docs/`.
##
## [codeblock]
## tools/render_workbench.sh
## [/codeblock]

const OUT_DIR := "res://docs"

var _client: PlaylotClient = null


func _ready() -> void:
	PlaylotPresentation.use_scratch_settings("render_workbench")
	_client = PlaylotClient.new()
	_client.name = "Client"
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	_run.call_deferred()


func _run() -> void:
	await _frames(60)
	_client.mouse_capture_override = false
	_client._open_profiles()
	await _frames(10)
	var screen := _client.profile_screen
	print("open: ", _client.screens.is_open(&"profiles"))
	var npcs := screen.ids("npc")
	print("npc ids: ", npcs)
	screen.open_profile("npc", "npc_hunter" if "npc_hunter" in npcs else npcs[0])
	await _frames(5)
	await _shot("workbench_npc")
	var weapons := screen.ids("weapon")
	print("weapon ids: ", weapons)
	if not weapons.is_empty():
		screen.open_profile("weapon", weapons[0])
		await _frames(5)
		var _r := screen.form.set_value("extra.damage", 99)
	await _shot("workbench_weapon")
	# dot-workbench's F9 panel (GSGameWorkbench) over the same profiles and the game settings.
	_client.screens.close_all() if _client.screens.has_method("close_all") else null
	var panel := _client.get_node_or_null("Workbench") as GSGameWorkbench
	if panel != null:
		panel.open()
		await _frames(10)
		await _shot("workbench_panel")
	get_tree().quit()


## Frame sequence after each still (GS_SHOT_FRAMES, set by the .sh); see GSShotSeq.
var _seq := GSShotSeq.new()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name])
	print(shot_name, " -> ", error_string(get_viewport().get_texture().get_image().save_png(path)))
	await _seq.record(get_tree(), path)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
