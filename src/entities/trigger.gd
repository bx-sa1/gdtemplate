@tool
extends Area3D

var interactable: Interactable = Interactable.new()
	
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
func _on_body_entered(body: Node3D) -> void:
	interactable.force_interact(body)
	queue_free()
	
func _func_godot_apply_properties(props: Dictionary) -> void:
	if props.has("targetname"):
		interactable.targetname = props["targetname"]
		
	if props.has("target"):
		interactable.target = props["target"]
		
func _func_godot_build_complete() -> void:
	add_child(interactable)
	interactable.owner = get_owner()
	
