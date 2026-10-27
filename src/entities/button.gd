class_name FuncButton
extends AnimatableBody3D

@export var mover: SlideMover
@export var interactable: Interactable
@export var wait: float

var _wait_timer: Timer
var func_godot_properties: Dictionary

func _func_godot_build_complete() -> void:
	wait = func_godot_properties.get("wait", -1)

	var displacement = func_godot_properties.get("displacement", Vector3.FORWARD)
	var move_time = func_godot_properties.get("move_time", 0.06)
	mover = SlideMover.new()
	mover.offset = displacement
	mover.move_time = move_time

	var targetname = func_godot_properties.get("targetname", "")
	var target = func_godot_properties.get("target", "")
	interactable = Interactable.new()
	interactable.target = target
	interactable.targetname = targetname
	add_child(interactable)

	MapEntityBridge.set_owner_recursive(interactable, owner)

	_setup()

func _ready() -> void:
	if mover:
		_setup()

func _setup() -> void:
	interactable.interacted.connect(interact)
	mover.finished.connect(reset)

func interact(by: Node3D) -> void:
	mover.move(true)

func reset(opened: bool = true) -> void:
	if wait == -1:
		interactable.enabled = false
		return
	if opened:
		_wait_timer.start(wait)
		await _wait_timer.timeout
		mover.move(false)
