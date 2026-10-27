extends SceneTree
## Builds the modding SDK from the game project, so it can't drift.
##
## Run from the project root:
##   godot --headless --path . --script res://sdk/build_sdk.gd -- \
##       --version=1.2.0 --prev=/path/to/previous/contract.json
##
## Exit code is 1 if the contract has breaking changes (CI should fail).
##
## Source of truth: the FGD resource below and the scripts its entities use.
## Anything in the SDK that isn't copied or generated from those is a bug.

# ---- Configuration ---------------------------------------------------------

## Your FuncGodotFGDFile resource.
const FGD_PATH := "res://entities/fgd/fgd.tres"

## Where the SDK is assembled. Add this to .gitignore.
const OUT_DIR := "res://build/sdk"

## Removals that are intentional (deprecation finished). JSON array of
## "entity_name" or "entity_name.property". Optional file.
const ALLOWED_REMOVALS_PATH := "res://sdk/allowed_removals.json"

## Folders copied verbatim into the SDK: source -> path inside SDK.
const COPY_DIRS := {
	"res://addons/func_godot": "addons/func_godot",
	"res://sdk/examples": "examples",
	"res://sdk/trenchbroom": "trenchbroom",
	"res://sdk/placeholder_textures": "textures",
	# "res://sdk/template": "",
}

# ---------------------------------------------------------------------------

var _args := {}


func _initialize() -> void:
	_parse_args()
	var version: String = _args.get("version", _git_version())
	var out := ProjectSettings.globalize_path(OUT_DIR)

	print("Building SDK %s -> %s" % [version, out])
	_clear_dir(out)
	DirAccess.make_dir_recursive_absolute(out)

	# 1. Load the FGD and gather every entity definition (including bases).
	_preload_global_classes()
	var fgd: Resource = load(FGD_PATH)
	if fgd == null:
		_fail("Could not load FGD at %s" % FGD_PATH)
		return
	var defs: Array = _gather_defs(fgd.get("entity_definitions"))
	print("  %d entity definitions" % defs.size())

	# 2. Contract, and diff against the previous release.
	var contract := _build_contract(defs, version)
	var prev_path: String = _args.get("prev", "")
	if prev_path != "" and not FileAccess.file_exists(prev_path):
		push_warning("--prev file not found (%s), skipping contract diff." % prev_path)
		prev_path = ""
	if prev_path != "":
		var errors := _diff(_load_json(prev_path), contract, _load_allowed_removals())
		if not errors.is_empty():
			for e in errors:
				printerr("  BREAKING: " + e)
			_fail("Contract has %d breaking change(s). Deprecate instead, or list them in %s." % [errors.size(), ALLOWED_REMOVALS_PATH])
			return
	_write(out.path_join("contract.json"), JSON.stringify(contract, "\t"))

	# 3. Copy static SDK content.
	for src: String in COPY_DIRS:
		_copy_dir(src, out.path_join(COPY_DIRS[src]))

	# 4. Copy entity/FGD resources at the same res:// paths they have in the game,
	#    and generate stubs for their scripts at the same paths.
	var stub_count := 0
	for d: Resource in defs:
		_copy_res(d.resource_path, out)
		var s: Script = d.get("script_class") as Script
		if s != null and s.resource_path != "":
			var stub := _make_stub(s)
			if stub != "":
				_write(out.path_join(s.resource_path.trim_prefix("res://")), stub)
				stub_count += 1
	_copy_res(FGD_PATH, out)
	print("  %d stubs generated" % stub_count)

	# 5. Export the .fgd text file straight from the same resources.
	_export_fgd(fgd, out)

	# 6. Version stamp, then zip.
	_write(out.path_join("sdk_version.txt"), version)
	var zip_path := out.get_base_dir().path_join("sdk-%s.zip" % version)
	_zip_dir(out, zip_path)
	print("Done: %s" % zip_path)
	quit(0)


# ---- Contract --------------------------------------------------------------

