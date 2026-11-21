extends "res://examples/headless_playlot_entities_and_weapons.gd"

## The hand-built maps: every script in res://maps but the generated one and the
## document reader, which are surveyed with their own arguments. Read off the directory so
## a map added is surveyed without anybody adding it here.
func _built_map_ids() -> Array[String]:
	var out: Array[String] = []

	for file in DirAccess.get_files_at("res://maps"):
		if file.ends_with(".gd") and not file.get_basename() in ["pg_generated", "pg_data"]:
			out.append(file.get_basename())

	out.sort()
	return out


# A run

## The spawn menu, driven the way a player drives it.
##
## A menu built from a catalogue is a seam between the screen stack and the catalogue that no addon suite reaches; it is a `Control` built in code, so sizes are checked, not just contents.
var _sm_menu: PlaylotSpawnMenu
var _sm_stack: GSScreenStack
var _sm_servers: PlaylotBrowser
var _sm_props_shown: Array[StringName]
var _sm_prop_count: int
var _sm_picked: Array[String]

func _test_spawn_menu() -> void:
	_section("the spawn menu")

	_sm_menu = PlaylotSpawnMenu.new()
	_sm_menu.catalogue = playlot.props.catalogue
	_sm_menu.weapons = playlot.weapons
	add_child(_sm_menu)

	# Registered on a real stack rather than shown directly: pushing is what calls
	# `_on_push`, and `_on_push` is what fills the grid.
	_sm_stack = GSScreenStack.new()
	add_child(_sm_stack)

	var ready := _sm_stack.setup()
	_check(ready.ok, "the screen stack sets up")

	var registered := _sm_stack.register(_sm_menu)
	_check(registered.ok, "and the menu registers on it")

	var pushed := _sm_stack.push(_sm_menu.screen_id())
	_check(pushed.ok, "and opens")
	_check(_sm_stack.any_open(), "and the stack knows a menu is up")

	await get_tree().process_frame

	_check(
		_sm_menu.size.x > 100.0 and _sm_menu.size.y > 100.0,
		"the menu has a size, which a Control built in code does not get for free",
		"%.0f x %.0f" % [_sm_menu.size.x, _sm_menu.size.y]
	)

	# The server browser, on the same stack and measured the same way. `set_anchors_preset` changes
	# nothing until something resizes the Control, which keeps its zero size with every property
	# correctly configured; only a size says so.
	_sm_servers = PlaylotBrowser.new()
	add_child(_sm_servers)

	var browser_registered := _sm_stack.register(_sm_servers)
	_check(browser_registered.ok, "the server browser registers too")

	var browser_open := _sm_stack.push(_sm_servers.screen_id())
	_check(browser_open.ok, "and opens")

	await get_tree().process_frame

	_check(
		_sm_servers.size.x > 100.0 and _sm_servers.size.y > 100.0,
		"and has a size rather than being an invisible 0 x 0",
		"%.0f x %.0f" % [_sm_servers.size.x, _sm_servers.size.y]
	)
	_check(
		_sm_servers.browser != null and _sm_servers.browser.count() > 0,
		"with something on the list, so a first run is not an empty box",
		"%d" % (_sm_servers.browser.count() if _sm_servers.browser != null else -1)
	)

	# Filtering is local and always will be: a server that chose which properties to report would
	# report whatever gets it listed, and a screen filtering its own rows would be a second filter.
	_check(
		_sm_servers.browser.filter != null,
		"and a filter the client owns rather than one the server answers"
	)
	_test_spawn_menu_2()
	await _test_spawn_menu_3()
	await _test_spawn_menu_4()
	await _test_spawn_menu_5()

