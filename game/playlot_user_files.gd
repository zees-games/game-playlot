extends RefCounted

## The game's own [code]user://[/code] files, which moved off the old Playlot name on 2026-11-17.
##
## [b]Read the new path; adopt the former one once.[/b] [method resolve] returns its argument
## unchanged unless it is one of the defaults in [constant FORMER]. For those, when the new
## file or folder is missing and the former one exists, the former is copied over (a folder
## recursively) and the new path is what everything reads and writes from then on. The former
## is left where it was, so an older build on the same machine still finds its own.
##
## A copy that fails is an error in the log and the former path is returned, so a player's
## settings or a server's records are never silently replaced by an empty new file.

const CHANNEL := "playlot.user_files"

## New default path -> the path it had under the old name.
const FORMER := {
	"user://playlot_settings": "user://playground_settings",
	"user://playlot/records": "user://playground/records",
	"user://cfg/playlot_vote.json": "user://cfg/playground_vote.json",
	"user://playlot_servers.json": "user://playground_servers.json",
	"user://playlot_identity": "user://playground_identity",
	"user://playlot_achievements": "user://playground_achievements",
	"user://playlot_punishments.json": "user://playground_punishments.json",
	"user://playlot_boards.json": "user://playground_boards.json",
}


## [param path], after adopting its former file or folder when it has one and is missing.
static func resolve(path: String) -> String:
	return adopt(path, FORMER.get(path, ""))


## [param path], after copying [param former] (a file, or a folder recursively) to it when
## [param path] is missing and [param former] exists. [method resolve] with the table spelled out.
static func adopt(path: String, former: String) -> String:
	if former == "" or _exists(path) or not _exists(former):
		return path
	var err := _copy(former, path)
	if err != OK:
		DotLog.error(CHANNEL, "could not copy a file from its former path, reading the former one", {
			"from": former, "to": path, "error": error_string(err),
		})
		return former
	DotLog.info(CHANNEL, "adopted a file from its former path", {"from": former, "to": path})
	return path


static func _exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


static func _copy(from: String, to: String) -> Error:
	if FileAccess.file_exists(from):
		var made := DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		if made != OK:
			return made
		return DirAccess.copy_absolute(from, to)
	var dir := DirAccess.open(from)
	if dir == null:
		return DirAccess.get_open_error()
	var made := DirAccess.make_dir_recursive_absolute(to)
	if made != OK:
		return made
	dir.include_hidden = true
	for name in dir.get_files():
		var err := DirAccess.copy_absolute(from.path_join(name), to.path_join(name))
		if err != OK:
			return err
	for name in dir.get_directories():
		var err := _copy(from.path_join(name), to.path_join(name))
		if err != OK:
			return err
	return OK
