class_name MapEntityBridge
extends RefCounted
## The only code that knows how map properties reach a node.
## Entity scripts never reference FuncGodot; they declare plain variables whose
## names match the FGD property names, and this copies the values onto them.


static func apply(node: Node, props: Dictionary) -> void:
	# Collect script variables (this script and its custom base scripts).
	var types := {}
	var s: Script = node.get_script()
	while s != null:
		for p: Dictionary in s.get_script_property_list():
			if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and not types.has(p.name):
				types[p.name] = p.type
		s = s.get_base_script()

	for key in props:
		if not types.has(key):
			continue # not a script variable, so engine properties can't be hit by accident
		var t: int = types[key]
		var value = props[key]
		if t != TYPE_NIL and t != TYPE_OBJECT:
			value = type_convert(value, t) # e.g. FGD 0/1 -> bool
		node.set(key, value)

static func axis_tb_to_gd(v: Vector3) -> Vector3:
	return Vector3()

static func get_class_properties(classname: StringName) -> Dictionary[String, Variant]:
	var class_list := ProjectSettings.get_global_class_list()
	var script: Object = null
	for cls: Dictionary in class_list:
		if cls.class == classname:
			script = load(cls.path).new()
			break

	if not script:
		return {}

	var props := {}
	for p: Dictionary in script.get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and not props.has(p.name):
			props[p.name] = script.get(p.name)

	return props

static func set_owner_recursive(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for child in node.get_children():
		set_owner_recursive(child, new_owner)
