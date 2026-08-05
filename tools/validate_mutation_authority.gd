# Run from the project root:
# godot --headless --path . -s res://tools/validate_mutation_authority.gd
extends SceneTree

# Enforces the mutation-authority convention (plan 0042):
#
#   Every mutable gameplay aggregate has one named authority. Calculators return outcomes; only the
#   authority applies them.
#
# The ownership facts live in ONE machine-readable home, tools/mutation_authority_manifest.json:
# authority class, protected fields, construction allowances, and temporary legacy writers with the
# plan that removes each one. Code headers and systems docs point at the manifest; they must never
# copy its lists, because a copied list rots silently.
#
# ── WHY A SOURCE GATE, AND WHAT IT CAN ACTUALLY SEE ──────────────────────────────────────────────
# Availability of an API does not prevent `system.quantity = 0`. GDScript has no `readonly`, and a
# passed Resource/Array/Dictionary is always a live alias. So the guard has to read source.
#
# Field NAMES alone are not enough: `destroyed` is a field of AntishipSystem, IjfsTarget, ShipState
# AND Brigade, so scanning for `.destroyed =` flags four unrelated aggregates. This validator
# therefore resolves the RECEIVER's type first and only then asks whether that (class, field) pair
# is protected. Measured on the tree at plan 0042: 591 receiver-chain assignments in scripts/, of
# which 19 had no annotation on the receiver — the house style is typed, so type-directed detection
# is credible here rather than aspirational.
#
# A receiver resolves from, in order: an explicit annotation (member, local, parameter, `for x: T`),
# `:= T.new()`, `:= call()` through the callee's DECLARED return type, an untyped `for x in arr`
# where `arr`'s declaration is `Array[T]`, and a dotted chain chased through declared field types
# with each `[…]` unwrapping one `Array[T]`.
# Scopes are per-function over a file-level scope, because `GameData` binds the name `entry` to two
# different types in two loaders (`Dictionary` and `InfrastructureDef`) and a file-global map called
# both ambiguous, reporting a write it should have cleared.
#
# DETECTED WRITE FORMS (each proven abstractly by a fixture under
# tools/fixtures/mutation_authority/, compared exactly on every run — a missed form fails this gate
# as a false negative):
#   direct_assign       recv.field = x
#   compound_assign     recv.field += x                    (also -= *= /= %= |= &= ^=)
#   element_assign      recv.field[k] = x
#   container_mutate    recv.field.append(...)             (and the other in-place Array/Dictionary
#                                                           mutators — see MUTATOR_METHODS; an index
#                                                           in between, recv.field[i].append(x), also
#                                                           counts)
#   dynamic_set         recv.set("field", x)               (also set_indexed / set_deferred, and a
#                                                           &"name" or variable key; reported against
#                                                           the CLASS, since a computed key names no
#                                                           particular field)
#   model_mutator       recv.some_method()                 where some_method is defined ON the
#                                                           protected model and either assigns a
#                                                           protected field or mutates one in place —
#                                                           the bypass a "just add a setter" refactor
#                                                           creates
#   cast_assign         (thing as Model).field = x
#   unresolved_receiver <unknown>.field = x                where `field` is protected on SOME
#                                                           aggregate and the receiver's type cannot
#                                                           be resolved. This is the false-NEGATIVE
#                                                           backstop: an unannotated alias fails
#                                                           loudly asking to be annotated, instead of
#                                                           slipping past unseen.
#
# KNOWN LIMITS, stated rather than papered over:
#   - One name bound to two types inside ONE function resolves to "ambiguous", which degrades to
#     unresolved_receiver (loud), never to silence. Lambdas are not scope boundaries: their
#     parameters join the enclosing function's scope, so two lambdas in one function that name a
#     parameter differently will read as ambiguous — again loud, not silent.
#   - `var row = untyped_expr()` — a bare `=` with no annotation, or a call whose callee declares no
#     return type — leaves the receiver unresolved. That is reported only when the write targets a
#     protected field NAME. A protected object reached through a name that collides with nothing
#     else is therefore the residual blind spot, and the reason field names are kept distinctive.
#   - Element type is read from DECLARATIONS only. `for row in some_dict.values()` and
#     `var row = rows[i]` on an untyped Array stay unresolved.
#   - A protected CONTAINER aliased into a local and mutated through that alias
#     (`var rows = state.antiship_systems` … then ANY in-place mutator on `rows` — `append`, `clear`,
#     `erase`, `resize`, `sort`, …) is invisible: the alias is untyped and the mutator's name is not a
#     protected field name, so neither the type check nor the name backstop fires. Closing it needs
#     alias dataflow, not a scanner. Today every real mutation reaches these rows by being PASSED to a
#     function that writes through a typed receiver, which is caught at the write site; plan 0043
#     should re-check that when it builds the authority.
#   - Statements are read one line at a time; only `\` continuations are rejoined. GDScript's other
#     multi-line form — a statement spread across an open bracket, e.g. `rows[\n  i\n].quantity = 0`
#     — is not seen. (Breaking after a bare `.` is NOT a GDScript continuation at all; it is a parse
#     error, so it needs no handling here — verified by running it.)
#   - Scope is scan_roots in the manifest (scripts/ + tools/). tests/ is deliberately excluded:
#     suites legitimately build and mutate their own fixture rows.
#   - Reflection (`Object.call("set_" + name)`, `Callable`s built from strings) is not modelled. No
#     such call exists in the tree; if one is added, it is invisible here.
#
# The abstract fixtures prove scanner FORMS, not production ownership. A second, generated contract
# pass scans one typed illegal assignment per REAL manifest claim plus every ordered wrong-authority
# pair against the REAL corpus and ownership. Its expectations come from the real manifest;
# a committed claim pin is the independent oracle that makes deleting or demoting a claim fail rather
# than also deleting its generated probe. The pin is regression evidence, never an ownership input.
#
# The manifest is checked as hard as the source: dead paths, dead fields, an unclassified field
# added to an owned model, two aggregates claiming one field, a stale allowance that no longer
# writes anything, and a scan that saw nothing all fail. Prints PASS:/FAIL: for the gate's verdict.
#
# ── SHARED MODELS ARE CLOSED-WORLD TOO ──────────────────────────────────────────────────────────
# `owned_models` has always been exhaustive; `hosted_fields` was not, so a field added to a model two
# aggregates share — GameStateData most of all — arrived unprotected and nothing said so. Every class
# any aggregate hosts must now account for every mutable field it declares: claimed by exactly one
# aggregate, or listed under the manifest's `shared_model_policies` with a classification from the
# closed vocabulary in POLICY_CLASSIFICATIONS and a concrete reason. Claimed and excluded at once
# fails, as does an exclusion for a field that no longer exists.
#
# That section is NOT a second ownership list: claimed fields are derived from `hosted_fields`, and
# naming one in a policy is an error rather than a duplicate. A classification that is a PROMISE
# (`planned_transitional`, `order_buffer`) additionally names the plan that takes the field over; the
# pointer must sit under the manifest's `plan_dir` AND still resolve, so a shipped plan being archived
# turns its exclusion red exactly when the reason expires, while a pointer at some other existing file
# — which could never go stale — is rejected outright.

const MANIFEST_PATH := "res://tools/mutation_authority_manifest.json"
const FIXTURE_DIR := "res://tools/fixtures/mutation_authority"
const FIXTURE_EXT := ".gdfixture"
const REAL_CLAIMS_PIN_PATH := "res://tools/fixtures/mutation_authority/real_claims_pin.json"
const GENERATED_REAL_PROBE_PATH := "res://tools/fixtures/mutation_authority/generated_real_contract.gdprobe"

const ASSIGN_OPS := "=(?!=)|\\+=|-=|\\*=|/=|%=|\\|=|&=|\\^="
# A type annotation, keeping any element type: `IjfsTarget`, `Array`, `Array[IjfsTarget]`.
const TYPE_EXPR := "[A-Za-z_]\\w*(?:\\[[A-Za-z_]\\w*\\])?"
# A receiver expression: `row`, `state.sealift_state`, `rows[i]`, `state.antiship_systems[0]`.
# The index segments are load-bearing — without them `rows[i].quantity = 0` matched NOTHING at all,
# neither as a protected write nor as an unresolved one.
const CHAIN_EXPR := "[A-Za-z_]\\w*(?:\\[[^\\]\\n]*\\])*(?:\\s*\\.\\s*[A-Za-z_]\\w*(?:\\[[^\\]\\n]*\\])*)*"
const MUTATOR_METHODS := [
	"append", "append_array", "push_back", "push_front", "pop_back", "pop_front", "pop_at",
	"erase", "clear", "insert", "remove_at", "resize", "sort", "sort_custom", "reverse",
	"shuffle", "fill", "merge", "assign",
]
const DYNAMIC_SETTERS := ["set", "set_indexed", "set_deferred"]
# Why a mutable field on a SHARED model may go unclaimed. The vocabulary is closed, so a new reason
# costs an edit here and a reviewer's attention rather than arriving as free text nobody reads. The
# value says whether the entry must also name the plan that ends it.
#   identity_construction_only  fixed when the object is built and never written again
#   content_config              scenario/content loaded once by its loader; not gameplay state
#   derived_projection          recomputed from authoritative state; never the source of truth
#   phase_output                a per-turn record the producing phase replaces wholesale. NOT the same
#                               as write-only: six of the eleven last_* slots are read back by a later
#                               phase in the same turn, so each entry names its consumer.
#   order_buffer                a request queue players fill and a phase drains — plan 0049's
#                               OrderTransitions owns all four, so this one names a plan too
#   planned_transitional        real state a named plan is going to take ownership of
const POLICY_CLASSIFICATIONS := {
	"identity_construction_only": false,
	"content_config": false,
	"derived_projection": false,
	"phase_output": false,
	"order_buffer": true,
	"planned_transitional": true,
}

var _h := ValidatorHarness.new("mutation-authority validation")
var _regex_cache: Dictionary = {}
var _real_contract_ran: bool = false


## Compiled once per pattern and reused — the scan matchers run per line, over ~180 files.
## A RegEx that fails to compile silently returns NO matches, which would turn this gate blind
## rather than red, so a compile failure is itself a hard failure.
func _regex(pattern: String) -> RegEx:
	if _regex_cache.has(pattern):
		return _regex_cache[pattern]
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		_fail("E_VACUOUS: detector pattern failed to compile, so it would match nothing: `%s`" % pattern)
	_regex_cache[pattern] = regex
	return regex