func _test_spawn_menu_2() -> void:

	# The site's listing: off unless a site is named, and this game's servers when one is.
	var env_key := "GS_BROWSER_BACKBONE_URL"
	var had := OS.get_environment(env_key)
	OS.unset_environment(env_key)
	var off: GSResult = PlaylotBrowser.site_listing()
	_check(
		off.ok and off.value == null
			and not _sm_servers.browser.sources().any(
				func(s: GSBrowserSource) -> bool: return s.source_name() == &"backbone"
			),
		"no site listing is read when none is configured"
	)
	OS.set_environment(env_key, "http://127.0.0.1:9")
	var on: GSResult = PlaylotBrowser.site_listing()
	var listing: GSBrowserSourceBackbone = on.value if on.ok else null
	_check(
		listing != null and listing.config.page_url(1).contains("app=playground"),
		"and this game's servers are when one is",
		listing.config.page_url(1) if listing != null else str(on.error)
	)
	# Where the site comes from when nobody passed a flag. Web: ?backbone= > page origin;
	# native: argv > env > the exported default. Each result is one a reversed order would get
	# wrong, so a swap fails a check.
	OS.unset_environment(env_key)
	var web_both := PlaylotBrowser.resolve_default_site({
		"web": true, "origin": "https://site.example", "query": "https://other.example"
	})
	_check(web_both == "https://other.example", "on the web ?backbone= beats the page origin", web_both)
	var web_origin := PlaylotBrowser.resolve_default_site({"web": true, "origin": "https://site.example", "query": ""})
	_check(web_origin == "https://site.example", "and with no query the page's own origin is the site", web_origin)
	var web_file := PlaylotBrowser.resolve_default_site({"web": true, "origin": "null", "query": ""})
	_check(web_file == "", "and a page with no usable origin lists no site", web_file)
	var web_listing: GSResult = PlaylotBrowser.site_listing({"web": true, "origin": "https://site.example", "query": ""})
	_check(
		web_listing.ok and web_listing.value != null
			and web_listing.value.config.page_url(1).begins_with("https://site.example/api/content/server/list")
			and web_listing.value.config.page_url(1).contains("app=playground"),
		"so a web client lists its own site's servers without a flag"
	)
	var saved_default := PlaylotBrowser.default_backbone_url
	PlaylotBrowser.default_backbone_url = "https://deploy.example"
	var native_default := PlaylotBrowser.resolve_default_site({"web": false, "origin": "https://site.example", "query": "https://other.example"})
	_check(native_default == "https://deploy.example", "on native the exported default is used and the page is never asked", native_default)
	OS.set_environment(env_key, "http://127.0.0.1:9")
	var env_wins: GSResult = PlaylotBrowser.site_listing({"web": false})
	_check(
		env_wins.ok and env_wins.value != null and env_wins.value.config.backbone_url == "http://127.0.0.1:9",
		"and the environment beats that default",
		str(env_wins.value.config.backbone_url) if env_wins.ok and env_wins.value != null else str(env_wins.error)
	)
	PlaylotBrowser.default_backbone_url = saved_default
	if had != "":
		OS.set_environment(env_key, had)
	else:
		OS.unset_environment(env_key)

	_sm_stack.pop()
	_sm_servers.queue_free()

	# Props tab

	_sm_props_shown = _sm_menu.shown()
	_sm_prop_count = 0

func _test_spawn_menu_3() -> void:

	# Hidden entries (debris) are the game's, not the menu's, as the menu's own filter says.
	for def in playlot.props.catalogue.props:
		if PlaylotSpawnables.kind_of(def) == PlaylotSpawnables.Kind.PROP and not bool(def.meta.get("hidden", false)):
			_sm_prop_count += 1

	_check(
		_sm_props_shown.size() == _sm_prop_count,
		"the props tab shows every prop and no entities",
		"%d of %d" % [_sm_props_shown.size(), _sm_prop_count]
	)
	_check(
		not _sm_props_shown.has(&"npc_wanderer"),
		"and an entity is not among them"
	)
	_check(_sm_menu.card_for(&"crate") != null, "each one has a card that names it")

	# Icons. Nothing here ships art, so every card is drawn from the definition —
	# and a card with no icon at all is the failure that looks like a working menu
	# right up until somebody opens it.
	var crate_card := _sm_menu.card_for(&"crate")
	var ball_card := _sm_menu.card_for(&"ball")

	_check(
		crate_card != null and crate_card.icon != null
		and crate_card.icon.get_width() == PlaylotIcons.SIZE,
		"with an icon on it"
	)
	_check(
		crate_card != null and ball_card != null
		and crate_card.icon != ball_card.icon,
		"and a box and a sphere do not get the same one"
	)

	# The cache is keyed on the drawing, not on the prop, so two props that draw the
	# same share a texture. That is what stops a four-hundred-prop catalogue building
	# four hundred images every time somebody presses Q.
	_check(
		PlaylotIcons.generated(PlaylotIcons.Glyph.BOX, 1.0, Color.RED)
		== PlaylotIcons.generated(PlaylotIcons.Glyph.BOX, 1.0, Color.RED),
		"an icon drawn twice is one texture"
	)

	# Clicking spawns. The menu never spawns anything itself — it emits, and the
	# client asks the server — which is what lets this file work unchanged when the
	# spawn becomes a gs-net message.
	var chosen: Array[StringName] = []
	_sm_menu.prop_chosen.connect(
		func(id: StringName) -> void: chosen.append(id)
	)

	_sm_menu.card_for(&"barrel").pressed.emit()

	_check(chosen.size() == 1 and chosen[0] == &"barrel",
		"clicking a prop asks for that prop")
	_check(_sm_menu.selected == &"barrel", "and arms it for the spawn key")

	# Search reaches across every category on the tab, because a player who types
	# "barrel" wants the barrel and not "no such prop, you are on the Toys tab".
	_sm_menu._on_search_changed("boulder")
	await get_tree().process_frame

	var found := _sm_menu.shown()
	_check(found.has(&"boulder"), "searching finds a prop by name")
	_check(found.size() < _sm_props_shown.size(), "and narrows the grid")

	_sm_menu._on_search_changed("zzzz")
	await get_tree().process_frame

