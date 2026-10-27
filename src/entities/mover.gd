@abstract
class_name Mover extends Resource
## A mover that tweens a 0..1 progress value and calls _apply(t) each step.
## Subclasses only describe the pose at a given t:
##   t = 0.0 -> fully closed, t = 1.0 -> fully open

## Seconds for a full open or close. Reversing mid-move takes the remaining fraction.
@export var move_time := 0.6
@export var transition: Tween.TransitionType = Tween.TRANS_CUBIC
@export var easing: Tween.EaseType = Tween.EASE_OUT

var node: Node3D
var _progress := 0.0
var _closed: Transform3D  # node transform when closed, in its parent's space
var _tween: Tween

## Emitted when a move completes. `opened` is true if the door ended up open.
## Must NOT be emitted if the move was interrupted by a newer move() call.
signal finished(opened: bool)

## Called once by the Door in _ready(). Capture the closed pose here.
func setup(p: Node3D) -> void:
	node = p
	_closed = p.transform


func move(opening: bool) -> void:
	var target := 1.0 if opening else 0.0
	if _tween:
		_tween.kill()  # a killed tween never emits `finished`
	_tween = node.create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # smoother with AnimatableBody3D
	_tween.set_trans(transition).set_ease(easing)
	_tween.tween_method(_set_progress, _progress, target, move_time * absf(target - _progress))
	_tween.finished.connect(func(): finished.emit(opening))


func _set_progress(t: float) -> void:
	_progress = t
	_apply(t)


## Override: place `node` for progress `t`, relative to `_closed`.
@abstract
func _apply(_t: float) -> void
