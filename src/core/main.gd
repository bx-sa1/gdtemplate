class_name Main extends Node

@export var player_scene: PackedScene

@onready var map_root: Node = %Map
@onready var ents_root: Node = %Entities
@onready var main_menu_ui: Control = %MainMenu
@onready var loading_ui: Control = %LoadingScreen
@onready var pause_ui: Control = %PauseScreen

var player: Node3D = null
var current_map: Node = null
var _busy := false

func _enter_tree() -> void:
	LimboConsole.register_command(load_map, "map", "Load a map")
	LimboConsole.register_command(load_map_debug, "map_debug", "Load a map externally")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	Events.map_requested.connect(load_map)
	Events.main_menu_requested.connect(show_main_menu)
	Events.pause_requested.connect(set_paused)
	Events.quit_requested.connect(get_tree().quit)

	show_main_menu()

func show_main_menu() -> void:
	if _busy:
		return
	if player:
		player.queue_free()
		player = null
	await unload_map()
	loading_ui.hide()
	main_menu_ui.show()

func set_paused(p: bool) -> void:
	if _busy:
		return
	if p and not current_map:
		return  # nothing to pause
	get_tree().paused = p
	pause_ui.visible = p

func unload_map() -> void:
	main_menu_ui.hide()
	pause_ui.hide()
	get_tree().paused = false

	if current_map:
		var old := current_map
		current_map = null          # clear BEFORE awaiting
		old.queue_free()
		await old.tree_exited

func _set_map(map: Node) -> void:
	current_map = map
	map_root.add_child(map)
	await get_tree().process_frame
	spawn_player()

func _fail(msg: String) -> void:
	push_error(msg)
	_busy = false
	show_main_menu()

func load_map(map_name: String) -> void:
	if _busy:
		return
	_busy = true
	loading_ui.show()
	await unload_map()

	var map_path := "res://assets/maps/%s.tscn" % map_name
	if ResourceLoader.load_threaded_request(map_path, "PackedScene") != OK:
		_fail("Failed to request map scene %s" % map_path)
		return

	var progress := []
	var status := ResourceLoader.load_threaded_get_status(map_path, progress)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if loading_ui.has_method("set_loading_progress"):
			loading_ui.set_loading_progress(progress[0])
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(map_path, progress)

	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_fail("Failure during loading of %s" % map_path)
		return

	var map_scene := ResourceLoader.load_threaded_get(map_path) as PackedScene
	if map_scene == null:
		_fail("Loaded resource is not a PackedScene: %s" % map_path)
		return

	await _set_map(map_scene.instantiate())
	loading_ui.hide()
	_busy = false

func load_map_debug(path: String) -> void:
	if _busy:
		return
	_busy = true
	await unload_map()

	var map := FuncGodotMap.new()          # fresh instance every time
	map.global_map_file = path
	map.build_failed.connect(func(): push_error("Failed to build debug map %s" % path))
	map.build()

	await _set_map(map)
	_busy = false

func spawn_player() -> void:
	var spawns := get_tree().get_nodes_in_group("SPAWN")
	if spawns.is_empty():
		push_warning("Map has no SPAWN nodes")
		return
	if not player_scene:
		push_error("player_scene is not assigned on Main")
		return

	var spawn: Node3D = spawns.pick_random()
	if not player:
		player = player_scene.instantiate()
		ents_root.add_child(player)
	player.global_position = spawn.global_position

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
