# scenes/

What a **dedicated server** loads for this game, as opposed to `game/playlot.tscn`, which is what a **client** loads.

`pg_server.tscn` is deliberately almost empty: a `Playlot` under a plain `Node`, with nothing configured on it. `Playlot._ready` registers itself under `playlot` in `GSRegistry`, which is what `playlot_module.gd` looks it up by, and everything an operator can change is a cvar or a layered configuration file. A scene full of exported defaults would be a second copy of those values, and the copy nobody edits is the one that goes stale.

It lives here rather than in `game/` because `gs-server-deploy`'s `setup.sh` copies `game/` into one shared directory and `scenes/*.tscn` into another, and the server scene is the half a client never loads.