func _test_spawn_menu_4() -> void:

	_check(
		_sm_menu.shown().is_empty(),
		"a search that matches nothing shows nothing"
	)

	_sm_menu._on_search_changed("")
	await get_tree().process_frame

	# A tab past the last one (a pack tab with no pack) is ignored, not an out-of-bounds index.
	var tab_before: Variant = _sm_menu.describe().get("tab")
	_sm_menu.show_tab(PlaylotSpawnMenu.Tab.size() as PlaylotSpawnMenu.Tab)
	_check(_sm_menu.describe().get("tab") == tab_before, "show_tab past the last tab leaves the open tab alone")

	# Entities tab

	_sm_menu.show_tab(PlaylotSpawnMenu.Tab.ENTITIES)
	await get_tree().process_frame

	var entities_shown := _sm_menu.shown()

	_check(not entities_shown.is_empty(), "the entities tab has entities on it")
	_check(
		entities_shown.has(&"npc_wanderer") and not entities_shown.has(&"crate"),
		"and no props"
	)

	# Weapons tab

	_sm_menu.show_tab(PlaylotSpawnMenu.Tab.WEAPONS)
	await get_tree().process_frame

	var weapons_shown := _sm_menu.shown()

	_check(
		weapons_shown.size() == playlot.weapons.size(),
		"the weapons tab shows every weapon",
		"%d of %d" % [weapons_shown.size(), playlot.weapons.size()]
	)

	var equipped: Array[StringName] = []
	_sm_menu.weapon_chosen.connect(
		func(id: StringName) -> void: equipped.append(id)
	)

	_sm_menu.card_for(&"launcher").pressed.emit()

	_check(
		equipped.size() == 1 and equipped[0] == &"launcher",
		"and clicking one asks to equip it rather than to spawn it"
	)

	# Switching tabs clears the filter. Carrying "containers" onto the weapons tab
	# would show nothing and read as the tab being broken.
	_sm_menu.show_tab(PlaylotSpawnMenu.Tab.PROPS)
	await get_tree().process_frame

	_check(
		_sm_menu.shown().size() == _sm_prop_count,
		"and going back to props shows all of them again"
	)

	# The Builds tab asks the server when it opens, and a click asks for that build.
	var opened := [0]
	_sm_picked = []
	_sm_menu.builds_opened.connect(func() -> void: opened[0] += 1)
	_sm_menu.build_chosen.connect(func(build_name: String) -> void: _sm_picked.append(build_name))
	_sm_menu.show_tab(PlaylotSpawnMenu.Tab.BUILDS)
	await get_tree().process_frame
	_check(opened[0] == 1 and _sm_menu.shown().is_empty(), "the Builds tab asks for the player's builds, and shows none until they come")
	_sm_menu.set_builds([{"name": "bridge", "props": 6, "custom": false}, {"name": "car", "props": 9, "custom": true}])
	await get_tree().process_frame
	_check(str(_sm_menu.shown()) == str([&"bridge", &"car"]), "then shows each one", str(_sm_menu.shown()))

func _test_spawn_menu_5() -> void:
	_sm_menu.card_for(&"car").pressed.emit()
	_check(str(_sm_picked) == str(["car"]), "and clicking one asks for it by name")
	_check(_sm_menu._categories_for_tab() == PackedStringArray(["builds", "custom props"]),
		"with a welded build filed as a custom prop")
	_sm_menu.show_tab(PlaylotSpawnMenu.Tab.PROPS)
	await get_tree().process_frame

	_check(
		PlaylotSpawnMenu.name_of_tool(&"phys") == "physics gun"
		and PlaylotSpawnMenu.name_of_tool(&"") == "nothing",
		"a tool id has a name, and an empty one is not silently a gravity gun"
	)

	var popped := _sm_stack.pop(_sm_menu.screen_id())
	_check(popped.ok and not _sm_stack.any_open(), "the menu closes")
	await _test_spawn_menu_reopen()

	_sm_stack.queue_free()
	_done()


## Every Q rebuilt ~130 cards, a 40-50 ms frame in the owner's profile; an unchanged menu keeps them.
func _test_spawn_menu_reopen() -> void:
	var builds := _sm_menu.grid_builds
	var cards := _sm_menu.shown().size()
	var t0 := Time.get_ticks_usec()
	var again := _sm_stack.push(_sm_menu.screen_id())
	var reopen_us := Time.get_ticks_usec() - t0
	await get_tree().process_frame
	_check(again.ok and _sm_menu.grid_builds == builds and _sm_menu.shown().size() == cards,
		"reopened unchanged, the menu keeps its cards rather than rebuilding them", "%d -> %d builds" % [builds, _sm_menu.grid_builds])
	_sm_stack.pop(_sm_menu.screen_id())

	var picked := _sm_menu.shown()[0] if cards > 0 else &"barrel"
	_sm_menu.selected = picked if _sm_menu.selected != picked else &""
	t0 = Time.get_ticks_usec()
	_sm_stack.push(_sm_menu.screen_id())
	var rebuild_us := Time.get_ticks_usec() - t0
	await get_tree().process_frame
	_check(_sm_menu.grid_builds == builds + 1, "and rebuilds them once what it shows has changed", "%d builds" % _sm_menu.grid_builds)
	print("    bench spawn menu open: rebuild %.2f ms, reopen %.2f ms (%d cards)" % [rebuild_us / 1000.0, reopen_us / 1000.0, cards])
	_sm_stack.pop(_sm_menu.screen_id())