func _initialize() -> void:
	print("=== Mutation-authority validation (plan 0042) ===")
	_run_self_test()
	_run_real_scan()
	_finish()


# ── Context: the source corpus a scan runs against ──────────────────────────────────────────────

## Everything the scanner needs to know about a set of source files: their stripped bodies, which
## class each declares, and each class's declared fields and their types. Built once per corpus so
## the fixture self-test and the real scan share exactly one code path.
class Corpus:
	extends RefCounted

	var raw: Dictionary = {}            # path -> original text
	var stripped: Dictionary = {}       # path -> comments/strings blanked, line numbers preserved
	var class_of: Dictionary = {}       # path -> class_name
	var path_of: Dictionary = {}        # class_name -> path
	var fields_of: Dictionary = {}      # class_name -> {field_name: declared_type}
	var order_of: Dictionary = {}       # class_name -> Array[String] in declaration order
	var returns_of: Dictionary = {}     # path -> {method_name: declared return type}


func _build_corpus(paths: Array) -> Corpus:
	var corpus := Corpus.new()
	for path_value in paths:
		var path := String(path_value)
		var text := FileAccess.get_file_as_string(path)
		corpus.raw[path] = text
		corpus.stripped[path] = _strip(text)
		corpus.returns_of[path] = _declared_returns(String(corpus.stripped[path]))
		var class_id := _class_name_of(String(corpus.stripped[path]))
		if class_id.is_empty():
			continue
		corpus.class_of[path] = class_id
		corpus.path_of[class_id] = path
		var declared := _declared_fields(String(corpus.stripped[path]))
		corpus.fields_of[class_id] = declared["types"]
		corpus.order_of[class_id] = declared["order"]
	return corpus


## Member `var` declarations of a class body: name -> declared type ("" when untyped). The element
## type of a typed array is kept (`Array[IjfsTarget]`, not `Array`) because that is what tells the
## scanner what an untyped `for` over that field is iterating.
##
## ANY annotation prefix counts, not just bare `@export`/`@onready`, and `static var` counts too. This
## regex is what BOTH exhaustiveness checks enumerate, so a declaration form it cannot see is a field
## that is neither protected nor reported — `@export_range(0, 10) var x` used to be exactly that.
## Proven by the annotated/static fields on the abstract FixtureHost and their bad-manifest fixtures.
func _declared_fields(body: String) -> Dictionary:
	var regex := _regex("(?m)^(?:@[a-z_]+(?:\\([^)]*\\))?\\s+)*(?:static\\s+)?var\\s+([A-Za-z_]\\w*)\\s*(?::\\s*(%s))?" % TYPE_EXPR)
	var types: Dictionary = {}
	var order: Array[String] = []
	for found in regex.search_all(body):
		var field := found.get_string(1)
		if types.has(field):
			continue
		types[field] = found.get_string(2)
		order.append(field)
	return {"types": types, "order": order}


## method name -> declared return type, so `var row := _build_row()` resolves as precisely as
## `var row: SomeModel = _build_row()` would. Without this, the commonest GDScript idiom in this
## codebase would be permanently unresolvable and every use would have to be hand-annotated.
func _declared_returns(body: String) -> Dictionary:
	# The parameter list is matched with one level of nesting rather than `.*?`, so a function with
	# no declared return type cannot borrow the `-> Type` of the function after it.
	var regex := _regex("\\bfunc\\s+([A-Za-z_]\\w*)\\s*\\((?:[^()]|\\([^()]*\\))*\\)\\s*->\\s*(%s)" % TYPE_EXPR)
	var returns: Dictionary = {}
	for found in regex.search_all(body):
		returns[found.get_string(1)] = found.get_string(2)
	return returns


# ── Ownership: the manifest reduced to lookup tables ────────────────────────────────────────────

## The manifest's ownership facts in the shape the scanner asks questions in.
class Ownership:
	extends RefCounted

	var protected: Dictionary = {}      # "Class.field" -> {aggregate, lifetime}
	var field_names: Dictionary = {}    # field_name -> true (for the unresolved-receiver backstop)
	var owner_paths: Dictionary = {}    # path -> true (a model may write its own protected fields)
	var allowances: Dictionary = {}     # "path|Class.field" -> {aggregate, kind, removal_plan}
	var authority_paths: Dictionary = {}# path -> aggregate id
	var mutators: Dictionary = {}       # "Class.method" -> aggregate id


## What judging a scan against an Ownership produced: the writes that are NOT permitted, plus which
## allowances and authorities were actually exercised. The usage record lives here rather than being
## written back into Ownership, so the same findings can be judged twice against different baselines
## — which is how the inert-authority direction is proven without hand-building a stripped Ownership.
class Verdict:
	extends RefCounted

	var violations: Array[Finding] = []
	var allowance_used: Dictionary = {}   # "path|Class.field" -> true
	var authority_used: Dictionary = {}   # authority path -> true


func _build_ownership(manifest: Dictionary, corpus: Corpus) -> Ownership:
	var ownership := Ownership.new()
	for aggregate_value in manifest.get("aggregates", []):
		var aggregate: Dictionary = aggregate_value
		var aggregate_id := _text(aggregate.get("id", ""))
		_claim_model_fields(ownership, aggregate, aggregate_id, "owned_models")
		_claim_model_fields(ownership, aggregate, aggregate_id, "hosted_fields")
		_claim_allowances(ownership, aggregate, aggregate_id, "construction_writers", "construction")
		_claim_allowances(ownership, aggregate, aggregate_id, "legacy_writers", "legacy")
		var authority_path := _text(aggregate.get("authority_path", ""))
		if not authority_path.is_empty():
			ownership.authority_paths[authority_path] = aggregate_id
	_collect_model_mutators(ownership, corpus)
	return ownership


func _claim_model_fields(
		ownership: Ownership, aggregate: Dictionary, aggregate_id: String, section: String) -> void:
	for entry_value in aggregate.get(section, []):
		var entry: Dictionary = entry_value
		var class_id := _text(entry.get("class", ""))
		var path := _text(entry.get("path", ""))
		if section == "owned_models" and not path.is_empty():
			ownership.owner_paths[path] = aggregate_id
		for field_value in Dictionary(entry.get("fields", {})).keys():
			var key := "%s.%s" % [class_id, String(field_value)]
			if ownership.protected.has(key):
				var prior: Dictionary = ownership.protected[key]
				_fail("E_DUPLICATE_CLAIM: %s is claimed by both '%s' and '%s' — one field, one aggregate." % [
					key, String(prior["aggregate"]), aggregate_id])
				continue
			ownership.protected[key] = {
				"aggregate": aggregate_id,
				"lifetime": String(Dictionary(entry.get("fields", {}))[field_value]),
			}
			ownership.field_names[String(field_value)] = true


func _claim_allowances(
		ownership: Ownership, aggregate: Dictionary, aggregate_id: String,
		section: String, kind: String) -> void:
	for entry_value in aggregate.get(section, []):
		var entry: Dictionary = entry_value
		var path := _text(entry.get("path", ""))
		for field_value in entry.get("fields", []):
			ownership.allowances["%s|%s" % [path, String(field_value)]] = {
				"aggregate": aggregate_id,
				"kind": kind,
				"path": path,
				"symbol": String(field_value),
				"removal_plan": _text(entry.get("removal_plan", "")),
			}


## Methods DEFINED on a protected model that write one of its own protected fields. Calling one from
## outside the authority is a bypass dressed as an API, so the scan treats such a call as a write.
func _collect_model_mutators(ownership: Ownership, corpus: Corpus) -> void:
	for key in ownership.protected.keys():
		var class_id := String(key).get_slice(".", 0)
		if not corpus.path_of.has(class_id):
			continue
		var body := String(corpus.stripped[corpus.path_of[class_id]])
		for method in _methods_writing_fields(body, class_id, ownership):
			ownership.mutators["%s.%s" % [class_id, method]] = ownership.protected[key]["aggregate"]


func _methods_writing_fields(body: String, class_id: String, ownership: Ownership) -> Array[String]:
	var out: Array[String] = []
	var lines := body.split("\n")
	var current := ""
	var func_regex := _regex("^\\s*(?:static\\s+)?func\\s+([A-Za-z_]\\w*)")
	var write_regex := _regex(
		"^\\s+(?:self\\s*\\.\\s*)?([A-Za-z_]\\w*)\\s*(?:\\[[^\\]]*\\])?\\s*(?:(?:%s)|\\.\\s*(?:%s)\\s*\\()"
		% [ASSIGN_OPS, "|".join(MUTATOR_METHODS)])
	for line_value in lines:
		var line := String(line_value)
		var found := func_regex.search(line)
		if found != null:
			current = found.get_string(1)
			continue
		if current.is_empty():
			continue
		var write := write_regex.search(line)
		if write == null:
			continue
		if ownership.protected.has("%s.%s" % [class_id, write.get_string(1)]) and not out.has(current):
			out.append(current)
	return out


# ── The scan ────────────────────────────────────────────────────────────────────────────────────

## One protected write the scan found, built in ONE place with everything it needs. It used to be an
## untyped Dictionary assembled in three passes — `_finding` built it, `_scan` bolted on path/line,
## and the dynamic-set matcher overwrote `symbol` after construction — then read by string key in a
## dozen places. `display` is why that overwrite existed: a dynamic `set()` is reported against the
## CLASS, because the key may be computed, so the text shown differs from the key looked up.
class Finding:
	extends RefCounted

	var symbol: String
	var rule: String
	var aggregate: String
	var snippet: String
	var path: String = ""
	var line: int = 0

	func _init(p_symbol: String, p_rule: String, p_aggregate: String, p_snippet: String) -> void:
		symbol = p_symbol
		rule = p_rule
		aggregate = p_aggregate
		snippet = p_snippet

	func allowance_key() -> String:
		return "%s|%s" % [path, symbol]

## Every protected write the corpus performs, as {path, line, rule, symbol, aggregate, snippet}.
## Whether a write is ALLOWED is decided afterwards, so an allowance that matches nothing can be
## reported as stale.
func _scan(corpus: Corpus, ownership: Ownership) -> Array[Finding]:
	var findings: Array[Finding] = []
	for path_value in corpus.stripped.keys():
		var path := String(path_value)
		var lines := String(corpus.stripped[path]).split("\n")
		var types := _receiver_types(lines, corpus, path)
		var logical := _join_continuations(lines)
		var self_class := String(corpus.class_of.get(path, ""))
		for index in range(lines.size()):
			for finding in _scan_line(String(logical[index]), types.at(index), corpus, ownership, self_class):
				finding.path = path
				finding.line = index + 1
				findings.append(finding)
	return findings