## Loads every global-class script before any .tres. The editor does this at
## startup; in --script mode nothing does, so loading an FGD .tres first can
## enter a script <-> resource preload cycle from the resource side and fail.
func _preload_global_classes() -> void:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = c.get("path", "")
		if path != "":
			load(path)


func _gather_defs(roots: Array) -> Array:
	var seen := {}
	var result := []
	var stack := roots.duplicate()
	while not stack.is_empty():
		var d: Resource = stack.pop_back()
		if d == null or seen.has(d.get("classname")):
			continue
		seen[d.get("classname")] = true
		result.append(d)
		stack.append_array(d.get("base_classes"))
	return result


func _build_contract(defs: Array, version: String) -> Dictionary:
	var entities := {}
	for d: Resource in defs:
		var bases: Array = []
		for b: Resource in d.get("base_classes"):
			bases.append(b.get("classname"))
		entities[d.get("classname")] = {
			"class_type": str(d.get_script().get_global_name()),
			"base_classes": bases,
			"properties": _effective_props(d),
		}
	return {
		"sdk_version": version,
		"godot_version": Engine.get_version_info().get("string", ""),
		"entities": entities,
	}


func _effective_props(d: Resource) -> Dictionary:
	var out := {}
	for b: Resource in d.get("base_classes"):
		out.merge(_effective_props(b), true)
	var props: Dictionary = d.get("class_properties")
	for k in props:
		out[k] = {
			"type": type_string(typeof(props[k])),
			"default": var_to_str(props[k]),
		}
	return out


func _diff(prev: Dictionary, cur: Dictionary, allowed: Array) -> Array[String]:
	var errs: Array[String] = []
	var pe: Dictionary = prev.get("entities", {})
	var ce: Dictionary = cur["entities"]
	for ename: String in pe:
		if not ce.has(ename):
			if not allowed.has(ename):
				errs.append("entity removed: %s" % ename)
			continue
		var pp: Dictionary = pe[ename]["properties"]
		var cp: Dictionary = ce[ename]["properties"]
		for pname: String in pp:
			var key := "%s.%s" % [ename, pname]
			if not cp.has(pname):
				if not allowed.has(key):
					errs.append("property removed: %s" % key)
			elif cp[pname]["type"] != pp[pname]["type"]:
				errs.append("property type changed: %s (%s -> %s)" % [key, pp[pname]["type"], cp[pname]["type"]])
	return errs


func _load_allowed_removals() -> Array:
	if not FileAccess.file_exists(ALLOWED_REMOVALS_PATH):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(ALLOWED_REMOVALS_PATH))
	return data if data is Array else []


# ---- Stub generation -------------------------------------------------------
# Convention: members starting with "_" are private and omitted from stubs.

func _make_stub(s: Script) -> String:
	if not s.can_instantiate():
		push_warning("Skipping stub for %s (can't instantiate in script mode; autoload dependency?)" % s.resource_path)
		return ""

	var out := "# AUTO-GENERATED by build_sdk.gd from the game project. Do not edit.\n"
	var gname := s.get_global_name()
	if gname != &"":
		out += "class_name %s\n" % gname
	out += "extends %s\n\n" % s.get_instance_base_type()

	var inst = (s as GDScript).new()

	# Constants and enums
	var consts := s.get_script_constant_map()
	for cname: String in consts:
		if cname.begins_with("_"):
			continue
		var v = consts[cname]
		if v is Script or v is Resource:
			continue
		out += "const %s = %s\n" % [cname, var_to_str(v)]
	out += "\n"

	# Signals
	for sig: Dictionary in s.get_script_signal_list():
		var sargs: Array[String] = []
		for a: Dictionary in sig.args:
			sargs.append(a.name)
		out += "signal %s(%s)\n" % [sig.name, ", ".join(sargs)]
	out += "\n"

	# Variables, with defaults read from a real instance
	for p: Dictionary in s.get_script_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or String(p.name).begins_with("_"):
			continue
		var prefix := "@export " if (p.usage & PROPERTY_USAGE_EDITOR) else ""
		if p.type == TYPE_OBJECT or p.type == TYPE_NIL:
			out += "%svar %s = null\n" % [prefix, p.name]
		else:
			out += "%svar %s: %s = %s\n" % [prefix, p.name, type_string(p.type), var_to_str(inst.get(p.name))]
	out += "\n"

	# Public methods, bodies empty. Return types are left off so `pass` is valid.
	for m: Dictionary in s.get_script_method_list():
		if String(m.name).begins_with("_"):
			continue
		var margs: Array[String] = []
		var n: int = m.args.size()
		var ndef: int = m.default_args.size()
		for i in n:
			var a: Dictionary = m.args[i]
			var arg: String = a.name
			if a.type != TYPE_NIL and a.type != TYPE_OBJECT:
				arg += ": " + type_string(a.type)
			if i >= n - ndef:
				arg += " = " + var_to_str(m.default_args[i - (n - ndef)])
			margs.append(arg)
		var static_kw := "static " if (m.flags & METHOD_FLAG_STATIC) else ""
		out += "%sfunc %s(%s):\n\tpass\n\n" % [static_kw, m.name, ", ".join(margs)]

	if inst is Node:
		inst.free()
	return out


