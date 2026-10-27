class_name RotateMover extends Mover
## Swings the panel around `axis` (in the panel's local space).
## Put the panel's origin at the hinge.

@export_range(-180.0, 180.0, 1.0, "degrees") var degrees := 90.0
@export var axis := Vector3.UP


func _apply(t: float) -> void:
	var swing := Basis(axis.normalized(), deg_to_rad(degrees) * t)
	node.transform = Transform3D(_closed.basis * swing, _closed.origin)