## A `\`-continued statement collapsed onto the physical line it starts on, with the continuation
## lines blanked so every reported line number still points at the statement's first line. Without
## this, `state. \` + newline + `antiship_systems = []` is split across two lines and matches
## nothing — a write form that disappears by being reformatted is not enforcement.
func _join_continuations(lines: PackedStringArray) -> PackedStringArray:
	var joined := lines.duplicate()
	for index in range(joined.size() - 1, -1, -1):
		var line := String(joined[index])
		if not line.strip_edges().ends_with("\\"):
			continue
		var head := line.substr(0, line.rfind("\\"))
		joined[index] = "%s %s" % [head, String(joined[index + 1]).strip_edges()]
		joined[index + 1] = ""
	return joined


## Per-line `name -> class` maps for one file. Scope matters: `GameData.load_infrastructure` and
## `GameData.load_beaches` both call their loop variable `entry` with different types, and a
## file-global map would collapse both to "ambiguous" and report two false positives.
class TypeMap:
	extends RefCounted

	var scopes: Array = []                          # Array[Dictionary], 0 = file scope
	var scope_of_line := PackedInt32Array()

	func at(line_index: int) -> Dictionary:
		return scopes[scope_of_line[line_index]]


## Every type annotation in the file, bucketed by the function it appears in: typed members and
## locals, `:=` from a constructor, typed loop variables, and typed parameters. A name annotated
## with two different types WITHIN ONE SCOPE resolves to "?" (ambiguous), which the scan then treats
## as unresolved and reports loudly rather than guessing.
func _receiver_types(lines: PackedStringArray, corpus: Corpus, path: String) -> TypeMap:
	var map := TypeMap.new()
	map.scope_of_line.resize(lines.size())
	var file_scope: Dictionary = {}
	# A class_name is itself a resolvable receiver, for `SomeClass.static_field = x`.
	for class_id in corpus.path_of.keys():
		_record_type(file_scope, String(class_id), String(class_id))
	var self_class := String(corpus.class_of.get(path, ""))
	if not self_class.is_empty():
		_record_type(file_scope, "self", self_class)
	map.scopes.append(file_scope)

	var boundary := _regex("^\\s*(?:static\\s+)?func\\s+[A-Za-z_]\\w*\\s*\\(")
	var current := 0
	var bodies: Array[String] = [""]
	for index in range(lines.size()):
		var line := String(lines[index])
		if boundary.search(line) != null:
			current = map.scopes.size()
			map.scopes.append(file_scope.duplicate())
			bodies.append("")
		map.scope_of_line[index] = current
		bodies[current] = "%s\n%s" % [bodies[current], line]

	# Members are declared at file scope but visible everywhere, so they are folded into each
	# function scope after the fact rather than being resolved through a parent chain.
	_collect_types(file_scope, bodies[0], corpus, path)
	for scope_index in range(1, map.scopes.size()):
		var scope: Dictionary = map.scopes[scope_index]
		for name in file_scope.keys():
			_record_type(scope, String(name), String(file_scope[name]))
		_collect_types(scope, bodies[scope_index], corpus, path)
	return map


func _collect_types(types: Dictionary, body: String, corpus: Corpus, path: String) -> void:
	var patterns := [
		"(?m)^\\s*(?:@[a-z_]+(?:\\([^)]*\\))?\\s+)*(?:static\\s+)?var\\s+([A-Za-z_]\\w*)\\s*:\\s*(%s)" % TYPE_EXPR,
		"(?m)^\\s*var\\s+([A-Za-z_]\\w*)\\s*:=\\s*([A-Za-z_]\\w*)\\.new\\(\\)",
		"(?m)\\bfor\\s+([A-Za-z_]\\w*)\\s*:\\s*(%s)\\s+in\\b" % TYPE_EXPR,
	]
	for pattern in patterns:
		var regex := _regex(pattern)
		for found in regex.search_all(body):
			_record_type(types, found.get_string(1), found.get_string(2))
	for name_and_type in _parameter_types(body):
		_record_type(types, String(name_and_type[0]), String(name_and_type[1]))
	_infer_from_calls(types, body, corpus, path)
	_infer_loop_elements(types, body, corpus)


## `var row := _build_row()` / `var row := SomeClass.build()` — resolved from the callee's declared
## return type. Bare calls are looked up in the file's own functions, qualified ones in the named
## class's.
func _infer_from_calls(types: Dictionary, body: String, corpus: Corpus, path: String) -> void:
	var regex := _regex("(?m)^\\s*var\\s+([A-Za-z_]\\w*)\\s*:=\\s*(?:([A-Za-z_]\\w*)\\s*\\.\\s*)?([A-Za-z_]\\w*)\\s*\\(")
	for found in regex.search_all(body):
		var owner_class := found.get_string(2)
		var owner_path := path
		if not owner_class.is_empty():
			if not corpus.path_of.has(owner_class):
				continue
			owner_path = String(corpus.path_of[owner_class])
		var returns: Dictionary = corpus.returns_of.get(owner_path, {})
		var declared := String(returns.get(found.get_string(3), ""))
		if not declared.is_empty():
			_record_type(types, found.get_string(1), declared)


## `for target in state.targets:` over an `Array[IjfsTarget]` — the element type is right there in
## the container's declaration, so an untyped loop over a typed array is not a blind spot.
func _infer_loop_elements(types: Dictionary, body: String, corpus: Corpus) -> void:
	var regex := _regex("(?m)\\bfor\\s+([A-Za-z_]\\w*)\\s+in\\s+(%s)\\s*:" % CHAIN_EXPR)
	for found in regex.search_all(body):
		var container := _resolve(found.get_string(2), types, corpus)
		if not container.begins_with("Array["):
			continue
		_record_type(types, found.get_string(1), container.trim_prefix("Array[").trim_suffix("]"))


func _record_type(types: Dictionary, name: String, type_id: String) -> void:
	if types.has(name) and String(types[name]) != type_id:
		types[name] = "?"
		return
	types[name] = type_id


## [[name, type], …] for every annotated parameter of every function signature in the file.
func _parameter_types(body: String) -> Array:
	# One level of nesting rather than `.*?`, so a default value like `f(x = g(y)) -> int:` does not
	# truncate the parameter list and quietly drop the annotations after it.
	var signature := _regex("\\bfunc(?:\\s+\\w+)?\\s*\\(((?:[^()]|\\([^()]*\\))*)\\)\\s*(?:->|:)")
	var parameter := _regex("^([A-Za-z_]\\w*)\\s*:\\s*(%s)" % TYPE_EXPR)
	var out: Array = []
	for found in signature.search_all(body):
		for part in found.get_string(1).split(","):
			var matched := parameter.search(String(part).strip_edges())
			if matched != null:
				out.append([matched.get_string(1), matched.get_string(2)])
	return out


## The class a receiver expression evaluates to, or "" when it cannot be resolved. The head comes
## from the file's annotations; each further component is chased through the declared field types of
## the class reached so far, and each `[…]` unwraps one `Array[T]`. Indexing anything whose element
## type is not declared (a bare `Array`, a `Dictionary`) resolves to "" — which the caller then
## reports as an unresolved receiver rather than passing over in silence.
func _resolve(expression: String, types: Dictionary, corpus: Corpus) -> String:
	var parts := expression.replace(" ", "").replace("\t", "").split(".")
	var current := ""
	for index in range(parts.size()):
		var part := String(parts[index])
		var name := part
		var indexings := 0
		var bracket := part.find("[")
		if bracket != -1:
			name = part.substr(0, bracket)
			indexings = part.substr(bracket).count("[")
		if index == 0:
			current = String(types.get(name, ""))
		else:
			current = String(Dictionary(corpus.fields_of.get(current, {})).get(name, ""))
		if current.is_empty() or current == "?":
			return ""
		for _step in range(indexings):
			if not current.begins_with("Array["):
				return ""
			current = current.trim_prefix("Array[").trim_suffix("]")
	return current


func _scan_line(
		line: String, types: Dictionary, corpus: Corpus, ownership: Ownership, self_class: String = "") -> Array[Finding]:
	var out: Array[Finding] = []
	out.append_array(_match_field_writes(line, types, corpus, ownership))
	out.append_array(_match_bare_member_writes(line, corpus, ownership, self_class))
	out.append_array(_match_cast_writes(line, corpus, ownership))
	out.append_array(_match_dynamic_sets(line, types, corpus, ownership))
	out.append_array(_match_mutator_calls(line, types, corpus, ownership))
	return out


## A declaration is not a write. Without this, every member declaration in a protected model reads as
## a bare write to the field it declares. The annotation prefix is part of the pattern for the same
## reason it is part of `_declared_fields`: `@export_range(0, 5) var rows_annotated = 0` does not
## START with `var`, so a keyword test flagged its initializer as `direct_assign` on a claimed field.
## Proven by the annotated claimed field on FixtureHost, which carries no `#@expect` marker.
func _is_declaration(trimmed: String) -> bool:
	var regex := _regex("^(?:@[a-z_]+(?:\\([^)]*\\))?\\s+)*(?:static\\s+)?(?:var|const|func)\\s")
	return regex.search(trimmed) != null


## Which write form a matched effect is. The three effect alternatives are mutually exclusive by
## construction, so at most one group is non-empty. Shared by the two matchers that use the same
## `<receiver> . <field> <effect>` shape but number their capture groups differently — the third copy
## of this ladder is what the duplication budget forbids.
func _effect_rule(element: String, container: String, assign: String) -> String:
	if not element.is_empty():
		return "element_assign"
	if not container.is_empty():
		return "container_mutate"
	if not assign.begins_with("="):
		return "compound_assign"
	return "direct_assign"


func _match_bare_member_writes(
		line: String, corpus: Corpus, ownership: Ownership, self_class: String) -> Array[Finding]:
	if self_class.is_empty():
		return []
	if _is_declaration(line.strip_edges()):
		return []
	var element_effect := "(\\[[^\\]\\n]*\\])\\s*(%s)" % ASSIGN_OPS
	var container_effect := "(?:\\[[^\\]\\n]*\\])?\\s*\\.\\s*(%s)\\s*\\(" % "|".join(MUTATOR_METHODS)
	var assign_effect := "(%s)" % ASSIGN_OPS
	var regex := _regex("(?<![\\w.])([A-Za-z_]\\w*)\\s*(?:%s|%s|%s)" % [element_effect, container_effect, assign_effect])
	var out: Array[Finding] = []
	for found in regex.search_all(line):
		var match_start := found.get_start()
		if match_start > 0 and line[match_start - 1] == ".":
			continue
		var field := found.get_string(1)
		var key := "%s.%s" % [self_class, field]
		if not ownership.protected.has(key):
			continue
		var rule := _effect_rule(found.get_string(2), found.get_string(4), found.get_string(5))
		var finding := _finding(key, rule, ownership, line)
		if finding != null:
			out.append(finding)
	return out