# ---- FGD export ------------------------------------------------------------

func _export_fgd(fgd: Resource, out: String) -> void:
	if not fgd.has_method("export_file"):
		push_warning("FGD resource has no export_file(); export it manually and drop it in trenchbroom/.")
		return
	fgd.call("export_file")
	var folder := str(fgd.get("export_folder"))
	var fname := str(fgd.get("fgd_name")) + ".fgd"
	var src := folder.path_join(fname)
	if not FileAccess.file_exists(src):
		push_warning("Expected exported FGD at %s but it wasn't there. Check your FuncGodot version's export settings." % src)
		return
	_copy_file(src, out.path_join("trenchbroom").path_join(fname))


# ---- File helpers ----------------------------------------------------------

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1]


func _git_version() -> String:
	var o := []
	if OS.execute("git", ["describe", "--tags", "--always"], o) == 0 and o.size() > 0:
		return String(o[0]).strip_edges()
	return "dev"


func _load_json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Can't write %s" % path)
		return
	f.store_string(text)


func _copy_file(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		push_error("Can't write %s" % dst)
		return
	f.store_buffer(FileAccess.get_file_as_bytes(src))


func _copy_res(res_path: String, out: String) -> void:
	if res_path != "" and FileAccess.file_exists(res_path):
		_copy_file(res_path, out.path_join(res_path.trim_prefix("res://")))


func _copy_dir(src: String, dst: String) -> void:
	var d := DirAccess.open(src)
	if d == null:
		push_warning("SDK source folder missing, skipped: %s" % src)
		return
	DirAccess.make_dir_recursive_absolute(dst)
	for f in d.get_files():
		if f.ends_with(".import"):
			continue # Godot regenerates these in the SDK project
		_copy_file(src.path_join(f), dst.path_join(f))
	for sub in d.get_directories():
		_copy_dir(src.path_join(sub), dst.path_join(sub))


func _clear_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_clear_dir(path.path_join(sub))
		DirAccess.remove_absolute(path.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))


func _zip_dir(dir: String, zip_path: String) -> void:
	var z := ZIPPacker.new()
	if z.open(zip_path) != OK:
		push_error("Can't create %s" % zip_path)
		return
	_zip_add(z, dir, "")
	z.close()


func _zip_add(z: ZIPPacker, base: String, rel: String) -> void:
	var full := base if rel == "" else base.path_join(rel)
	var d := DirAccess.open(full)
	for f in d.get_files():
		z.start_file(f if rel == "" else rel.path_join(f))
		z.write_file(FileAccess.get_file_as_bytes(full.path_join(f)))
		z.close_file()
	for sub in d.get_directories():
		_zip_add(z, base, sub if rel == "" else rel.path_join(sub))


func _fail(msg: String) -> void:
	printerr("SDK build failed: " + msg)
	quit(1)
