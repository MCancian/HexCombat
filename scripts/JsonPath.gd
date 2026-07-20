class_name JsonPath
extends RefCounted

## Canonical grammar for dot-paths into parsed JSON — the SINGLE home for the syntax, shared by the
## knob-vector dump (read side, `KnobRegistry._extract`) and `DataOverrides` (write side) so the two
## can never drift. A path is "."-separated segments; each segment is one of:
##
##   key             a dict key
##   name[]  name[*] every element of the array at `name`  (fan out)
##   name[N]         element N of the array at `name`
##
## The two sides share ONLY this segment parsing + index selection; traversal itself differs by
## direction and is intentionally NOT merged: reads are lenient (null on any miss, for the dump),
## writes are fail-loud (a typo'd override path is a bug, never a default).


## Split one segment into {key, is_array, selector}. `selector` is "" for a plain key; for an array
## segment it is "" or "*" (all elements) or a digit string (one index). Malformed brackets assert.
static func parse_segment(segment: String) -> Dictionary:
	var bracket := segment.find("[")
	if bracket == -1:
		return {"key": segment, "is_array": false, "selector": ""}
	assert(segment.ends_with("]"), "Malformed array segment (missing ']'): %s" % segment)
	return {
		"key": segment.substr(0, bracket),
		"is_array": true,
		"selector": segment.substr(bracket + 1, segment.length() - bracket - 2),
	}


## Resolve an array selector to concrete indices: {indices, valid}. "" / "*" address every element
## (always valid, even on an empty array); a digit addresses that one index. `valid` is false when
## the selector is malformed or the index is out of range — writers fail loud on that, readers treat
## it as a miss.
static func select_indices(arr: Array, selector: String) -> Dictionary:
	if selector.is_empty() or selector == "*":
		return {"indices": range(arr.size()), "valid": true}
	if not selector.is_valid_int():
		return {"indices": [], "valid": false}
	var index := int(selector)
	if index < 0 or index >= arr.size():
		return {"indices": [], "valid": false}
	return {"indices": [index], "valid": true}


## True for an all-elements selector ("" or "*"), which fans out; false for a single index.
static func is_all_elements(selector: String) -> bool:
	return selector.is_empty() or selector == "*"