## direct_assign / compound_assign / element_assign / container_mutate — all four share one shape,
## `<receiver expression> . <field> <effect>`, so they are matched together and told apart by the
## effect that follows the field.
func _match_field_writes(
		line: String, types: Dictionary, corpus: Corpus, ownership: Ownership) -> Array[Finding]:
	# `<receiver> . <field>` followed by whichever effect identifies the rule. Built from named parts:
	# one long format string mixing `%` and `+` hid a capture-group off-by-one for two revisions.
	var target := "(?<![\\w.])(%s)\\s*\\.\\s*([A-Za-z_]\\w*)\\s*" % CHAIN_EXPR
	var element_effect := "(\\[[^\\]\\n]*\\])\\s*(%s)" % ASSIGN_OPS
	var container_effect := "(?:\\[[^\\]\\n]*\\])?\\s*\\.\\s*(%s)\\s*\\(" % "|".join(MUTATOR_METHODS)
	var assign_effect := "(%s)" % ASSIGN_OPS
	var regex := _regex("%s(?:%s|%s|%s)" % [target, element_effect, container_effect, assign_effect])
	var out: Array[Finding] = []
	for found in regex.search_all(line):
		var receiver := found.get_string(1)
		var field := found.get_string(2)
		var rule := _effect_rule(found.get_string(3), found.get_string(5), found.get_string(6))
		var class_id := _resolve(receiver, types, corpus)
		var finding := _protected_finding(class_id, field, rule, corpus, ownership, line)
		if finding != null:
			out.append(finding)
	return out


## `(thing as Model).field = x` — the cast names the type outright, so no inference is needed.
func _match_cast_writes(line: String, corpus: Corpus, ownership: Ownership) -> Array[Finding]:
	var regex := _regex("\\bas\\s+([A-Za-z_]\\w*)\\s*\\)\\s*\\.\\s*([A-Za-z_]\\w*)\\s*(?:\\[[^\\]\\n]*\\])?\\s*(?:%s)" % ASSIGN_OPS)
	var out: Array[Finding] = []
	for found in regex.search_all(line):
		var finding := _protected_finding(
			found.get_string(1), found.get_string(2), "cast_assign", corpus, ownership, line)
		if finding != null:
			out.append(finding)
	return out


## `recv.set("field", x)` and friends. Flagged on ANY protected model regardless of the key, because
## the key can be computed and a validator that trusted a literal key would be theatre.
func _match_dynamic_sets(
		line: String, types: Dictionary, corpus: Corpus, ownership: Ownership) -> Array[Finding]:
	var regex := _regex(
		"(?<![\\w.])(%s)\\s*\\.\\s*(%s)\\s*\\(\\s*(?:&?\"[^\"\\n]*\"|[A-Za-z_]\\w*)"
		% [CHAIN_EXPR, "|".join(DYNAMIC_SETTERS)])
	var out: Array[Finding] = []
	for found in regex.search_all(line):
		var class_id := _resolve(found.get_string(1), types, corpus)
		if class_id.is_empty():
			continue
		for key in ownership.protected.keys():
			if String(key).get_slice(".", 0) != class_id:
				continue
			# Reported against the CLASS, not a field: the key may be computed, so naming one
			# particular field would be a guess dressed up as a finding. The protected key is still
			# what resolves the aggregate, which is why `display` is a constructor argument rather
			# than something written over the finding afterwards.
			out.append(_finding(String(key), "dynamic_set", ownership, line,
				"%s.<any field, key not statically known>" % class_id))
			break
	return out


## A call to a model method that writes protected fields, from anywhere. `_apply_allowances` lets it
## through for the authority and for declared writers, exactly as a direct write would be.
func _match_mutator_calls(
		line: String, types: Dictionary, corpus: Corpus, ownership: Ownership) -> Array[Finding]:
	var regex := _regex("(?<![\\w.])(%s)\\s*\\.\\s*([A-Za-z_]\\w*)\\s*\\(" % CHAIN_EXPR)
	var out: Array[Finding] = []
	for found in regex.search_all(line):
		var class_id := _resolve(found.get_string(1), types, corpus)
		if class_id.is_empty():
			continue
		var key := "%s.%s" % [class_id, found.get_string(2)]
		if ownership.mutators.has(key):
			out.append(_finding(key, "model_mutator", ownership, line))
	return out


## A write is interesting when its (class, field) pair is protected — or when the receiver's type is
## unknown and the field name is protected SOMEWHERE, which is the false-negative backstop.
func _protected_finding(
		class_id: String, field: String, rule: String,
		corpus: Corpus, ownership: Ownership, line: String) -> Finding:
	# `Variant`/`Object`/`Resource` are annotations that name no class, so they carry exactly as much
	# information as no annotation at all. Treating them as "resolved, and not protected" was a
	# silent bypass: one `func apply(row: Variant)` and the gate went blind.
	if class_id.is_empty() or not corpus.path_of.has(class_id):
		if not ownership.field_names.has(field):
			return null
		return _finding("?.%s" % field, "unresolved_receiver", ownership, line)
	var key := "%s.%s" % [class_id, field]
	if not ownership.protected.has(key):
		return null
	return _finding(key, rule, ownership, line)


## `display` overrides the reported text without changing the key the aggregate is resolved from.
func _finding(
		symbol: String, rule: String, ownership: Ownership, line: String,
		display: String = "") -> Finding:
	var aggregate := ""
	if ownership.protected.has(symbol):
		aggregate = String(ownership.protected[symbol]["aggregate"])
	elif ownership.mutators.has(symbol):
		aggregate = String(ownership.mutators[symbol])
	var shown := display if not display.is_empty() else symbol
	return Finding.new(shown, rule, aggregate, line.strip_edges())


# ── Verdict: which findings are allowed, and which allowances are dead ──────────────────────────

## Judges every finding against the manifest and returns BOTH halves of the answer: which writes are
## not permitted, and which allowances and authorities were exercised getting there. It reads
## Ownership and writes nothing back into it, so a caller may judge the same findings against a
## different baseline. A model may always write its own protected fields — that is where a sanctioned
## mutator method lives.
func _apply_allowances(findings: Array[Finding], ownership: Ownership) -> Verdict:
	var verdict := Verdict.new()
	for finding in findings:
		if not finding.aggregate.is_empty() and ownership.authority_paths.get(finding.path, "") == finding.aggregate:
			verdict.authority_used[finding.path] = true
			continue
		if not finding.aggregate.is_empty() and ownership.owner_paths.get(finding.path, "") == finding.aggregate:
			continue
		if ownership.allowances.has(finding.allowance_key()):
			verdict.allowance_used[finding.allowance_key()] = true
			continue
		verdict.violations.append(finding)
	return verdict


## An authority that writes nothing is not an authority — either the aggregate's writes moved
## somewhere else (a bypass the scan should have caught, so the manifest is lying about which model
## it protects) or the class is a stub the manifest is treating as shipped.
func _report_inert_authorities(manifest: Dictionary, verdict: Verdict) -> void:
	for aggregate_value in manifest.get("aggregates", []):
		var aggregate: Dictionary = aggregate_value
		var authority_path := _text(aggregate.get("authority_path", ""))
		if authority_path.is_empty() or verdict.authority_used.has(authority_path):
			continue
		_fail("E_INERT_AUTHORITY: %s is declared the authority for aggregate '%s' but writes none of its protected fields. Either it is a stub, or the real writes are somewhere this scan is not looking." % [
			authority_path.trim_prefix("res://"), _text(aggregate.get("id", ""))])


func _report_stale_allowances(ownership: Ownership, verdict: Verdict) -> void:
	for key in ownership.allowances.keys():
		if verdict.allowance_used.has(key):
			continue
		var allowance: Dictionary = ownership.allowances[key]
		_fail("E_STALE_ALLOWANCE: %s no longer writes %s (aggregate '%s', %s allowance). Delete the entry — a dead exception is an open door nobody is watching." % [
			String(allowance["path"]).trim_prefix("res://"), String(allowance["symbol"]),
			String(allowance["aggregate"]), String(allowance["kind"])])


func _report_violations(violations: Array[Finding], ownership: Ownership, manifest_path: String) -> void:
	for violation in violations:
		_fail(_diagnostic(violation, ownership, manifest_path))


## Failures teach the rule: what was written, how, where, who is allowed to write it instead, and
## where the ownership fact lives. A method name is only ever suggested when the manifest names an
## authority whose file exists — never invented.
func _diagnostic(violation: Finding, ownership: Ownership, manifest_path: String) -> String:
	var authority := _authority_advice(violation.aggregate, ownership)
	if violation.rule == "unresolved_receiver":
		return "E_UNRESOLVED_WRITE: %s:%d writes '%s' on a receiver whose type cannot be resolved: `%s`. '%s' is a protected field name, so this write cannot be cleared or blamed. Annotate the receiver (`var row: SomeModel = …`) and the gate will judge it. Ownership: %s" % [
			violation.path.trim_prefix("res://"), violation.line,
			violation.symbol.trim_prefix("?."), violation.snippet, violation.symbol.trim_prefix("?."),
			manifest_path.trim_prefix("res://")]
	return "E_UNAUTHORIZED_WRITE: %s:%d mutates protected %s (%s) outside its authority: `%s`. Aggregate '%s'; %s Ownership: %s" % [
		violation.path.trim_prefix("res://"), violation.line, violation.symbol,
		violation.rule, violation.snippet, violation.aggregate, authority,
		manifest_path.trim_prefix("res://")]


func _authority_advice(aggregate: String, ownership: Ownership) -> String:
	for path in ownership.authority_paths.keys():
		if String(ownership.authority_paths[path]) == aggregate:
			return "route the change through %s and have it return a typed receipt." % String(path).trim_prefix("res://")
	return "no authority file exists yet; return the outcome from your calculator and let the aggregate's future authority apply it, or add an explicit legacy-writer entry naming the plan that removes it."


# ── Manifest checks ─────────────────────────────────────────────────────────────────────────────

