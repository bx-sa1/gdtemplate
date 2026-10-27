class_name SlideMover extends Mover
## Slides the panel by `offset` (in the Door's local space).

@export var offset := Vector3(0.0, 3.0, 0.0)


func _apply(t: float) -> void:
	node.transform = Transform3D(_closed.basis, _closed.origin + offset * t)
