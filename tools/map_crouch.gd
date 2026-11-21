extends Node

const PlaylotMapSurvey := preload("../game/playlot_map_survey.gd")
const PlaylotPlayer := preload("../game/playlot_player.gd")

## The vents of the custom maps: floor only a crouched player fits over, that no spawn leads
## to. The suite's survey asks about a standing player, so a crawlspace, a low attic or a
## duct is never a standable cell there and nothing says whether anyone can reach it. This
## surveys each map twice (standing, then at the family crouch height) and prints every
## crouch-only region no spawn reaches that the document does not declare.
##
## It does not widen a passage: a map whose vent is cut off declares it (the converter's
## `declared`), or a climb is built to it, in the converter.
##
##   godot --headless --path . res://tools/map_crouch.tscn -- pgc_town pgc_site
##   godot --headless --path . res://tools/map_crouch.tscn          # every maps/custom/*.json

func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var ids: PackedStringArray = OS.get_cmdline_user_args()
	if ids.is_empty():
		for file in DirAccess.get_files_at("res://maps/custom"):
			if file.ends_with(".json"):
				ids.append(file.get_basename())
	var data_script := load("res://maps/pg_data.gd") as GDScript
	var crouch_height: float = PlaylotPlayer.movement_tunables().crouch_height
	var failed := false
	for id in ids:
		var map: Node3D = data_script.new()
		var configured: GSResult = map.configure_doc("res://maps/custom/%s.json" % id)
		if not configured.ok:
			print("%s: LOAD FAILED %s" % [id, str(configured.error)])
			failed = true
			map.free()
			continue
		var spawns: Array[Vector3] = [map.fallback_spawn]
		var found: Dictionary = PlaylotMapSurvey.crouch_cut_off(map, [], spawns, map.survey_declared(), crouch_height)
		map.free()
		print("%s: %d crouch-only cells, %d reached" % [id, int(found["crouch_only"]), int(found["crouch_reached"])])
		for line in found["cut_off"]:
			print("  CUT OFF %s" % line)
			failed = true
	get_tree().quit(1 if failed else 0)
