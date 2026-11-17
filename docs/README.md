# game-playlot docs

The detail behind [CLAUDE.md](../CLAUDE.md). One subject per file; open the one you are about to touch. Family-wide rules are in the family's [CLAUDE.md](../../../CLAUDE.md) and [docs/](../../../docs/README.md).

| File | Read it before |
| --- | --- |
| [simulation.md](simulation.md) | touching the tick loop, the player, styles, `post_move_fn`, teleports and spawns, the movement tunables, the tick rate, or the module and its console commands |
| [sandbox.md](sandbox.md) | touching props, entities and NPC perception, armed NPCs, weapons and zee-dot-weapons, projectiles, the Q menu and its icons, the tools, the tool gun, limits, machines, breaking, picking players up, creative mode, prop surfing, or saved builds |
| [spawn-providers.md](spawn-providers.md) | a pack that should add weapons, NPCs or bots to the Q menu: the `spawn_provider.gd` contract |
| [profiles.md](profiles.md) | the Q menu NPCs and pack weapons derived from profiles, game-tier overrides, and `profile_edit` (admin live edits) |
| [maps.md](maps.md) | changing a map, the zone export, the survey, custom map documents and their props, materials, liquids and panes, or `pg_generated` |
| [timer.md](timer.md) | the run timer: why it does not ship, how a server adds dot-timer, what `addons/pg_timer` does and what it dropped |
| [vehicles.md](vehicles.md) | touching vehicles, seats, the circuit, or what a driver feels over the wire |
| [netcode.md](netcode.md) | touching `game/net/`, prediction, remote bodies, the READY gate, mirrors, an event or request kind, or a message script |
| [inventory.md](inventory.md) | touching the bag or its wire |
| [modes.md](modes.md) | touching the arena, the waves and downs, the shop, spectating, or hosting a party |
| [services.md](services.md) | touching chat, voice, the moderator's tools, stats and achievements, the vote and its clock, hibernation, identity, or the browser listing |
| [client.md](client.md) | touching the client: boot, Escape and the menu, third person and bodies, the people figure, presentation, sound and effects, the chat box, or the render tools |
| [testing.md](testing.md) | adding a check, or believing a green run |
| [not-yet.md](not-yet.md) | planning: what is not built yet, and why each is open |
| [history.md](history.md) | a bug that "cannot be happening"; what this game found and how it looked |

## Where the code is

The files of [CLAUDE.md](../CLAUDE.md)'s layout, one by one.

| Path | What |
| --- | --- |
| `game/playlot.gd` | the simulation: maps, the optional run timer, props, entities, players, liquids, panes; headless |
| `game/playlot_player.gd`, `playlot_player_stack.gd`, `playlot_character.gd`, `playlot_figure.gd`, `playlot_avatars.gd` | the player bridge (movement, style, tools), its stack, its body and what it wears |
| `game/playlot_module.gd`, `playlot_services.gd`, `playlot_mod_tools.gd`, `playlot_vote.gd`, `playlot_platform.gd`, `playlot_progress.gd` | the server: dot-server module and every console command, chat/voice/moderation, the vote, identity, stats |
| `game/playlot_prop.gd`, `playlot_spawnables.gd`, `playlot_limits.gd`, `playlot_constraints.gd`, `playlot_pickup.gd`, `playlot_builds.gd`, `prop.tscn`, `entity.tscn`, `vehicle.tscn` | props: one scene for every prop, the catalogue, limits, constraints, picking players up, saved builds |
| `game/entities/` | NPCs and other entities, each `extends` a path |
| `game/weapons/`, `game/toolgun/`, `playlot_weapons.gd`, `playlot_zee.gd`, `playlot_projectiles.gd` | the toys, the tool gun's modes, zee-dot-weapons, grenades and rockets |
| `game/playlot_arena.gd`, `playlot_waves.gd`, `playlot_downs.gd`, `playlot_shop.gd`, `playlot_spectate.gd`, `playlot_party.gd`, `playlot_npc_world.gd` | the modes |
| `game/playlot_inventory.gd` | the bag |
| `game/playlot_client.gd`, `playlot_hud.gd`, `playlot_spawn_menu.gd`, `playlot_icons.gd`, `playlot_presentation.gd`, `playlot_rope_view.gd`, `game/client/` | the client: not headless |
| `game/net/` | the dot-net bridge, link, per-kind net classes, events and requests, the bag's wire |
| `game/playlot_map.gd`, `playlot_geometry.gd`, `playlot_lighting.gd`, `playlot_map_survey.gd`, `playlot_materials.gd`, `playlot_worldgen.gd` | the map base, box building and the palette, each map's dot-lighting, the survey, materials, the generator |
| `maps/` | `pg_flatgrass` (hand-built, the default), `pg_generated`, `pg_data` (builds a JSON map), `custom/` (playlot-maps, linked) |
| `examples/` | the five suites |
| `tools/` | `map_props.gd`, `screenshot*.sh`, `render_feel.sh`, `audio_probe.sh`, `loudness_pilot.gd` |
| `assets/` | vendored CC0 art: zee weapons and arms, the character kit, Kenney's prototype grid |
| `scenes/fx/` | the two effect scenes |
| `game.yml` | the descriptor that travels in the published pack |