## Everything that can be wrong with the manifest itself, checked before its claims are trusted.
## Returns false when the manifest is too broken for a scan to mean anything.
func _check_manifest(manifest: Dictionary, corpus: Corpus, strict_paths: bool) -> bool:
	if int(manifest.get("schema_version", 0)) != 1:
		_fail("E_MANIFEST_SCHEMA: schema_version must be 1, found %s." % str(manifest.get("schema_version", null)))
		return false
	var aggregates: Array = manifest.get("aggregates", [])
	if aggregates.is_empty():
		_fail("E_MANIFEST_SCHEMA: no aggregates declared — an empty manifest enforces nothing.")
		return false
	for aggregate_value in aggregates:
		var aggregate: Dictionary = aggregate_value
		_check_authority(aggregate)
		_check_model_section(aggregate, corpus, "owned_models", true)
		_check_model_section(aggregate, corpus, "hosted_fields", false)
		if strict_paths:
			_check_writer_paths(aggregate, corpus)
	_check_shared_model_policies(manifest, corpus)
	return true


func _check_authority(aggregate: Dictionary) -> void:
	var aggregate_id := _text(aggregate.get("id", ""))
	var status := _text(aggregate.get("status", ""))
	var authority_path := _text(aggregate.get("authority_path", ""))
	if status == "enforced":
		if authority_path.is_empty() or not FileAccess.file_exists(authority_path):
			_fail("E_NO_AUTHORITY: aggregate '%s' is 'enforced' but its authority_path '%s' does not exist." % [
				aggregate_id, authority_path])
		return
	if status != "migration":
		_fail("E_MANIFEST_SCHEMA: aggregate '%s' has status '%s'; expected 'migration' or 'enforced'." % [
			aggregate_id, status])
		return
	if _text(aggregate.get("planned_authority", "")).is_empty():
		_fail("E_NO_AUTHORITY: aggregate '%s' is migration-only, so it must name a planned_authority." % aggregate_id)
	if not authority_path.is_empty():
		_fail("E_MANIFEST_SCHEMA: aggregate '%s' is migration-only but declares authority_path '%s'; set status 'enforced' instead." % [
			aggregate_id, authority_path])


## A declared model must exist, declare the class it claims, and — for an OWNED model — classify
## every mutable field it has. The last rule is what stops a new field appearing unprotected.
func _check_model_section(
		aggregate: Dictionary, corpus: Corpus, section: String, exhaustive: bool) -> void:
	var aggregate_id := _text(aggregate.get("id", ""))
	for entry_value in aggregate.get(section, []):
		var entry: Dictionary = entry_value
		var class_id := _text(entry.get("class", ""))
		var path := _text(entry.get("path", ""))
		if not corpus.stripped.has(path):
			_fail("E_DEAD_PATH: aggregate '%s' declares %s '%s', which is not in the scan corpus." % [
				aggregate_id, section, path])
			continue
		if String(corpus.class_of.get(path, "")) != class_id:
			_fail("E_DEAD_PATH: aggregate '%s' says %s declares class '%s', but it declares '%s'." % [
				aggregate_id, path, class_id, String(corpus.class_of.get(path, "<none>"))])
			continue
		var declared: Dictionary = corpus.fields_of.get(class_id, {})
		var claimed: Dictionary = entry.get("fields", {})
		for field_value in claimed.keys():
			if not declared.has(String(field_value)):
				_fail("E_DEAD_FIELD: aggregate '%s' protects %s.%s, which %s no longer declares." % [
					aggregate_id, class_id, String(field_value), path])
		if not exhaustive:
			continue
		for field_value in corpus.order_of.get(class_id, []):
			if not claimed.has(String(field_value)):
				_fail("E_UNCLASSIFIED_FIELD: %s.%s is mutable and unclassified. Owned models classify every field; add it to aggregate '%s' with a lifetime, or move the field to a model this aggregate does not own." % [
					class_id, String(field_value), aggregate_id])


func _check_writer_paths(aggregate: Dictionary, corpus: Corpus) -> void:
	var aggregate_id := _text(aggregate.get("id", ""))
	for section in ["construction_writers", "legacy_writers"]:
		for entry_value in aggregate.get(section, []):
			var entry: Dictionary = entry_value
			var path := _text(entry.get("path", ""))
			if not corpus.stripped.has(path):
				_fail("E_DEAD_PATH: aggregate '%s' lists %s '%s', which is not in the scan corpus." % [
					aggregate_id, section, path])
			if section == "legacy_writers" and _text(entry.get("removal_plan", "")).is_empty():
				_fail("E_MANIFEST_SCHEMA: legacy writer '%s' (aggregate '%s') has no removal_plan. A legacy writer without an exit is just a permitted writer." % [
					path, aggregate_id])


# ── Shared-model closure: a hosted class classifies every field it declares ─────────────────────

## `hosted_fields` claims only the fields one aggregate owns on a SHARED model, so on its own it is
## open-world: a field added to GameStateData is unprotected and nothing says so. This closes it —
## every mutable field of every hosted class is claimed by exactly one aggregate, or excluded here
## with a classification and a concrete reason. Exclusions are NOT a second ownership list: claimed
## fields are read out of the aggregates, and naming one here is an error rather than a duplicate.
func _check_shared_model_policies(manifest: Dictionary, corpus: Corpus) -> void:
	var hosted := _hosted_classes(manifest)
	if hosted.is_empty():
		_fail("E_VACUOUS: no class appears under hosted_fields, so the shared-model closure check would enforce nothing.")
		return
	var claimed := _claimed_fields_by_class(manifest)
	var policies := _policies_by_class(manifest, hosted)
	for class_id_value in hosted.keys():
		var class_id := String(class_id_value)
		# A class whose path is dead has no declared fields to close over, and _check_model_section
		# has already said so. Reporting it twice would bury the fixable error.
		if not corpus.order_of.has(class_id):
			continue
		_check_class_closure(
			class_id, corpus,
			Dictionary(claimed.get(class_id, {})), Dictionary(policies.get(class_id, {})))


## class_name -> the path its host declares, for every class any aggregate registers under
## `hosted_fields`. That is exactly the set of models shared between aggregates, and therefore the
## set whose leftover fields nobody has spoken for.
func _hosted_classes(manifest: Dictionary) -> Dictionary:
	var hosted: Dictionary = {}
	for aggregate_value in manifest.get("aggregates", []):
		for entry_value in Dictionary(aggregate_value).get("hosted_fields", []):
			var entry: Dictionary = entry_value
			hosted[_text(entry.get("class", ""))] = _text(entry.get("path", ""))
	return hosted


## class_name -> {field: true} across BOTH claim sections, so "claimed and excluded at once" is
## judged against every claim in the manifest rather than only the hosted half of it.
func _claimed_fields_by_class(manifest: Dictionary) -> Dictionary:
	var claimed: Dictionary = {}
	for aggregate_value in manifest.get("aggregates", []):
		for section in ["owned_models", "hosted_fields"]:
			for entry_value in Dictionary(aggregate_value).get(section, []):
				var entry: Dictionary = entry_value
				var class_id := _text(entry.get("class", ""))
				if not claimed.has(class_id):
					claimed[class_id] = {}
				for field_value in Dictionary(entry.get("fields", {})).keys():
					claimed[class_id][String(field_value)] = true
	return claimed


## The policy section reduced to class_name -> non_authority_fields, with every exclusion judged on
## its own terms along the way. Whether a field is REAL and unclaimed is a separate question, asked
## afterwards against the corpus.
func _policies_by_class(manifest: Dictionary, hosted: Dictionary) -> Dictionary:
	var plan_dir := _text(manifest.get("plan_dir", ""))
	var policies: Dictionary = {}
	for policy_value in manifest.get("shared_model_policies", []):
		var policy: Dictionary = policy_value
		var class_id := _policy_target(policy, hosted, policies)
		if class_id.is_empty():
			continue
		var fields := Dictionary(policy.get("non_authority_fields", {}))
		for field_value in fields.keys():
			_check_exclusion(
				"%s.%s" % [class_id, String(field_value)],
				Dictionary(fields[field_value]), plan_dir)
		policies[class_id] = fields
	return policies


## The class one policy entry attaches to, or "" when the entry is unusable. A path that disagrees
## with the host is reported but does NOT reject the entry: dropping it would bury one fixable error
## under an E_UNCLASSIFIED_HOSTED_FIELD per field the entry did classify.
func _policy_target(policy: Dictionary, hosted: Dictionary, seen: Dictionary) -> String:
	var class_id := _text(policy.get("class", ""))
	if seen.has(class_id):
		_fail("E_DUPLICATE_SHARED_POLICY: '%s' has two shared-model policy entries. One class, one policy — a second entry splits the exclusion list into two homes that drift apart." % class_id)
		return ""
	if not hosted.has(class_id):
		_fail("E_SHARED_POLICY_CLASS: shared-model policy names '%s', which no aggregate registers under hosted_fields. This section classifies leftover fields on SHARED models only; an owned model classifies every field in its own 'fields' map." % class_id)
		return ""
	var path := _text(policy.get("path", ""))
	if path != String(hosted[class_id]):
		_fail("E_SHARED_POLICY_CLASS: shared-model policy for '%s' declares path '%s', but the aggregate hosting it declares '%s'." % [
			class_id, path, String(hosted[class_id])])
	return class_id


## One hosted class, closed over: every declared field is claimed or excluded, never both, and no
## exclusion outlives the field it names.
func _check_class_closure(
		class_id: String, corpus: Corpus, claimed: Dictionary, excluded: Dictionary) -> void:
	for field_value in corpus.order_of.get(class_id, []):
		var declared_field := String(field_value)
		if claimed.has(declared_field) or excluded.has(declared_field):
			continue
		_fail("E_UNCLASSIFIED_HOSTED_FIELD: %s.%s is mutable and nobody has spoken for it. Claim it in the hosted_fields of the aggregate that owns it, or classify it under shared_model_policies with a reason." % [
			class_id, declared_field])
	var declared: Dictionary = corpus.fields_of.get(class_id, {})
	for field_value in excluded.keys():
		var field := String(field_value)
		if claimed.has(field):
			_fail("E_CLAIMED_AND_EXCLUDED: %s.%s is claimed by an aggregate AND excluded by shared_model_policies. A field is protected or it is not; the exclusion would read as permission to write a protected field." % [
				class_id, field])
		elif not declared.has(field):
			_fail("E_DEAD_EXCLUSION: shared_model_policies excludes %s.%s, which %s no longer declares. Delete the entry — a stale exclusion silently pre-clears the next field to take that name." % [
				class_id, field, class_id])


