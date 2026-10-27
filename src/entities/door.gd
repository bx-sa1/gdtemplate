@tool
class_name FuncDoor extends AnimatableBody3D
## A door that opens when the player is near. All movement and animation is
## handled by the `mover` (a DoorMover node: SlideMover, RotateMover,
## AnimationMover, or your own).
##
## Scene setup:
##   Door (Node3D)                  <- this script
##   ├─ Panel (AnimatableBody3D)    <- the visible, solid part (mesh + collision)
##   ├─ Trigger (Area3D)            <- slightly bigger than the doorway, mask = player layer
##   └─ Mover (SlideMover etc.)     <- assign to the `mover` export
##
## Notes:
##   - Use AnimatableBody3D for the panel so the player is pushed correctly.
##   - The player must be in the "player" group.
##   - Optional key support: if the player has `has_key(id: String) -> bool`,
##     a door with `key_id` set unlocks for a player carrying that key.

signal opened
signal closed
signal unlock_failed(by: Node3D)

enum State { CLOSED, OPENING, OPEN, CLOSING }

@export var mover: Mover
@export var trigger: Area3D
@export var interactable: Interactable
## Open automatically when the player enters the trigger.
## If false, something must call interact() (e.g. the player's "use" action).
@export var auto_open := true
## Seconds after the player leaves before the door closes. 0 = stay open.
@export var auto_close_delay := 2.0
## Empty = can only be unlocked by calling unlock().
@export var key_id := ""



var state := State.CLOSED

var _occupants: Array[Node3D] = []
var _close_timer: Timer
var _func_godot_properties: Dictionary

func _func_godot_build_complete() -> void:
	var bounds := AABB()
	for c in get_children():
		if c is VisualInstance3D:
			var b: AABB = c.get_aabb()
			bounds = bounds.merge(b)

	# 2. Trigger: a box around the door, grown by trigger_range.
	collision_mask = _func_godot_properties.get("collision_mask", ~0)
	var trigger_range = _func_godot_properties.get("trigger_range", 0.0)
	trigger = Area3D.new()
	trigger.name = "Trigger"
	trigger.collision_layer = 0
	trigger.collision_mask = collision_mask
	var box := BoxShape3D.new()
	box.size = bounds.size + Vector3.ONE * trigger_range * 2.0
	var trigger_shape := CollisionShape3D.new()
	trigger_shape.shape = box
	trigger_shape.position = bounds.get_center() # center, not the AABB corner
	trigger.add_child(trigger_shape)
	add_child(trigger)

	# 3. Mover: variables named like FGD properties (move_time, ...) are set by name.
	var move_type = _func_godot_properties.get("move_type", 0)
	var displacement = _func_godot_properties.get("displacement", Vector3.FORWARD)
	if move_type == 0:
		mover = SlideMover.new()
		mover.offset = displacement
	elif move_type == 1:
		mover = RotateMover.new()
		mover.degrees = displacement.length()
		mover.axis = displacement.normalized()

	# 4. Interactable: "enabled" means locked, as in the original script.
	var locked = _func_godot_properties.get("locked", false)
	interactable = Interactable.new()
	interactable.enabled = locked
	add_child(interactable)

	MapEntityBridge.set_owner_recursive(trigger, owner)
	MapEntityBridge.set_owner_recursive(interactable, owner)

	_setup()

func _ready() -> void:
	if mover:
		_setup()

func _setup() -> void:
	if mover == null:
		push_error("Door '%s' has no mover assigned" % name)
	else:
		mover.setup(self)
		mover.finished.connect(_on_mover_finished)

	_close_timer = Timer.new()
	_close_timer.one_shot = true
	_close_timer.timeout.connect(close)
	add_child(_close_timer)

	trigger.body_entered.connect(_on_body_entered)
	trigger.body_exited.connect(_on_body_exited)
	interactable.interacted.connect(interact)


# --- Public API -------------------------------------------------------------

func open() -> void:
	if mover == null or interactable.enabled or state == State.OPEN or state == State.OPENING:
		return
	state = State.OPENING
	_close_timer.stop()
	mover.move(true)


func close() -> void:
	if mover == null or state == State.CLOSED or state == State.CLOSING:
		return
	if not _occupants.is_empty():
		return  # don't shut the door on someone standing in it
	state = State.CLOSING
	mover.move(false)


func toggle() -> void:
	if state == State.OPEN or state == State.OPENING:
		close()
	else:
		open()


func unlock() -> void:
	interactable.enabled = false


## Call from the player's interact/use logic for doors with auto_open = false,
## or interactable.enabled doors that need a key.
func interact(by: Node3D) -> void:
	if interactable.enabled and not _try_unlock(by):
		unlock_failed.emit(by)
		return
	toggle()


# --- Internals --------------------------------------------------------------

func _on_mover_finished(was_open: bool) -> void:
	if was_open:
		state = State.OPEN
		opened.emit()
		if _occupants.is_empty():  # player walked away while it was opening
			_start_close_timer()
	else:
		state = State.CLOSED
		closed.emit()


func _start_close_timer() -> void:
	if auto_close_delay > 0.0:
		_close_timer.start(auto_close_delay)


func _try_unlock(by: Node3D) -> bool:
	if not interactable.enabled:
		return true
	if key_id.is_empty():
		return false
	if by and by.has_method("has_key") and by.has_key(key_id):
		interactable.enabled = false
		return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_occupants.append(body)
	_close_timer.stop()

	if not auto_open:
		return
	if interactable.enabled and not _try_unlock(body):
		unlock_failed.emit(body)
		return
	open()


func _on_body_exited(body: Node3D) -> void:
	_occupants.erase(body)
	if _occupants.is_empty() and state == State.OPEN:
		_start_close_timer()