## One exclusion on its own terms: a classification from the closed vocabulary, a concrete reason,
## and — for a classification that is a PROMISE — the plan that deletes the entry.
##
## The pointer must live under the manifest's `plan_dir` and still resolve. Both halves are load-bearing:
## without the directory rule any existing file satisfies the check, and without the existence rule a
## plan that ships and is archived leaves its exclusion looking permanent. `plan_dir` is configured
## rather than hardcoded so the abstract fixture world can prove the rule without its expectations
## moving every time a REAL plan is archived.
func _check_exclusion(symbol: String, entry: Dictionary, plan_dir: String) -> void:
	var classification := _text(entry.get("classification", ""))
	if not POLICY_CLASSIFICATIONS.has(classification):
		_fail("E_SHARED_POLICY_SCHEMA: %s is excluded as '%s'; expected one of %s." % [
			symbol, classification, str(POLICY_CLASSIFICATIONS.keys())])
		return
	if _text(entry.get("why", "")).strip_edges().is_empty():
		_fail("E_SHARED_POLICY_SCHEMA: %s is excluded with no 'why'. An unexplained exclusion is an unprotected field with paperwork." % symbol)
		return
	var plan := _text(entry.get("plan", ""))
	if plan.is_empty():
		if bool(POLICY_CLASSIFICATIONS[classification]):
			_fail("E_SHARED_POLICY_SCHEMA: %s is excluded as '%s', which is a promise, so it must name the plan that takes ownership of the field." % [
				symbol, classification])
		return
	# Normalised before the containment test: `res://docs/plans/../archive/x.md` passes a raw prefix
	# check while pointing outside plan_dir entirely, which would let an ARCHIVED plan keep an
	# exclusion alive — the exact failure this rule exists to prevent.
	plan = plan.simplify_path()
	if plan_dir.is_empty() or not plan.begins_with("%s/" % plan_dir.simplify_path()):
		_fail("E_SHARED_POLICY_SCHEMA: %s points at '%s', which is not under the manifest's plan_dir '%s'. Only a live plan can expire, so a pointer anywhere else can never go stale." % [
			symbol, plan, plan_dir])
		return
	if not FileAccess.file_exists(plan):
		_fail("E_STALE_POLICY_PLAN: %s points at '%s', which no longer exists — a shipped plan is archived out of plan_dir. The exclusion has outlived its reason: claim the field now, or reclassify it." % [
			symbol, plan])


## scripts/transitions/ is the authority directory. A file living there that no aggregate names is
## rejected outright, so the directory cannot quietly become a second grab bag of writers: authority
## is granted to an exact named file, never to everything sharing its folder.
func _check_authority_dir(manifest: Dictionary, ownership: Ownership, extension: String) -> void:
	var dir_path := _text(manifest.get("authority_dir", ""))
	if dir_path.is_empty() or not DirAccess.dir_exists_absolute(dir_path):
		return
	for path in _files_with_extension(dir_path, extension):
		if not ownership.authority_paths.has(path):
			_fail("E_UNREGISTERED_AUTHORITY_FILE: %s lives in the authority directory but no aggregate in the manifest names it as its authority_path. Authority is granted to an exact named file, never to a directory." % path.trim_prefix("res://"))


# ── Runs ────────────────────────────────────────────────────────────────────────────────────────

## Sorted, reviewable claim identity. Including aggregate and section makes a silent deletion,
## reassignment, or owned -> hosted demotion differ from the committed regression pin.
func _manifest_claim_keys(manifest: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for aggregate_value in manifest.get("aggregates", []):
		var aggregate: Dictionary = aggregate_value
		var aggregate_id := _text(aggregate.get("id", ""))
		for section in ["owned_models", "hosted_fields"]:
			for entry_value in aggregate.get(section, []):
				var entry: Dictionary = entry_value
				var class_id := _text(entry.get("class", ""))
				for field_value in Dictionary(entry.get("fields", {})).keys():
					keys.append("%s|%s|%s.%s" % [
						aggregate_id, section, class_id, String(field_value)])
	keys.sort()
	return keys


func _pinned_claim_set(pin: Dictionary) -> Dictionary:
	if pin.is_empty() or not (pin.get("claims", null) is Array):
		_fail("E_REAL_CLAIM_PIN: %s is missing, unparseable, or has no claims array." %
			REAL_CLAIMS_PIN_PATH.trim_prefix("res://"))
		return {}
	var pinned: Dictionary = {}
	var ordered: Array[String] = []
	for claim_value in pin.get("claims", []):
		var claim := String(claim_value)
		if pinned.has(claim):
			_fail("E_REAL_CLAIM_PIN: duplicate pinned claim '%s'." % claim)
		pinned[claim] = true
		ordered.append(claim)
	if ordered.is_empty():
		_fail("E_REAL_CLAIM_PIN: claims array is empty, so it protects nothing.")
		return {}
	var sorted: Array[String] = ordered.duplicate()
	sorted.sort()
	if ordered != sorted:
		_fail("E_REAL_CLAIM_PIN: claims must stay sorted so ownership changes remain reviewable.")
	return pinned


## The pin is deliberately NOT read by _build_ownership: it is an independent expected-output
## artifact. A manifest edit must update it visibly, just as a serialized fixture update does.
func _check_real_claim_pin(manifest: Dictionary, pin: Dictionary) -> void:
	var pinned := _pinned_claim_set(pin)
	if pinned.is_empty():
		return
	var actual: Dictionary = {}
	for claim in _manifest_claim_keys(manifest):
		actual[claim] = true
	for claim in pinned.keys():
		if not actual.has(claim):
			_fail("E_REAL_CLAIM_PIN: pinned claim '%s' is absent from the real manifest." % claim)
	for claim in actual.keys():
		if not pinned.has(claim):
			_fail("E_REAL_CLAIM_PIN: real manifest claim '%s' has no reviewed pin." % claim)


## Proves both comparison directions without maintaining broken copies of the production manifest.
func _check_real_claim_pin_self_test(manifest: Dictionary) -> void:
	var claims := _manifest_claim_keys(manifest)
	if claims.is_empty():
		_fail("SELF-TEST: the real claim-pin check has no claims to perturb.")
		return
	var missing_pin: Array[String] = claims.duplicate()
	missing_pin.remove_at(0)
	var missing_errors := _capture_failures(func() -> void:
		_check_real_claim_pin(manifest, {"claims": missing_pin}))
	_expect_single_error(missing_errors, "E_REAL_CLAIM_PIN", "real claim pin missing-entry direction")
	var extra_pin: Array[String] = claims.duplicate()
	extra_pin.append("fixture_ghost|owned_models|FixtureGhost.missing_field")
	extra_pin.sort()
	var extra_errors := _capture_failures(func() -> void:
		_check_real_claim_pin(manifest, {"claims": extra_pin}))
	_expect_single_error(extra_errors, "E_REAL_CLAIM_PIN", "real claim pin extra-entry direction")
	var duplicate_pin: Array[String] = claims.duplicate()
	duplicate_pin.insert(1, duplicate_pin[0])
	var duplicate_errors := _capture_failures(func() -> void:
		_check_real_claim_pin(manifest, {"claims": duplicate_pin}))
	_expect_single_error(duplicate_errors, "E_REAL_CLAIM_PIN", "real claim pin duplicate direction")
	if claims.size() > 1:
		var unsorted_pin: Array[String] = claims.duplicate()
		var first := unsorted_pin[0]
		unsorted_pin[0] = unsorted_pin[1]
		unsorted_pin[1] = first
		var sort_errors := _capture_failures(func() -> void:
			_check_real_claim_pin(manifest, {"claims": unsorted_pin}))
		_expect_single_error(sort_errors, "E_REAL_CLAIM_PIN", "real claim pin sorted-order direction")


func _probe_expectation(claim: String, rule: String = "direct_assign") -> Dictionary:
	var parts := claim.split("|")
	return {
		"aggregate": String(parts[0]),
		"rule": rule,
		"symbol": String(parts[2]),
	}


## One valid, type-directed assignment per real claim. The probe is generated from the manifest so
## it scales automatically; the independent pin above is what prevents oracle circularity.
func _direct_real_probe_source(claims: Array[String], expected: Dictionary) -> String:
	var lines: Array[String] = ["extends RefCounted", ""]
	for index in range(claims.size()):
		var claim := claims[index]
		var symbol := claim.get_slice("|", 2)
		var class_id := symbol.get_slice(".", 0)
		var field := symbol.get_slice(".", 1)
		lines.append("static func probe_%03d(target: %s) -> void:" % [index, class_id])
		lines.append("\ttarget.%s = target.%s" % [field, field])
		expected["%s:%d" % [GENERATED_REAL_PROBE_PATH, lines.size()]] = _probe_expectation(claim)
		lines.append("")
	return "\n".join(lines) + "\n"


## Every real authority path writes one representative field from EVERY OTHER aggregate. This full
## ordered matrix catches accidental pair-specific grants without editing a production file.
func _wrong_authority_probe_sources(
		manifest: Dictionary, claims: Array[String], expected: Dictionary) -> Dictionary:
	var authority_by_aggregate: Dictionary = {}
	var first_claim_by_aggregate: Dictionary = {}
	for aggregate_value in manifest.get("aggregates", []):
		var aggregate: Dictionary = aggregate_value
		var aggregate_id := _text(aggregate.get("id", ""))
		authority_by_aggregate[aggregate_id] = _text(aggregate.get("authority_path", ""))
	for claim in claims:
		var aggregate_id := claim.get_slice("|", 0)
		if not first_claim_by_aggregate.has(aggregate_id):
			first_claim_by_aggregate[aggregate_id] = claim
	var aggregate_ids: Array = authority_by_aggregate.keys()
	aggregate_ids.sort()
	var sources: Dictionary = {}
	if aggregate_ids.size() < 2:
		_fail("E_VACUOUS: real wrong-authority probes need at least two aggregates.")
		return sources
	for wrong_id_value in aggregate_ids:
		var wrong_id := String(wrong_id_value)
		var path := String(authority_by_aggregate[wrong_id])
		var lines: Array[String] = ["extends RefCounted", ""]
		for target_id_value in aggregate_ids:
			var target_id := String(target_id_value)
			if target_id == wrong_id:
				continue
			var claim := String(first_claim_by_aggregate.get(target_id, ""))
			var symbol := claim.get_slice("|", 2)
			var class_id := symbol.get_slice(".", 0)
			var field := symbol.get_slice(".", 1)
			lines.append("static func probe_%s(target: %s) -> void:" % [target_id, class_id])
			lines.append("\ttarget.%s = target.%s" % [field, field])
			expected["%s:%d" % [path, lines.size()]] = _probe_expectation(claim)
			lines.append("")
		sources[path] = "\n".join(lines) + "\n"
	return sources


## A tiny source-only corpus that borrows the real corpus's class/type tables. Probe text is never
## written into production files and never compiled, matching the existing .gdfixture contract.
func _expected_wrong_authority_pairs(manifest: Dictionary) -> Dictionary:
	var aggregate_ids: Array[String] = []
	for aggregate_value in manifest.get("aggregates", []):
		aggregate_ids.append(_text(Dictionary(aggregate_value).get("id", "")))
	var expected: Dictionary = {}
	for writer_id in aggregate_ids:
		for target_id in aggregate_ids:
			if writer_id != target_id:
				expected["%s|%s" % [writer_id, target_id]] = true
	return expected


## Pair identity is derived independently from probe generation. Cardinality alone would let a
## broken generator repeat one foreign target while silently omitting another.
func _check_wrong_authority_pairs(
		manifest: Dictionary, ownership: Ownership, violations: Array[Finding]) -> void:
	var actual: Dictionary = {}
	for violation in violations:
		var writer_id := String(ownership.authority_paths.get(violation.path, ""))
		if writer_id.is_empty():
			continue
		var pair := "%s|%s" % [writer_id, violation.aggregate]
		if actual.has(pair):
			_fail("REAL-CONTRACT DUPLICATE BOUNDARY: wrong-authority pair '%s' was probed twice." % pair)
		actual[pair] = true
	var expected := _expected_wrong_authority_pairs(manifest)
	for pair in expected.keys():
		if not actual.has(pair):
			_fail("REAL-CONTRACT MISSING BOUNDARY: wrong-authority pair '%s' was not probed." % pair)
	for pair in actual.keys():
		if not expected.has(pair):
			_fail("REAL-CONTRACT EXTRA BOUNDARY: unexpected wrong-authority pair '%s'." % pair)


func _build_probe_corpus(reference: Corpus, sources: Dictionary) -> Corpus:
	var corpus := Corpus.new()
	corpus.path_of = reference.path_of.duplicate()
	corpus.fields_of = reference.fields_of.duplicate(true)
	corpus.order_of = reference.order_of.duplicate(true)
	for path_value in sources.keys():
		var path := String(path_value)
		var text := String(sources[path_value])
		corpus.raw[path] = text
		corpus.stripped[path] = _strip(text)
		corpus.returns_of[path] = _declared_returns(String(corpus.stripped[path]))
		var class_id := _class_name_of(String(corpus.stripped[path]))
		if class_id.is_empty():
			continue
		corpus.class_of[path] = class_id
		corpus.path_of[class_id] = path
		var declared := _declared_fields(String(corpus.stripped[path]))
		corpus.fields_of[class_id] = declared["types"]
		corpus.order_of[class_id] = declared["order"]
	return corpus


func _record_real_contract_finding(actual: Dictionary, violation: Finding) -> void:
	var location := "%s:%d" % [violation.path, violation.line]
	if actual.has(location):
		_fail("REAL-CONTRACT DUPLICATE FINDING: %s produced more than one finding." %
			location.trim_prefix("res://"))
		return
	actual[location] = {
		"aggregate": violation.aggregate,
		"rule": violation.rule,
		"symbol": violation.symbol,
	}


func _check_real_contract_duplicate_self_test() -> void:
	var finding := Finding.new("FixtureRow.quantity_units", "direct_assign", "fixture_aggregate", "")
	finding.path = GENERATED_REAL_PROBE_PATH
	finding.line = 1
	var actual: Dictionary = {}
	_record_real_contract_finding(actual, finding)
	var duplicate_errors := _capture_failures(func() -> void:
		_record_real_contract_finding(actual, finding))
	_expect_single_error(
		duplicate_errors, "REAL-CONTRACT DUPLICATE FINDING", "real-contract duplicate finding")


func _compare_real_contract_probes(expected: Dictionary, actual: Dictionary) -> void:
	if expected.is_empty():
		_fail("REAL-CONTRACT FALSE NEGATIVE: no generated expectations; the pass proves nothing.")
	for location in expected.keys():
		if not actual.has(location):
			_fail("REAL-CONTRACT FALSE NEGATIVE: %s expected %s and the scanner found nothing." % [
				String(location).trim_prefix("res://"), str(expected[location])])
		elif actual[location] != expected[location]:
			_fail("REAL-CONTRACT WRONG FINDING: %s expected %s, got %s." % [
				String(location).trim_prefix("res://"), str(expected[location]), str(actual[location])])
	for location in actual.keys():
		if not expected.has(location):
			_fail("REAL-CONTRACT FALSE POSITIVE: %s produced unexpected %s." % [
				String(location).trim_prefix("res://"), str(actual[location])])


func _run_real_contract_probes(
		manifest: Dictionary, real_corpus: Corpus, ownership: Ownership) -> void:
	var claims := _manifest_claim_keys(manifest)
	var expected: Dictionary = {}
	var sources: Dictionary = {
		GENERATED_REAL_PROBE_PATH: _direct_real_probe_source(claims, expected),
	}
	var wrong_authority_sources := _wrong_authority_probe_sources(manifest, claims, expected)
	for path in wrong_authority_sources.keys():
		sources[path] = wrong_authority_sources[path]
	var aggregate_count := Array(manifest.get("aggregates", [])).size()
	var boundary_count := aggregate_count * (aggregate_count - 1)
	if wrong_authority_sources.size() != aggregate_count or expected.size() != claims.size() + boundary_count:
		_fail("E_VACUOUS: real-contract probes generated %d source(s) / %d expectation(s); expected %d authority source(s) / %d total expectation(s)." % [
			wrong_authority_sources.size(), expected.size(), aggregate_count, claims.size() + boundary_count])
		return
	var probe_corpus := _build_probe_corpus(real_corpus, sources)
	var verdict := _apply_allowances(_scan(probe_corpus, ownership), ownership)
	_check_wrong_authority_pairs(manifest, ownership, verdict.violations)
	var actual: Dictionary = {}
	for violation in verdict.violations:
		_record_real_contract_finding(actual, violation)
	_compare_real_contract_probes(expected, actual)
	_real_contract_ran = true
	print("Real-contract probes: %d manifest claim(s) and %d wrong-authority boundary(s) reproduced." % [
		claims.size(), boundary_count])


func _run_real_scan() -> void:
	var manifest := _read_json(MANIFEST_PATH)
	if manifest.is_empty():
		_fail("E_MANIFEST_SCHEMA: %s is missing or unparseable." % MANIFEST_PATH)
		return
	var claim_pin := _read_json(REAL_CLAIMS_PIN_PATH)
	var paths: Array[String] = []
	var excludes: Array = manifest.get("scan_excludes", [])
	for root_value in manifest.get("scan_roots", []):
		for path in _gd_files(String(root_value)):
			if not _excluded(path, excludes):
				paths.append(path)
	var corpus := _build_corpus(paths)
	if not _check_manifest(manifest, corpus, true):
		return
	_check_real_claim_pin(manifest, claim_pin)
	_check_real_claim_pin_self_test(manifest)
	var ownership := _build_ownership(manifest, corpus)
	_check_authority_dir(manifest, ownership, ".gd")
	var findings := _scan(corpus, ownership)
	_guard_vacuous(paths.size(), corpus, ownership, findings.size())
	var verdict := _apply_allowances(findings, ownership)
	_report_violations(verdict.violations, ownership, MANIFEST_PATH)
	_report_stale_allowances(ownership, verdict)
	_report_inert_authorities(manifest, verdict)
	_run_real_contract_probes(manifest, corpus, ownership)
	_print_campaign_progress(manifest, paths.size(), ownership)


## A validator that silently scanned nothing looks exactly like one that verified everything — the
## DataOverrides silent-failure family. Every count that could collapse to zero is asserted.
func _guard_vacuous(
		file_count: int, corpus: Corpus, ownership: Ownership, finding_count: int) -> void:
	if file_count < 50:
		_fail("E_VACUOUS: scanned only %d file(s); the scan roots resolved to nothing usable." % file_count)
	if corpus.path_of.is_empty():
		_fail("E_VACUOUS: no class_name declarations found — receiver resolution would silently see nothing.")
	if ownership.protected.is_empty():
		_fail("E_VACUOUS: the manifest protects zero symbols.")
	if finding_count == 0:
		_fail("E_VACUOUS: zero protected writes found across the whole tree. Every registered aggregate has at least a construction writer, so this means the scanner matched nothing.")


func _print_campaign_progress(manifest: Dictionary, file_count: int, ownership: Ownership) -> void:
	print("Scanned %d source file(s); %d protected symbol(s) across %d aggregate(s)." % [
		file_count, ownership.protected.size(), Array(manifest.get("aggregates", [])).size()])
	var remaining := 0
	for aggregate_value in manifest.get("aggregates", []):
		var aggregate: Dictionary = aggregate_value
		var authority := _text(aggregate.get("planned_authority", null))
		if authority.is_empty():
			authority = _text(aggregate.get("authority_class", null))
		print("  aggregate '%s' [%s] -> %s" % [
			_text(aggregate.get("id", "")), _text(aggregate.get("status", "")), authority])
		for entry_value in aggregate.get("legacy_writers", []):
			var entry: Dictionary = entry_value
			remaining += 1
			print("      legacy writer %s (%d field(s)) — removed by: %s" % [
				_text(entry.get("path", "")).trim_prefix("res://"),
				Array(entry.get("fields", [])).size(), _text(entry.get("removal_plan", ""))])
	print("Legacy writers still outstanding: %d." % remaining)


## The self-test is the proof that the claims in this file's header are true. Every deliberately
## illegal fixture declares the rule it expects on the offending line; the scan's output must match
## that expectation EXACTLY — a missing hit is a false negative, an extra hit a false positive.
func _run_self_test() -> void:
	var manifest := _read_json("%s/fixture_manifest.json" % FIXTURE_DIR)
	var paths := _fixture_files()
	if manifest.is_empty() or paths.is_empty():
		_fail("E_VACUOUS: self-test fixtures missing under %s — the detector's claims are unproven." % FIXTURE_DIR)
		return
	var corpus := _build_corpus(paths)
	if not _check_manifest(manifest, corpus, true):
		return
	var ownership := _build_ownership(manifest, corpus)
	var verdict := _apply_allowances(_scan(corpus, ownership), ownership)
	var actual: Dictionary = {}
	for violation in verdict.violations:
		actual["%s:%d" % [violation.path, violation.line]] = violation.rule
	var expected := _fixture_expectations(corpus)
	_compare_self_test(expected, actual)
	_check_manifest_error_fixtures(corpus)
	_check_authority_dir_fixture(manifest, ownership)
	_check_inert_authority_fixture(manifest, verdict)
	_check_stale_allowance_fixture(ownership, verdict)
	_check_real_contract_duplicate_self_test()
	_check_promise_classification_self_test()
	_check_empty_hosted_self_test(corpus)
	print("Self-test: %d fixture file(s), %d expected violation(s) reproduced." % [paths.size(), expected.size()])


## Proves the table is CONSISTENTLY IMPLEMENTED: every classification it marks a promise really does
## demand a plan, and every one it does not really demands nothing. So a promise added later cannot
## arrive unproven.
##
## What it deliberately CANNOT prove is the table's CONTENT, because it reads the same table it
## checks — measured: flipping `order_buffer` back to `false` left this self-test green. That decision
## is pinned from outside instead, by the bad-manifest fixture that omits an `order_buffer` plan and
## declares the error it must provoke. Same reason `real_claims_pin.json` exists.
func _check_promise_classification_self_test() -> void:
	for classification_value in POLICY_CLASSIFICATIONS.keys():
		var classification := String(classification_value)
		var produced := _capture_failures(func() -> void:
			_check_exclusion(
				"SelfTest.field",
				{"classification": classification, "why": "self-test"},
				"res://docs/plans"))
		if bool(POLICY_CLASSIFICATIONS[classification_value]):
			_expect_single_error(produced, "E_SHARED_POLICY_SCHEMA",
				"promise classification '%s' with no plan" % classification)
		elif not produced.is_empty():
			_fail("SELF-TEST: classification '%s' is not marked a promise, yet demanded something anyway: %s." % [
				classification, str(produced)])


## A manifest whose aggregates host nothing would make the whole closure check inert while still
## printing PASS. The healthy fixture world always hosts a class, so the failing direction is only
## reachable by re-judging a stripped manifest.
func _check_empty_hosted_self_test(corpus: Corpus) -> void:
	var produced := _capture_failures(func() -> void:
		_check_shared_model_policies({"aggregates": [{"id": "no_hosts"}]}, corpus))
	_expect_single_error(produced, "E_VACUOUS", "empty hosted-class set")


## Proves the authority-directory rule against a fixture folder, because scripts/transitions/ does
## not exist yet — an unproven rule is a rule nobody has run.
func _check_authority_dir_fixture(manifest: Dictionary, ownership: Ownership) -> void:
	var produced := _capture_failures(func() -> void:
		_check_authority_dir(manifest, ownership, FIXTURE_EXT))
	_expect_single_error(produced, "E_UNREGISTERED_AUTHORITY_FILE", "authority-directory fixture")


## The fixture authority DOES write, so the live check passes there. Re-judging the same manifest
## against an EMPTY usage record is how the failing direction gets exercised without a second fixture
## tree — and it is only expressible because the usage record is a separate Verdict rather than a side
## effect written back into Ownership.
func _check_inert_authority_fixture(manifest: Dictionary, verdict: Verdict) -> void:
	var first_auth := _text(Dictionary(manifest["aggregates"][0]).get("authority_path", ""))
	if not verdict.authority_used.has(first_auth):
		_fail("SELF-TEST: the fixture authority wrote nothing, so the inert-authority check is being proven against the wrong baseline.")
		return
	var test_verdict := Verdict.new()
	test_verdict.authority_used = verdict.authority_used.duplicate()
	test_verdict.authority_used.erase(first_auth)
	var produced := _capture_failures(func() -> void:
		_report_inert_authorities(manifest, test_verdict))
	_expect_single_error(produced, "E_INERT_AUTHORITY", "inert-authority fixture")


## The fixture manifest carries a fabricated legacy allowance that writes nothing in the fixture
## corpus. Re-judging the manifest against the normal usage record (where the allowance is absent)
## proves the stale-allowance check fires.
func _check_stale_allowance_fixture(ownership: Ownership, verdict: Verdict) -> void:
	var produced := _capture_failures(func() -> void:
		_report_stale_allowances(ownership, verdict))
	_expect_single_error(produced, "E_STALE_ALLOWANCE", "stale allowance fixture")


func _compare_self_test(expected: Dictionary, actual: Dictionary) -> void:
	if expected.is_empty():
		_fail("SELF-TEST: no `#@expect` markers parsed out of the fixtures. The self-test would then agree with any scanner, including one that detects nothing.")
	for key in expected.keys():
		if not actual.has(key):
			_fail("SELF-TEST FALSE NEGATIVE: %s expects rule '%s' and the scanner found nothing. The header claims this write form is detected; either fix the detector or stop claiming it." % [
				String(key).trim_prefix("res://"), String(expected[key])])
		elif String(actual[key]) != String(expected[key]):
			_fail("SELF-TEST WRONG RULE: %s expected '%s', got '%s'." % [
				String(key).trim_prefix("res://"), String(expected[key]), String(actual[key])])
	for key in actual.keys():
		if not expected.has(key):
			_fail("SELF-TEST FALSE POSITIVE: %s was flagged '%s' but the fixture declares it legal." % [
				String(key).trim_prefix("res://"), String(actual[key])])


## `#@expect <rule>` trailing a fixture line declares the violation that line must produce. Read
## from the RAW text, because the scanner itself works on a comment-stripped copy.
func _fixture_expectations(corpus: Corpus) -> Dictionary:
	var regex := _regex("#@expect\\s+([a-z_]+)")
	var expected: Dictionary = {}
	for path_value in corpus.raw.keys():
		var lines := String(corpus.raw[path_value]).split("\n")
		for index in range(lines.size()):
			var found := regex.search(String(lines[index]))
			if found != null:
				var start := _statement_start(lines, index)
				expected["%s:%d" % [String(path_value), start + 1]] = found.get_string(1)
	return expected


## The first physical line of the statement containing `index`. An expectation belongs to its
## statement, and a `\`-continued statement is reported at the line it starts on — so a marker
## written on the continuation still names the right violation.
func _statement_start(lines: PackedStringArray, index: int) -> int:
	var start := index
	while start > 0 and String(lines[start - 1]).strip_edges().ends_with("\\"):
		start -= 1
	return start


## Broken-manifest fixtures: each declares the single error code it must provoke. They exercise the
## manifest checks the source fixtures cannot reach — dead paths, dead fields, an unclassified field,
## two aggregates claiming one field, a missing authority, and every way a shared-model policy can be
## wrong.
func _check_manifest_error_fixtures(corpus: Corpus) -> void:
	var fixtures := _files_matching(FIXTURE_DIR, "bad_manifest_", ".json")
	if fixtures.size() < 23:
		_fail("SELF-TEST: found %d broken-manifest fixture(s), expected at least 23 — the manifest checks would go unproven." % fixtures.size())
	for path in fixtures:
		var manifest := _read_json(path)
		var produced := _capture_failures(func() -> void:
			_check_manifest(manifest, corpus, true)
			_build_ownership(manifest, corpus))
		_expect_single_error(
			produced, _text(manifest.get("_expect_error", "")), path.trim_prefix("res://"))


## Runs a check with the failure list quarantined, and returns what that check alone produced.
func _capture_failures(body: Callable) -> Array[String]:
	var quarantined: Array[String] = _h.failures
	_h.failures = []
	body.call()
	var produced: Array[String] = _h.failures.duplicate()
	_h.failures = quarantined
	return produced


func _expect_single_error(produced: Array[String], expected: String, label: String) -> void:
	if expected.is_empty():
		_fail("SELF-TEST: %s declares no _expect_error, so it proves nothing." % label)
		return
	for message in produced:
		if message.begins_with(expected):
			if produced.size() != 1:
				_fail("SELF-TEST: %s expected exactly one error, produced %d: %s." % [
					label, produced.size(), str(produced)])
			return
	_fail("SELF-TEST: %s expected error '%s'; the checks produced %s." % [
		label, expected, str(produced)])


# ── Small helpers ───────────────────────────────────────────────────────────────────────────────

func _fixture_files() -> Array[String]:
	return _files_with_extension(FIXTURE_DIR, FIXTURE_EXT)


func _files_matching(dir_path: String, prefix: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with(prefix) and entry.ends_with(suffix):
			out.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _gd_files(root: String) -> Array[String]:
	return _files_with_extension(root, ".gd")


func _files_with_extension(root: String, extension: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := "%s/%s" % [root, entry]
			if dir.current_is_dir():
				out.append_array(_files_with_extension(full, extension))
			elif entry.ends_with(extension):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _excluded(path: String, excludes: Array) -> bool:
	for prefix in excludes:
		if path.begins_with(String(prefix)):
			return true
	return false


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## JSON null is a legitimate manifest value ("no authority file yet"), and `String(null)` is a hard
## error in GDScript — so every manifest read goes through here.
func _text(value: Variant) -> String:
	return "" if value == null else str(value)


func _class_name_of(body: String) -> String:
	var regex := _regex("(?m)^class_name\\s+([A-Za-z_]\\w*)")
	var found := regex.search(body)
	return found.get_string(1) if found != null else ""


## Comments and string literals are prose, not code — this header discusses `system.quantity = 0` at
## length. Newlines survive so reported line numbers stay true.
func _strip(body: String) -> String:
	var without_strings := _regex("\"[^\"\\n]*\"|'[^'\\n]*'")
	var stripped := without_strings.sub(body, "\"\"", true)
	var without_comments := _regex("(?m)#.*$")
	return without_comments.sub(stripped, "", true)


func _fail(message: String) -> void:
	_h.failures.append(message)


func _finish() -> void:
	if not _real_contract_ran:
		_fail("E_VACUOUS: generated real-contract pass did not complete.")
	if _h.failures.is_empty():
		print("PASS: mutation authority — no unauthorised writes to any registered aggregate.")
		quit(0)
		return
	for failure in _h.failures:
		push_error(failure)
	print("FAIL: mutation-authority validation found %d issue(s):" % _h.failures.size())
	for failure in _h.failures:
		print("  - %s" % failure)
	quit(1)
