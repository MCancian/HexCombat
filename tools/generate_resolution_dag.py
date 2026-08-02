#!/usr/bin/env python3
"""Generate designer-readable resolution dependency maps (plan 0061 Part 1).

This is intentionally an on-demand reading aid, not a gate and not a scheduler. Godot reflection
exports declarations; this stdlib-only Python half conservatively scans method bodies, propagates
method effects, constructs call-site graphs, validates focused fixtures/current IJFS structure, and
renders Markdown. Unsupported or ambiguous syntax is reported rather than silently treated as pure.

Usage:
    godot --headless --path . --import  # after adding/renaming class_name scripts
    python3 tools/generate_resolution_dag.py --validate
    python3 tools/generate_resolution_dag.py
"""
from __future__ import annotations

import argparse
import collections
import dataclasses
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Iterable, Iterator, Optional

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
PRESENTATIONS = ROOT / "docs" / "presentations"
FIXTURES = ROOT / "tools" / "fixtures" / "resolution_dag"
MANIFEST_PATH = ROOT / "tools" / "mutation_authority_manifest.json"
EXPORTER_PATH = ROOT / "tools" / "export_resolution_symbols.gd"
GENERATOR_PATH = Path(__file__).resolve()
FORMAT_VERSION = 1
PASS_RE = re.compile(
    r"(?m)^PASS: resolution symbols exported — (\d+) scripts; (\d+) global classes; sha256=([0-9a-f]{64})$"
)
MUTATORS = {
    "append", "append_array", "push_back", "push_front", "pop_back", "pop_front", "pop_at",
    "erase", "clear", "insert", "remove_at", "resize", "sort", "sort_custom", "reverse",
    "shuffle", "fill", "merge", "assign",
}
RNG_METHODS = {
    "roll_d100", "choose_indices", "randf", "weighted_choice", "weighted_choices",
    "shuffle_indices",
}
BUILTIN_TYPES = {
    "Variant", "Nil", "bool", "int", "float", "String", "StringName", "Array", "Dictionary",
    "Callable", "Object", "Resource", "RefCounted", "Node", "SceneTree", "Vector2", "Vector2i",
    "Vector3", "PackedStringArray", "PackedByteArray", "Color", "RegEx", "RegExMatch",
}
RENDER_DIRS = {"calc", "interleaved"}

class DagError(RuntimeError):
    pass


@dataclasses.dataclass(frozen=True)
class Diagnostic:
    kind: str
    path: str
    method: str
    line: int
    excerpt: str

    def text(self) -> str:
        return f"{self.kind}: {self.path}:{self.line} ({self.method}) — `{self.excerpt.strip()}`"


@dataclasses.dataclass
class Effect:
    reads: set[str] = dataclasses.field(default_factory=set)
    writes: set[str] = dataclasses.field(default_factory=set)
    rng_streams: set[str] = dataclasses.field(default_factory=set)
    calls: set[str] = dataclasses.field(default_factory=set)
    diagnostics: set[Diagnostic] = dataclasses.field(default_factory=set)

    def merge(self, other: "Effect") -> bool:
        before = (len(self.reads), len(self.writes), len(self.rng_streams), len(self.calls), len(self.diagnostics))
        self.reads.update(other.reads)
        self.writes.update(other.writes)
        self.rng_streams.update(other.rng_streams)
        self.calls.update(other.calls)
        self.diagnostics.update(other.diagnostics)
        return before != (len(self.reads), len(self.writes), len(self.rng_streams), len(self.calls), len(self.diagnostics))

    def copy(self) -> "Effect":
        return Effect(set(self.reads), set(self.writes), set(self.rng_streams), set(self.calls), set(self.diagnostics))


@dataclasses.dataclass
class Statement:
    line: int
    indent: int
    source: str
    code: str       # comments removed; strings preserved
    masked: str     # comments and string contents blanked


@dataclasses.dataclass
class ClassInfo:
    name: str
    path: str
    base: str
    fields: dict[str, str]
    methods_declared: dict[str, str]
    constants: list[dict]


@dataclasses.dataclass
class MethodInfo:
    key: str
    class_name: str
    name: str
    path: str
    line: int
    indent: int
    params: dict[str, str]
    return_type: str
    statements: list[Statement] = dataclasses.field(default_factory=list)
    direct: Effect = dataclasses.field(default_factory=Effect)
    total: Effect = dataclasses.field(default_factory=Effect)
    scope_types: dict[str, str] = dataclasses.field(default_factory=dict)
    local_names: set[str] = dataclasses.field(default_factory=set)
    call_bindings: list[tuple[str, list[str]]] = dataclasses.field(default_factory=list)
    rng_aliases: dict[str, str] = dataclasses.field(default_factory=dict)
    callsites: list["CallSite"] = dataclasses.field(default_factory=list)


@dataclasses.dataclass(frozen=True)
class CallRef:
    callee: str
    start: int
    arguments: tuple[str, ...]


@dataclasses.dataclass
class CallSite:
    caller: str
    callee: str
    line: int
    ordinal: int
    statement: str
    node_effect: Effect  # statement effects plus the called method's transitive effects

    @property
    def node_id(self) -> str:
        return f"{self.caller}:{self.line}:{self.ordinal}:{self.callee}"


@dataclasses.dataclass(frozen=True)
class Edge:
    source: str
    target: str
    kind: str
    fields: tuple[str, ...]


@dataclasses.dataclass
class LexState:
    quote: Optional[str] = None
    escaped: bool = False


def _lex_line(line: str, state: LexState) -> tuple[str, str]:
    """Return (comments-removed, strings-masked) preserving character positions.

    This is independent from gd_metrics.py by design: the generator is a reading aid and must not
    import a gate-run module. It hardens that tool's strings-before-comments rule with triple-string
    state and exact-length masking.
    """
    decommented = list(line)
    masked = list(line)
    i = 0
    while i < len(line):
        if state.quote:
            quote = state.quote
            if quote in ('"""', "'''") and line.startswith(quote, i) and not state.escaped:
                for j in range(i, min(len(line), i + 3)):
                    masked[j] = " "
                i += 3
                state.quote = None
                continue
            ch = line[i]
            masked[i] = " "
            if quote in ('"', "'") and ch == quote and not state.escaped:
                state.quote = None
            state.escaped = (ch == "\\" and not state.escaped)
            if ch != "\\":
                state.escaped = False
            i += 1
            continue
        if line.startswith('"""', i) or line.startswith("'''", i):
            state.quote = line[i:i + 3]
            for j in range(i, min(len(line), i + 3)):
                masked[j] = " "
            i += 3
            continue
        ch = line[i]
        if ch in ('"', "'"):
            state.quote = ch
            masked[i] = " "
            i += 1
            continue
        if ch == "#":
            for j in range(i, len(line)):
                decommented[j] = " "
                masked[j] = " "
            break
        i += 1
    return "".join(decommented), "".join(masked)


def statements_from_text(text: str) -> list[Statement]:
    lines = text.splitlines()
    lex_state = LexState()
    result: list[Statement] = []
    source_parts: list[str] = []
    code_parts: list[str] = []
    masked_parts: list[str] = []
    start_line = 0
    indent = 0
    depth = 0
    continued = False
    for index, raw in enumerate(lines, 1):
        code, masked = _lex_line(raw, lex_state)
        if not source_parts and not masked.strip():
            continue
        if not source_parts:
            start_line = index
            indent = len(raw) - len(raw.lstrip(" \t"))
        source_parts.append(raw.strip())
        # Keep code/masked chunks at identical lengths. Trimming a trailing string from `masked`
        # but not `code` shifts every match span on the next continuation line and can turn a read
        # into the wrong dictionary-key access.
        code_parts.append(code)
        masked_parts.append(masked)
        for ch in masked:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth = max(0, depth - 1)
        continued = masked.rstrip().endswith("\\")
        if depth == 0 and not continued and lex_state.quote not in ('"""', "'''"):
            joined_source = " ".join(part for part in source_parts if part)
            joined_code = " ".join(code_parts)
            joined_masked = " ".join(masked_parts)
            if joined_masked.strip():
                result.append(Statement(start_line, indent, joined_source, joined_code, joined_masked))
            source_parts = []
            code_parts = []
            masked_parts = []
    if source_parts:
        result.append(Statement(start_line, indent, " ".join(source_parts), " ".join(code_parts), " ".join(masked_parts)))
    return result


def _split_top_level(value: str, delimiter: str = ",") -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    depth = 0
    quote: Optional[str] = None
    escaped = False
    for ch in value:
        if quote:
            current.append(ch)
            if ch == quote and not escaped:
                quote = None
            escaped = ch == "\\" and not escaped
            if ch != "\\":
                escaped = False
            continue
        if ch in ('"', "'"):
            quote = ch
            current.append(ch)
            continue
        if ch in "([{": depth += 1
        elif ch in ")]}": depth = max(0, depth - 1)
        if ch == delimiter and depth == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
    parts.append("".join(current).strip())
    return [part for part in parts if part]


def _type_from_property(row: dict) -> str:
    class_name = row.get("class_name", "")
    if class_name:
        return str(class_name)
    type_name = str(row.get("type_name", "Variant"))
    if type_name == "Nil":
        return "Variant"
    if type_name == "Array" and row.get("hint_string"):
        return f"Array[{row['hint_string']}]"
    return type_name


def _source_hash(paths: Iterable[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(paths):
        rel = path.relative_to(ROOT).as_posix().encode()
        digest.update(rel)
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def _script_paths() -> list[Path]:
    return sorted(SCRIPTS.rglob("*.gd"))


def _symbol_input_paths() -> list[Path]:
    return _script_paths() + [ROOT / "project.godot"]


def export_symbols(output_path: Path, godot: str) -> dict:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    rel_output = output_path.relative_to(ROOT).as_posix()
    command = [godot, "--headless", "--path", str(ROOT), "--quit-after", "180", "-s",
               "res://tools/export_resolution_symbols.gd", "--", f"--output={rel_output}"]
    proc = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=240)
    combined = proc.stdout + proc.stderr
    match = PASS_RE.search(combined)
    if not match:
        tail = "\n".join(combined.splitlines()[-30:])
        raise DagError(f"symbol exporter did not print its exact PASS sentinel (exit {proc.returncode}):\n{tail}")
    declared_scripts, declared_globals, declared_hash = int(match.group(1)), int(match.group(2)), match.group(3)
    try:
        payload = json.loads(output_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DagError(f"symbol exporter output is unreadable: {exc}") from exc
    actual_hash = _source_hash(_symbol_input_paths())
    checks = {
        "format_version": payload.get("format_version") == FORMAT_VERSION,
        "script_count": payload.get("script_count") == declared_scripts == len(payload.get("scripts", [])),
        "global_class_count": declared_globals > 0 and payload.get("global_class_count") == declared_globals,
        "source_hash": payload.get("source_hash") == declared_hash == actual_hash,
    }
    failed = [name for name, ok in checks.items() if not ok]
    if failed:
        raise DagError(f"symbol export contract mismatch: {', '.join(failed)}")
    return payload


class Analyzer:
    def __init__(self, symbols: dict, sources: Optional[dict[str, str]] = None,
                 manifest: Optional[dict] = None,
                 extra_model_classes: Optional[set[str]] = None) -> None:
        self.symbols = symbols
        self.sources = sources or {}
        self.classes: dict[str, ClassInfo] = {}
        self.class_by_path: dict[str, str] = {}
        self.class_aliases: dict[str, str] = {}
        self.class_diagnostics: dict[str, set[Diagnostic]] = collections.defaultdict(set)
        self.methods: dict[str, MethodInfo] = {}
        self.protected_fields: set[str] = set()
        self.protected_names: set[str] = set()
        self.model_classes: set[str] = set()
        self.authority_classes: set[str] = set()
        self.coordinator_classes: set[str] = set()
        self._build_classes()
        self.model_classes.update(extra_model_classes or set())
        self._load_manifest(manifest or {})
        self._parse_methods()
        self._analyse_methods()
        self._propagate()
        self._attach_callsites()

    def _build_classes(self) -> None:
        for row in self.symbols.get("scripts", []):
            name = str(row.get("class", ""))
            if not name:
                continue
            fields = {str(p["name"]): _type_from_property(p) for p in row.get("properties", [])}
            methods = {str(m["name"]): _type_from_property(m.get("return", {}))
                       for m in row.get("methods", [])}
            info = ClassInfo(name, str(row["path"]), str(row.get("base", "")), fields, methods,
                             list(row.get("constants", [])))
            self.classes[name] = info
            self.class_by_path[info.path] = name
            if info.path.startswith("scripts/model/"):
                self.model_classes.add(name)
            if info.path.startswith("scripts/phases/"):
                self.coordinator_classes.add(name)
            for constant in info.constants:
                if "inner_class" in constant:
                    self.class_diagnostics[name].add(Diagnostic(
                        "inner_class_unanalysed", info.path, name, 0,
                        f"inner class {constant.get('name', '<unnamed>')}"))
        for alias, path_value in sorted(self.symbols.get("autoloads", {}).items()):
            primary = self.class_by_path.get(str(path_value), "")
            if primary:
                self.class_aliases[str(alias)] = primary

    def _canonical_class(self, name: str) -> str:
        return self.class_aliases.get(name, name)

    def _load_manifest(self, manifest: dict) -> None:
        for aggregate in manifest.get("aggregates", []):
            authority = str(aggregate.get("authority_class", ""))
            if authority:
                self.authority_classes.add(authority)
            for group in (aggregate.get("owned_models", []), aggregate.get("hosted_fields", [])):
                for model in group:
                    class_name = str(model.get("class", ""))
                    if class_name:
                        self.model_classes.add(class_name)
                    for field in model.get("fields", {}).keys():
                        key = f"{class_name}.{field}"
                        self.protected_fields.add(key)
                        self.protected_names.add(str(field))

    def _text(self, path: str) -> str:
        if path in self.sources:
            return self.sources[path]
        return (ROOT / path).read_text(encoding="utf-8", errors="replace")

    def _parse_methods(self) -> None:
        func_re = re.compile(
            r"^(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\((.*)\)\s*(?:->\s*([^:]+))?\s*:\s*$"
        )
        property_re = re.compile(r"^(?:@[A-Za-z_]\w*(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+([A-Za-z_]\w*)\s*(?::\s*([^:=]+))?\s*:\s*$")
        delegated_property_re = re.compile(
            r"^(?:@[A-Za-z_]\w*(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+"
            r"([A-Za-z_]\w*)\s*:\s*([^:]+?)\s*:\s*(get|set)\s*=\s*([A-Za-z_]\w*)\s*$")
        accessor_re = re.compile(r"^(get|set)(?:\(([^)]*)\))?\s*:\s*(.*)$")
        for class_name, cls in sorted(self.classes.items()):
            try:
                statements = statements_from_text(self._text(cls.path))
            except OSError:
                continue
            active: Optional[MethodInfo] = None
            property_name: Optional[str] = None
            property_indent = -1
            for statement in statements:
                stripped = statement.masked.strip()
                match = func_re.match(stripped)
                if match:
                    active = None
                    property_name = None
                    # Top-level class methods only. Inner-class methods are reflected as constants and
                    # remain an explicit Variant/inner-class limitation instead of being misattributed.
                    if statement.indent != 0:
                        continue
                    name = match.group(1)
                    params = self._parse_params(match.group(2))
                    return_type = (match.group(3) or cls.methods_declared.get(name, "Variant")).strip()
                    key = f"{class_name}.{name}"
                    active = MethodInfo(key, class_name, name, cls.path, statement.line,
                                        statement.indent, params, return_type)
                    active.scope_types = dict(params)
                    active.local_names = set(params)
                    self.methods[key] = active
                    continue
                delegated_match = delegated_property_re.match(stripped)
                if delegated_match and statement.indent == 0:
                    active = None
                    property_name, property_type, kind, helper = delegated_match.groups()
                    name = f"@{kind}:{property_name}"
                    params = {"value": property_type.strip()} if kind == "set" else {}
                    key = f"{class_name}.{name}"
                    accessor = MethodInfo(
                        key, class_name, name, cls.path, statement.line, statement.indent, params,
                        property_type.strip() if kind == "get" else "void")
                    accessor.scope_types = dict(params)
                    accessor.local_names = set(params)
                    accessor.direct.calls.add(f"{class_name}.{helper}")
                    self.methods[key] = accessor
                    property_name = None
                    continue
                prop_match = property_re.match(stripped)
                if prop_match and statement.indent == 0:
                    active = None
                    property_name = prop_match.group(1)
                    property_indent = statement.indent
                    continue
                accessor_match = accessor_re.match(stripped)
                if property_name and accessor_match and statement.indent > property_indent:
                    kind, parameter_text, inline_body = accessor_match.groups()
                    name = f"@{kind}:{property_name}"
                    params = self._parse_params(parameter_text or "")
                    if kind == "set" and not params:
                        params = {"value": cls.fields.get(property_name, "Variant")}
                    key = f"{class_name}.{name}"
                    active = MethodInfo(key, class_name, name, cls.path, statement.line,
                                        statement.indent, params,
                                        cls.fields.get(property_name, "Variant") if kind == "get" else "void")
                    active.scope_types = dict(params)
                    active.local_names = set(params)
                    self.methods[key] = active
                    if inline_body.strip():
                        offset = statement.source.find(":") + 1
                        active.statements.append(Statement(statement.line, statement.indent + 1,
                                                           inline_body.strip(), inline_body.strip(), inline_body.strip()))
                    continue
                if active is not None:
                    if statement.indent <= active.indent:
                        active = None
                    else:
                        active.statements.append(statement)
                if property_name and statement.indent <= property_indent and not prop_match:
                    property_name = None

    def _parse_params(self, value: str) -> dict[str, str]:
        result: dict[str, str] = {}
        for part in _split_top_level(value):
            match = re.match(r"([A-Za-z_]\w*)\s*(?::\s*([^=]+))?", part)
            if match:
                result[match.group(1)] = (match.group(2) or "Variant").strip()
        return result

    def _analyse_methods(self) -> None:
        for method in self.methods.values():
            scope = dict(method.params)
            method.local_names = set(method.params)
            method.rng_aliases = {
                name: name for name, type_name in method.params.items() if "Dice" in type_name}
            scope["self"] = method.class_name
            cls = self.classes[method.class_name]
            scope.update({name: field_type for name, field_type in cls.fields.items()})
            for statement in method.statements:
                self._bind_types(statement, method, scope)
                self._scan_statement(statement, method, scope)
            method.scope_types = scope
            method.total = method.direct.copy()

    def _bind_types(self, statement: Statement, method: MethodInfo, scope: dict[str, str]) -> None:
        code = statement.masked.strip()
        var_match = re.match(r"var\s+([A-Za-z_]\w*)\s*(?::\s*([^:=]+))?\s*(?::=|=)\s*(.+)$", code)
        if var_match:
            name, annotation, expression = var_match.group(1), var_match.group(2), var_match.group(3)
            inferred = annotation.strip() if annotation else self._resolve_expression_type(expression, method, scope)
            scope[name] = inferred or "Variant"
            method.local_names.add(name)
            expression_text = expression.strip()
            if expression_text in method.rng_aliases:
                method.rng_aliases[name] = method.rng_aliases[expression_text]
            elif re.fullmatch(r"[A-Za-z_]\w*", expression_text) and "Dice" in scope.get(expression_text, ""):
                method.rng_aliases[name] = expression_text
            elif re.search(r"\.derive\s*\(", expression_text):
                method.rng_aliases[name] = (
                    f"derived@{method.path}:{statement.line}:{name}")
            if scope[name] == "Variant" and self._stateful_untyped(expression, annotation, method, scope):
                method.direct.diagnostics.add(Diagnostic(
                    "untyped_alias", method.path, method.key, statement.line, statement.source))
        else:
            declaration = re.match(r"var\s+([A-Za-z_]\w*)\s*:\s*([^=]+?)\s*$", code)
            if declaration:
                scope[declaration.group(1)] = declaration.group(2).strip()
                method.local_names.add(declaration.group(1))
        for_match = re.match(r"for\s+([A-Za-z_]\w*)\s*(?::\s*([^ ]+))?\s+in\s+(.+)\s*:\s*$", code)
        if for_match:
            name, annotation, expression = for_match.group(1), for_match.group(2), for_match.group(3)
            collection_type = self._resolve_expression_type(expression, method, scope)
            scope[name] = annotation or self._element_type(collection_type) or "Variant"
            method.local_names.add(name)
            if scope[name] == "Variant" and self._stateful_untyped(expression, annotation, method, scope):
                method.direct.diagnostics.add(Diagnostic(
                    "untyped_iteration", method.path, method.key, statement.line, statement.source))

    def _resolve_expression_type(self, expression: str, method: MethodInfo,
                                 scope: dict[str, str]) -> str:
        expression = expression.strip()
        cast = re.search(r"\bas\s+([A-Za-z_]\w*(?:\[[^]]+\])?)", expression)
        if cast:
            return cast.group(1)
        created = re.match(r"([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.new\s*\(", expression)
        if created:
            return created.group(1)
        call = re.match(r"([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(", expression)
        if call:
            receiver_class = self._canonical_class(call.group(1))
            target = f"{receiver_class}.{call.group(2)}"
            if target in self.methods:
                return self.methods[target].return_type
            if receiver_class in self.classes:
                return self.classes[receiver_class].methods_declared.get(call.group(2), "Variant")
        local_call = re.match(r"([A-Za-z_]\w*)\s*\(", expression)
        if local_call:
            target = f"{method.class_name}.{local_call.group(1)}"
            if target in self.methods:
                return self.methods[target].return_type
        chain = re.match(r"([A-Za-z_]\w*(?:\[[^]]+\])?(?:\.[A-Za-z_]\w*(?:\[[^]]+\])?)*)", expression)
        if chain:
            return self._resolve_chain_type(chain.group(1), method, scope)
        return "Variant"

    def _resolve_chain_type(self, chain: str, method: MethodInfo, scope: dict[str, str]) -> str:
        parts = self._chain_parts(chain)
        if not parts:
            return "Variant"
        root_name, root_index = parts[0]
        canonical_root = self._canonical_class(root_name)
        current = scope.get(root_name, canonical_root if canonical_root in self.classes else "Variant")
        if root_index:
            current = self._element_type(current) or "Variant"
        for name, index in parts[1:]:
            base = self._base_type(current)
            if base not in self.classes or name not in self.classes[base].fields:
                return "Variant"
            current = self.classes[base].fields[name]
            if index:
                current = self._element_type(current) or "Variant"
        return current

    @staticmethod
    def _base_type(type_name: str) -> str:
        return type_name.split("[", 1)[0].strip()

    @staticmethod
    def _element_type(type_name: str) -> Optional[str]:
        match = re.match(r"Array\[([^]]+)\]", type_name.strip())
        return match.group(1) if match else None

    def _stateful_untyped(self, expression: str, annotation: Optional[str], method: MethodInfo,
                          scope: dict[str, str]) -> bool:
        # Explicit Variant carriers containing an index/member are worth surfacing. For inferred
        # scalars, avoid flooding pages with `var probability := 0.0`; require a state-shaped root or
        # a protected field name.
        if annotation and annotation.strip() == "Variant" and ("[" in expression or "." in expression):
            return True
        if any(re.search(r"\." + re.escape(name) + r"\b", expression) for name in self.protected_names):
            return True
        roots = re.findall(r"\b([A-Za-z_]\w*)\s*(?:\.|\[)", expression)
        for root in roots:
            root_type = scope.get(root, "Variant")
            base = self._base_type(root_type)
            element = self._element_type(root_type)
            if base in self.model_classes or element in self.model_classes:
                return True
            if root in {"state", "target", "ctx", "data", "data_store", "brigade", "squadron", "munition"}:
                return True
        return False

    @staticmethod
    def _chain_parts(chain: str) -> list[tuple[str, Optional[str]]]:
        raw_parts: list[str] = []
        current: list[str] = []
        bracket_depth = 0
        for character in chain:
            if character == "[":
                bracket_depth += 1
            elif character == "]":
                bracket_depth = max(0, bracket_depth - 1)
            if character == "." and bracket_depth == 0:
                raw_parts.append("".join(current))
                current = []
            else:
                current.append(character)
        raw_parts.append("".join(current))
        parts: list[tuple[str, Optional[str]]] = []
        for raw in raw_parts:
            match = re.fullmatch(r"\s*([A-Za-z_]\w*)(?:\[(.*)\])?\s*", raw)
            if not match:
                return []
            parts.append((match.group(1), match.group(2)))
        return parts

    def _scan_statement(self, statement: Statement, method: MethodInfo,
                        scope: dict[str, str]) -> None:
        masked = statement.masked
        assignment = self._assignment(masked)
        call_refs = self._calls_in_statement(statement, method, scope)
        method.direct.calls.update(ref.callee for ref in call_refs)
        if len(call_refs) > 1:
            method.direct.diagnostics.add(Diagnostic(
                "multi_call_statement", method.path, method.key, statement.line, statement.source))
        for ref in call_refs:
            method.call_bindings.append((ref.callee, list(ref.arguments)))
        if re.search(r"\.call(?:v)?\s*\(", masked):
            method.direct.diagnostics.add(Diagnostic(
                "dynamic_dispatch", method.path, method.key, statement.line, statement.source))
        if "func(" in masked or re.search(r"\bCallable\b", masked):
            method.direct.diagnostics.add(Diagnostic(
                "callable_or_lambda", method.path, method.key, statement.line, statement.source))

        chain_re = re.compile(r"\b[A-Za-z_]\w*(?:\[[^]\n]+\])?(?:\s*\.\s*[A-Za-z_]\w*(?:\[[^]\n]+\])?)+")
        nested_index = self._has_nested_brackets(masked)
        if nested_index:
            method.direct.diagnostics.add(Diagnostic(
                "nested_index_unanalysed", method.path, method.key, statement.line, statement.source))
        chain_matches = [] if nested_index else chain_re.finditer(masked)
        for match in chain_matches:
            chain = match.group(0)
            # `code` preserves literal dictionary keys while `masked` provides trustworthy spans.
            source_chain = statement.code[match.start():match.end()]
            # Trim a terminal method segment; it is a call/mutator, not a field.
            after = masked[match.end():]
            terminal_call = bool(re.match(r"\s*\(", after))
            parts = self._chain_parts(source_chain)
            if not parts:
                continue
            terminal_method = parts[-1][0] if terminal_call else ""
            field_parts = parts[:-1] if terminal_call else parts
            accesses = self._field_accesses(field_parts, method, scope)
            self._scan_index_reads(source_chain, statement, method, scope)
            if not accesses:
                if any(name in self.protected_names for name, _ in field_parts[1:]):
                    method.direct.diagnostics.add(Diagnostic(
                        "unresolved_receiver", method.path, method.key, statement.line, statement.source))
                continue
            mutates = terminal_call and terminal_method in MUTATORS
            lhs_end = assignment[0] if assignment else -1
            compound = assignment[1] != "=" if assignment else False
            # A field used inside an LHS index is a read, not the write target:
            # `totals[target.category] = count` reads category. The old positional test marked it
            # written and invented WAW/WAR edges in pure reporting code.
            bracket_depth = self._bracket_depth(masked[:match.start()])
            on_lhs = assignment is not None and match.start() < lhs_end and bracket_depth == 0
            for index, field_key in enumerate(accesses):
                final = index == len(accesses) - 1
                base_field = field_key.split("[", 1)[0]
                owner, field_name = base_field.split(".", 1)
                if final and (on_lhs or mutates):
                    method.direct.writes.add(field_key)
                    setter = f"{owner}.@set:{field_name}"
                    if setter in self.methods and setter != method.key:
                        method.direct.calls.add(setter)
                    if compound or mutates:
                        method.direct.reads.add(field_key)
                        getter = f"{owner}.@get:{field_name}"
                        if getter in self.methods and getter != method.key:
                            method.direct.calls.add(getter)
                else:
                    method.direct.reads.add(field_key)
                    getter = f"{owner}.@get:{field_name}"
                    if getter in self.methods and getter != method.key:
                        method.direct.calls.add(getter)

        # Instance methods may use member fields without `self.`. Parameters/locals shadow members,
        # so only unshadowed reflected fields are eligible. This catches ordinary model mutators and
        # delegated setter helpers, not just inline accessor bodies.
        cls = self.classes[method.class_name]
        if not nested_index and (method.class_name in self.model_classes or any(
                f"{method.class_name}.{name}" in self.protected_fields for name in cls.fields)):
            for field_name in cls.fields:
                if field_name in method.local_names:
                    continue
                pattern = re.compile(r"(?<![.\w])" + re.escape(field_name) + r"\b")
                for occurrence in pattern.finditer(masked):
                    field_key = f"{method.class_name}.{field_name}"
                    suffix_code = statement.code[occurrence.end():]
                    key_match = re.match(r"\s*\[\s*([&]?[\"'][^\"']+[\"'])\s*\]", suffix_code)
                    if key_match:
                        literal = self._literal_key(key_match.group(1))
                        if literal:
                            field_key += f"[{literal}]"
                    method_match = re.match(r"\s*\.\s*([A-Za-z_]\w*)\s*\(", suffix_code)
                    mutates = bool(method_match and method_match.group(1) in MUTATORS)
                    on_lhs = (assignment is not None and occurrence.start() < assignment[0] and
                              self._bracket_depth(masked[:occurrence.start()]) == 0)
                    compound = assignment is not None and assignment[1] != "="
                    if on_lhs or mutates:
                        method.direct.writes.add(field_key)
                        setter = f"{method.class_name}.@set:{field_name}"
                        if setter in self.methods and setter != method.key:
                            method.direct.calls.add(setter)
                        if compound or mutates:
                            method.direct.reads.add(field_key)
                    else:
                        method.direct.reads.add(field_key)
                        getter = f"{method.class_name}.@get:{field_name}"
                        if getter in self.methods and getter != method.key:
                            method.direct.calls.add(getter)

        for receiver, rng_method in re.findall(r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.([A-Za-z_]\w*)\s*\(", masked):
            receiver_type = self._resolve_chain_type(receiver, method, scope)
            if rng_method in RNG_METHODS and ("Dice" in receiver_type or "dice" in receiver.lower()):
                identity = method.rng_aliases.get(receiver, receiver)
                method.direct.rng_streams.add(self._rng_stream_label(identity, statement.code))

    @staticmethod
    def _has_nested_brackets(code: str) -> bool:
        # Only a nested INDEX is unsupported. Array/dictionary literals may legitimately surround a
        # simple `state.rows[key]` access and must not suppress that access.
        stack: list[bool] = []
        for index, character in enumerate(code):
            if character == "[":
                is_index = (index > 0 and not code[index - 1].isspace() and
                            (code[index - 1].isalnum() or code[index - 1] in "_]") )
                if is_index and any(stack):
                    return True
                stack.append(is_index)
            elif character == "]" and stack:
                stack.pop()
        return False

    def _scan_index_reads(self, chain: str, statement: Statement, method: MethodInfo,
                          scope: dict[str, str]) -> None:
        for expression in re.findall(r"\[([^]]+)\]", chain):
            for match in re.finditer(
                    r"\b[A-Za-z_]\w*(?:\[[^]\n]+\])?(?:\s*\.\s*[A-Za-z_]\w*(?:\[[^]\n]+\])?)+",
                    expression):
                parts = self._chain_parts(match.group(0))
                for field_key in self._field_accesses(parts, method, scope):
                    method.direct.reads.add(field_key)

    @staticmethod
    def _bracket_depth(prefix: str) -> int:
        depth = 0
        for character in prefix:
            if character == "[":
                depth += 1
            elif character == "]":
                depth = max(0, depth - 1)
        return depth

    @staticmethod
    def _assignment(masked: str) -> Optional[tuple[int, str]]:
        depth = 0
        for index, ch in enumerate(masked):
            if ch in "([{": depth += 1
            elif ch in ")]}": depth = max(0, depth - 1)
            if depth != 0:
                continue
            for op in ("+=", "-=", "*=", "/=", "%=", "|=", "&=", "^=", "="):
                if masked.startswith(op, index):
                    if op == "=" and ((index + 1 < len(masked) and masked[index + 1] == "=") or
                                      (index > 0 and masked[index - 1] in "!<>=:")):
                        continue
                    return index, op
        return None

    def _field_accesses(self, parts: list[tuple[str, Optional[str]]], method: MethodInfo,
                        scope: dict[str, str]) -> list[str]:
        if not parts:
            return []
        root, root_index = parts[0]
        canonical_root = self._canonical_class(root)
        current = scope.get(root, canonical_root if canonical_root in self.classes else "Variant")
        if root_index:
            current = self._element_type(current) or "Variant"
        accesses: list[str] = []
        for name, index in parts[1:]:
            base = self._base_type(current)
            cls = self.classes.get(base)
            if cls is None or name not in cls.fields:
                break
            field_key = f"{base}.{name}"
            if index:
                literal = self._literal_key(index)
                if literal:
                    field_key += f"[{literal}]"
            if base in self.model_classes or field_key.split("[", 1)[0] in self.protected_fields:
                accesses.append(field_key)
            current = cls.fields[name]
            if index:
                current = self._element_type(current) or "Variant"
        return accesses

    @staticmethod
    def _literal_key(index: str) -> Optional[str]:
        value = index.strip()
        match = re.fullmatch(r"[&]?['\"]([^'\"]+)['\"]", value)
        return match.group(1) if match else None

    def _calls_in_statement(self, statement: Statement, method: MethodInfo,
                            scope: dict[str, str]) -> list[CallRef]:
        refs: dict[tuple[int, str], CallRef] = {}
        masked = statement.masked

        def add_ref(match: re.Match[str], target: str) -> None:
            open_paren = masked.find("(", match.start(), match.end() + 1)
            if open_paren < 0:
                return
            arguments = self._arguments_at(statement.code, open_paren)
            normalized = tuple(
                self._rng_argument_identity(argument, method, statement, match.start(), index)
                for index, argument in enumerate(arguments))
            refs[(match.start(), target)] = CallRef(target, match.start(), normalized)

        # Reflected inner-class calls remain call-site nodes even though their bodies/types may be
        # incomplete (Godot exposes them through the outer script's constant map).
        inner_pattern = re.compile(
            r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(")
        for match in inner_pattern.finditer(masked):
            outer, inner, name = match.groups()
            cls = self.classes.get(outer)
            if cls and any(str(row.get("name", "")) == inner for row in cls.constants):
                add_ref(match, f"{outer}.{inner}.{name}")

        # Class/typed receiver calls.
        receiver_pattern = re.compile(
            r"\b([A-Za-z_]\w*(?:\[[^]]+\])?(?:\.[A-Za-z_]\w*(?:\[[^]]+\])?)*)\."
            r"([A-Za-z_]\w*)\s*\(")
        for match in receiver_pattern.finditer(masked):
            receiver, name = match.groups()
            canonical_receiver = self._canonical_class(receiver)
            if canonical_receiver in self.classes:
                target = f"{canonical_receiver}.{name}"
            else:
                receiver_type = self._resolve_chain_type(receiver, method, scope)
                target = f"{self._base_type(receiver_type)}.{name}"
            if target in self.methods or target.split(".", 1)[0] in self.classes:
                add_ref(match, target)

        # Local helper calls (exclude language keywords and already-qualified calls).
        for match in re.finditer(r"(?<![.])\b([A-Za-z_]\w*)\s*\(", masked):
            name = match.group(1)
            target = f"{method.class_name}.{name}"
            if target in self.methods:
                add_ref(match, target)
        return sorted(refs.values(), key=lambda ref: (ref.start, ref.callee))

    @staticmethod
    def _rng_argument_identity(argument: str, method: MethodInfo, statement: Statement,
                               call_start: int, argument_index: int) -> str:
        value = argument.strip()
        if value in method.rng_aliases:
            return method.rng_aliases[value]
        if re.search(r"\.derive\s*\(", value):
            return f"derived@{method.path}:{statement.line}:{call_start}:{argument_index}"
        return value

    @staticmethod
    def _rng_stream_label(receiver: str, code: str) -> str:
        derive = re.search(r"\.derive\s*\(\s*['\"]([^'\"]+)['\"]", code)
        return f"{receiver}.derive({derive.group(1)})" if derive else receiver

    def _propagate(self) -> None:
        # Monotone fixed point. Cycles converge because every component is a finite set.
        changed = True
        rounds = 0
        while changed and rounds <= len(self.methods) + 1:
            rounds += 1
            changed = False
            for method in self.methods.values():
                bindings = method.call_bindings or [(callee, []) for callee in sorted(method.direct.calls)]
                for callee, arguments in bindings:
                    target = self.methods.get(callee)
                    if target is None:
                        continue
                    target_effect = target.total.copy()
                    target_effect.rng_streams = self._remap_streams(
                        target, target_effect.rng_streams, arguments)
                    if method.total.merge(target_effect):
                        changed = True
        if changed:
            raise DagError("effect propagation did not converge within the finite method bound")

    def _attach_callsites(self) -> None:
        for method in self.methods.values():
            ordinal = 0
            for statement in method.statements:
                call_refs = self._calls_in_statement(statement, method, method.scope_types)
                statement_effect = self._effect_for_statement(statement, method)
                for ref_index, ref in enumerate(call_refs):
                    ordinal += 1
                    # Assignment/result effects belong to the outer lexical call, not every nested
                    # argument call on the same statement. Nested callees still carry their own
                    # transitive effects below.
                    effect = statement_effect.copy() if ref_index == 0 else Effect()
                    target = self.methods.get(ref.callee)
                    if target:
                        target_effect = target.total.copy()
                        target_effect.rng_streams = self._remap_streams(
                            target, target_effect.rng_streams, list(ref.arguments))
                        effect.merge(target_effect)
                    elif ref.callee.split(".", 1)[0] in self.classes:
                        effect.diagnostics.add(Diagnostic(
                            "callee_body_unresolved", method.path, method.key, statement.line, statement.source))
                    method.callsites.append(CallSite(
                        method.key, ref.callee, statement.line, ordinal, statement.source, effect))

    @staticmethod
    def _remap_streams(callee: MethodInfo, streams: set[str], arguments: list[str]) -> set[str]:
        bindings = dict(zip(callee.params.keys(), arguments))
        remapped: set[str] = set()
        for stream in streams:
            replacement = stream
            for parameter, argument in bindings.items():
                if stream == parameter:
                    replacement = argument
                    break
                if stream.startswith(parameter + "."):
                    replacement = argument + stream[len(parameter):]
                    break
            remapped.add(replacement)
        return remapped

    @staticmethod
    def _call_arguments(code: str, method_name: str, occurrence: int = 1) -> list[str]:
        matches = list(re.finditer(r"\b" + re.escape(method_name) + r"\s*\(", code))
        if occurrence < 1 or occurrence > len(matches):
            return []
        match = matches[occurrence - 1]
        open_paren = code.find("(", match.start())
        return Analyzer._arguments_at(code, open_paren)

    @staticmethod
    def _arguments_at(code: str, open_paren: int) -> list[str]:
        if open_paren < 0:
            return []
        start = open_paren + 1
        depth = 1
        quote: Optional[str] = None
        escaped = False
        for index in range(start, len(code)):
            ch = code[index]
            if quote:
                if ch == quote and not escaped:
                    quote = None
                escaped = ch == "\\" and not escaped
                if ch != "\\":
                    escaped = False
                continue
            if ch in ('\"', "'"):
                quote = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return _split_top_level(code[start:index])
        return []

    def _effect_for_statement(self, statement: Statement, method: MethodInfo) -> Effect:
        # Re-scan one statement with the final function scope so assignment targets become call-node effects.
        temp = MethodInfo(method.key, method.class_name, method.name, method.path,
                          method.line, method.indent, method.params, method.return_type)
        self._scan_statement(statement, temp, method.scope_types)
        return temp.direct

    def ordering_methods(self) -> list[MethodInfo]:
        selected: list[MethodInfo] = []
        for method in self.methods.values():
            if method.path.startswith("scripts/interleaved/") and method.name == "run_daily" and method.callsites:
                selected.append(method)
            elif method.class_name in self.coordinator_classes and method.callsites:
                selected.append(method)
        return sorted(selected, key=lambda m: m.key)

    def graph_for(self, method: MethodInfo) -> tuple[list[CallSite], list[Edge]]:
        nodes = method.callsites
        edges: set[Edge] = set()
        for first, second in zip(nodes, nodes[1:]):
            edges.add(Edge(first.node_id, second.node_id, "CALL", ()))
        for left_index, left in enumerate(nodes):
            for right in nodes[left_index + 1:]:
                # Multiple calls on one logical statement may be nested; lexical start order is not
                # evaluation order. Keep the CALL map but do not invent directional state/RNG edges.
                if left.line == right.line:
                    continue
                raw = left.node_effect.writes & right.node_effect.reads
                war = left.node_effect.reads & right.node_effect.writes
                waw = left.node_effect.writes & right.node_effect.writes
                if raw: edges.add(Edge(left.node_id, right.node_id, "RAW", tuple(sorted(raw))))
                if war: edges.add(Edge(left.node_id, right.node_id, "WAR", tuple(sorted(war))))
                if waw: edges.add(Edge(left.node_id, right.node_id, "WAW", tuple(sorted(waw))))
        by_stream: dict[str, list[CallSite]] = collections.defaultdict(list)
        for node in nodes:
            for stream in node.node_effect.rng_streams:
                by_stream[stream].append(node)
        for stream, stream_nodes in by_stream.items():
            for first, second in zip(stream_nodes, stream_nodes[1:]):
                edges.add(Edge(first.node_id, second.node_id, "RNG", (stream,)))
        return nodes, sorted(edges, key=lambda edge: (edge.source, edge.target, edge.kind, edge.fields))


def _load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def _fixture_analyzer() -> Analyzer:
    symbols = json.loads((FIXTURES / "fixture_symbols.json").read_text(encoding="utf-8"))
    source_path = "tools/fixtures/resolution_dag/source_patterns.gdfixture"
    sources = {source_path: (FIXTURES / "source_patterns.gdfixture").read_text(encoding="utf-8")}
    # Fixture classes deliberately live outside scripts/model; classify them before analysis so the
    # fixture follows the same one-shot constructor lifecycle as production.
    return Analyzer(
        symbols, sources=sources,
        extra_model_classes={"ResolutionDagFixture", "FixtureState", "FixtureTarget"})


def run_self_tests() -> list[str]:
    results: list[str] = []
    escape_state = LexState()
    _lex_line('var path := "\\\\"', escape_state)
    _code_after, mask_after = _lex_line("target.health", escape_state)
    if escape_state.quote is not None or "target.health" not in mask_after:
        raise DagError("self-test: an escaped backslash kept string masking open across lines")
    if (Analyzer._call_arguments("pick(first) + pick(second)", "pick", 1) != ["first"] or
            Analyzer._call_arguments("pick(first) + pick(second)", "pick", 2) != ["second"]):
        raise DagError("self-test: repeated calls on one statement reused the first argument list")
    joined = statements_from_text((FIXTURES / "source_patterns.gdfixture").read_text(encoding="utf-8"))
    fake_hits = [s for s in joined if "Fake.call" in s.masked or "state.target.health" in s.masked and s.line == 13]
    if fake_hits:
        raise DagError("self-test: comment/string masking leaked fake calls or fields")
    multiline = [s for s in joined if "helper(" in s.masked and s.line == 21]
    if len(multiline) != 1 or "alias" not in multiline[0].masked:
        raise DagError("self-test: multiline statement joining failed")
    results.append("comment/string masking and multiline joining")

    analyzer = _fixture_analyzer()
    if not any(d.kind == "inner_class_unanalysed"
               for d in analyzer.class_diagnostics.get("ResolutionDagFixture", set())):
        raise DagError("self-test: reflected inner class did not produce a visible limitation")
    helper = analyzer.methods.get("ResolutionDagFixture.helper")
    ordering = analyzer.methods.get("ResolutionDagFixture.ordering")
    recursive = analyzer.methods.get("ResolutionDagFixture.recursive")
    if not helper or not ordering or not recursive:
        raise DagError("self-test: fixture method indexing failed")
    expected_helper_writes = {"FixtureTarget.health", "FixtureTarget.metadata[status]"}
    if not expected_helper_writes <= helper.total.writes:
        raise DagError(f"self-test: helper writes missing: expected {expected_helper_writes}, got {helper.total.writes}")
    if "FixtureTarget.health" not in helper.total.reads:
        raise DagError("self-test: compound assignment did not register a read")
    if not expected_helper_writes <= recursive.total.writes:
        raise DagError("self-test: recursive fixed-point propagation missed helper effects")
    if not expected_helper_writes <= ordering.total.writes:
        raise DagError("self-test: alias/transitive effects did not reach ordering")
    typed_loop = analyzer.methods.get("ResolutionDagFixture.typed_loop_direct")
    if (not typed_loop or "FixtureTarget.health" not in typed_loop.direct.reads or
            "FixtureTarget.health" not in typed_loop.direct.writes):
        raise DagError("self-test: unannotated loop over reflected Array[T] lost the element type")
    mutual = analyzer.methods.get("ResolutionDagFixture.mutual_a")
    if not mutual or "FixtureTarget.metadata[mutual]" not in mutual.total.writes:
        raise DagError("self-test: fixed-point propagation stopped before a later-declared call chain")
    helper_sites = [site for site in ordering.callsites if site.callee == "ResolutionDagFixture.helper"]
    if len(helper_sites) != 2 or len({site.node_id for site in helper_sites}) != 2:
        raise DagError("self-test: repeated call sites were collapsed")
    if len([site for site in ordering.callsites if site.callee == "Dice.roll_d100"]) != 2:
        # Dice is absent from fixture symbols, so direct RNG still appears in the method effect but not
        # as a graph node. This assertion documents the deliberate boundary instead of pretending.
        if "dice" not in ordering.total.rng_streams:
            raise DagError("self-test: RNG stream detection failed")
    getter = analyzer.methods.get("ResolutionDagFixture.@get:property_health")
    setter = analyzer.methods.get("ResolutionDagFixture.@set:property_health")
    if not getter or "ResolutionDagFixture.property_health" not in getter.total.reads:
        raise DagError("self-test: custom property getter body was not analysed")
    if not setter or "ResolutionDagFixture.property_health" not in setter.total.writes:
        raise DagError("self-test: custom property setter body was not analysed")
    index_only = analyzer.methods.get("ResolutionDagFixture.index_key_is_read")
    if (not index_only or "FixtureTarget.health" not in index_only.direct.reads or
            "FixtureTarget.health" in index_only.direct.writes):
        raise DagError("self-test: a model field inside an LHS index must be read, not written")
    nested_write = analyzer.methods.get("ResolutionDagFixture.nested_write")
    if (not nested_write or "FixtureState.targets" not in nested_write.direct.reads or
            "FixtureTarget.health" not in nested_write.direct.writes or
            "FixtureState.targets" in nested_write.direct.writes):
        raise DagError("self-test: nested collection write did not separate receiver reads from final write")
    dotted_index = analyzer.methods.get("ResolutionDagFixture.dotted_index_write")
    if (not dotted_index or "FixtureState.targets" not in dotted_index.direct.reads or
            "FixtureTarget.health" not in dotted_index.direct.reads or
            "FixtureTarget.health" not in dotted_index.direct.writes or
            "FixtureState.targets" in dotted_index.direct.writes):
        raise DagError("self-test: dotted index expressions corrupted nested read/write ownership")
    nested_index = analyzer.methods.get("ResolutionDagFixture.nested_index_is_loud")
    if (not nested_index or nested_index.direct.reads or nested_index.direct.writes or
            not any(d.kind == "nested_index_unanalysed" for d in nested_index.direct.diagnostics)):
        raise DagError("self-test: nested indexes must stop field analysis with a loud diagnostic")
    offset_case = analyzer.methods.get("ResolutionDagFixture.multiline_string_offset")
    if not offset_case or "FixtureTarget.metadata[status]" not in offset_case.direct.reads:
        raise DagError("self-test: multiline string masking shifted later field/key spans")
    declared = analyzer.methods.get("ResolutionDagFixture.declared_before_assignment")
    if not declared or "FixtureTarget.health" not in declared.direct.reads:
        raise DagError("self-test: typed local declared before assignment lost its receiver type")
    delegated = analyzer.methods.get("ResolutionDagFixture.@set:delegated_health")
    if (not delegated or "ResolutionDagFixture._set_delegated_health" not in delegated.direct.calls or
            "ResolutionDagFixture.property_health" not in delegated.total.writes):
        raise DagError("self-test: delegated custom setter did not propagate helper effects")
    independent = analyzer.methods.get("ResolutionDagFixture.independent_streams")
    same_label = analyzer.methods.get("ResolutionDagFixture.same_label_independent_streams")
    shared = analyzer.methods.get("ResolutionDagFixture.shared_stream")
    aliased = analyzer.methods.get("ResolutionDagFixture.aliased_shared_stream")
    if not independent or not same_label or not shared or not aliased:
        raise DagError("self-test: RNG fixture methods were not indexed")
    independent_rng = [edge for edge in analyzer.graph_for(independent)[1] if edge.kind == "RNG"]
    same_label_rng = [edge for edge in analyzer.graph_for(same_label)[1] if edge.kind == "RNG"]
    shared_rng = [edge for edge in analyzer.graph_for(shared)[1] if edge.kind == "RNG"]
    aliased_rng = [edge for edge in analyzer.graph_for(aliased)[1] if edge.kind == "RNG"]
    if independent_rng or same_label_rng or len(shared_rng) != 1 or len(aliased_rng) != 1:
        raise DagError(
            "self-test: derived RNG objects must be independent while shared/aliased streams stay ordered")
    if len(independent.total.rng_streams) != 2 or len(same_label.total.rng_streams) != 2:
        raise DagError(f"self-test: derived RNG call-site identities collapsed: {independent.total.rng_streams}, "
                       f"{same_label.total.rng_streams}")
    nested_assignment = analyzer.methods.get("ResolutionDagFixture.nested_assignment")
    if not nested_assignment or len(nested_assignment.callsites) != 2:
        raise DagError("self-test: nested assignment call sites were not indexed")
    outer, inner = nested_assignment.callsites
    if ("FixtureTarget.health" not in outer.node_effect.writes or
            "FixtureTarget.health" in inner.node_effect.writes or
            any(edge.kind != "CALL" for edge in analyzer.graph_for(nested_assignment)[1])):
        raise DagError("self-test: one statement's assignment effect leaked onto nested argument calls")
    results.append("typed aliases/loops, nested keys, recursion, repeated call sites, property accessors, and RNG")
    return results


def validate_current_ijfs(analyzer: Analyzer) -> list[str]:
    oracle = json.loads((FIXTURES / "ijfs_current_oracle.json").read_text(encoding="utf-8"))
    method = analyzer.methods.get(oracle["ordering_method"])
    if method is None:
        raise DagError(f"IJFS oracle method missing: {oracle['ordering_method']}")
    counts = collections.Counter(site.callee for site in method.callsites)
    for callee, expected in oracle["required_call_counts"].items():
        if counts[callee] != expected:
            raise DagError(f"IJFS current oracle: {callee} expected {expected} call sites, found {counts[callee]}")
    for forbidden in oracle["forbidden_calls"]:
        if counts[forbidden]:
            raise DagError(f"IJFS current oracle: stale/forbidden call returned: {forbidden}")
    nodes, edges = analyzer.graph_for(method)
    node_by_id = {node.node_id: node for node in nodes}
    indexed_edges: dict[tuple[str, int, str, int, str], set[str]] = {}
    for edge in edges:
        source = node_by_id[edge.source]
        target = node_by_id[edge.target]
        indexed_edges.setdefault(
            (source.callee, source.line, target.callee, target.line, edge.kind), set()).update(edge.fields)
    for expected_edge in oracle["required_edges"]:
        source_name, source_line = expected_edge["source"]
        target_name, target_line = expected_edge["target"]
        identity = (source_name, source_line, target_name, target_line, expected_edge["kind"])
        actual_fields = indexed_edges.get(identity)
        if actual_fields is None:
            raise DagError(f"IJFS current oracle: required edge missing: {identity}")
        expected_fields = set(expected_edge["fields"])
        if actual_fields != expected_fields:
            raise DagError(
                f"IJFS current oracle: edge {identity} expected exact evidence "
                f"{sorted(expected_fields)}; got {sorted(actual_fields)}")
    for method_key, expected_writes in oracle["required_transition_effects"].items():
        target = analyzer.methods.get(method_key)
        if target is None:
            raise DagError(f"IJFS effect oracle method missing: {method_key}")
        actual_writes = set(target.total.writes)
        expected_write_set = set(expected_writes)
        if actual_writes != expected_write_set:
            raise DagError(
                f"IJFS effect oracle: {method_key} expected exact writes "
                f"{sorted(expected_write_set)}; got {sorted(actual_writes)}")
    return ["current post-plan-0060 IJFS call-site/effect oracle"]


def validate_manifest_reach(analyzer: Analyzer) -> list[str]:
    transition_writes: set[str] = set()
    for method in analyzer.methods.values():
        if method.class_name in analyzer.authority_classes:
            transition_writes.update(field.split("[", 1)[0] for field in method.direct.writes)
    reached = analyzer.protected_fields & transition_writes
    if not reached:
        raise DagError("manifest cross-check found zero protected fields written by authority methods")
    empty_authorities: list[str] = []
    for authority in sorted(analyzer.authority_classes):
        authority_writes = {
            field.split("[", 1)[0]
            for method in analyzer.methods.values() if method.class_name == authority
            for field in method.direct.writes
        }
        if not (authority_writes & analyzer.protected_fields):
            empty_authorities.append(authority)
    if empty_authorities:
        raise DagError(
            f"manifest cross-check found authority classes with zero protected writes: {empty_authorities}")
    # Not every protected field has a runtime writer (identity/construction fields are legitimate), so
    # absence is rendered as dictionary coverage rather than made a false failure.
    return [f"manifest-aware transition scan reached {len(reached)} protected fields across "
            f"{len(analyzer.authority_classes)} authorities"]


def _git(args: list[str], default: str) -> str:
    try:
        return subprocess.check_output(["git", *args], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip() or default
    except (OSError, subprocess.CalledProcessError):
        return default


def _generation_stamp(symbols: dict) -> dict[str, str]:
    tool_digest = hashlib.sha256()
    stamped_paths = [GENERATOR_PATH, EXPORTER_PATH, MANIFEST_PATH, ROOT / "project.godot"]
    stamped_paths.extend(sorted(FIXTURES.glob("*")))
    for path in stamped_paths:
        tool_digest.update(path.relative_to(ROOT).as_posix().encode())
        tool_digest.update(b"\0")
        tool_digest.update(path.read_bytes())
        tool_digest.update(b"\0")
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch:
        generated = dt.datetime.fromtimestamp(int(epoch), tz=dt.timezone.utc).isoformat()
    else:
        generated = _git(["show", "-s", "--format=%cI", "HEAD"], "unknown")
    return {
        "commit": _git(["rev-parse", "--short=12", "HEAD"], "unknown"),
        "source_hash": symbols["source_hash"],
        "tool_hash": tool_digest.hexdigest(),
        "generated": generated,
    }


def _summary_for(path: Path) -> str:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    parts: list[str] = []
    for line in lines[2:40]:
        stripped = line.strip()
        if stripped.startswith("##"):
            parts.append(stripped.lstrip("# "))
        elif parts and stripped.startswith("#"):
            parts.append(stripped.lstrip("# "))
        elif parts and stripped:
            break
    return " ".join(parts) if parts else "No source summary was found; see the access tables below."


def _header(title: str, stamp: dict[str, str], diagnostics: int) -> list[str]:
    return [
        f"# {title}", "",
        "> **Reading aid, not an execution contract.** No detected edge is not permission to reorder.",
        "> GDScript reads and writes are conservative source analysis; transition writes are also",
        "> checked against the mutation manifest. Potential conflicts may refer to different object",
        "> instances or conditional branches.", "",
        f"Generator format v{FORMAT_VERSION}; scan scope `scripts/**/*.gd` plus `project.godot` autoload aliases.",
        f"Generated from commit `{stamp['commit']}`; input SHA-256 `{stamp['source_hash']}`;",
        f"tool/manifest/fixture SHA-256 `{stamp['tool_hash']}`; stable generation time `{stamp['generated']}`.",
        f"Unresolved-analysis diagnostics on this page: **{diagnostics}**.", "",
    ]


def _field_table(reads: set[str], writes: set[str]) -> list[str]:
    rows = ["## Model-field evidence", "", "| Field | Read | Written |", "|---|:---:|:---:|"]
    for field in sorted(reads | writes):
        rows.append(f"| `{field}` | {'yes' if field in reads else ''} | {'yes' if field in writes else ''} |")
    if not (reads or writes):
        rows.append("| _No persistent model field was resolved_ | | |")
    rows.append("")
    return rows


def _display_value(value: str) -> str:
    if value.startswith("derived@"):
        location, _call_start, _argument = value.removeprefix("derived@").rsplit(":", 2)
        return f"derived stream at {location}"
    return value


def _compact_values(values: Iterable[str], limit: int = 10) -> str:
    ordered = sorted(set(values))
    if not ordered:
        return "—"
    visible = ", ".join(f"`{_display_value(item)}`" for item in ordered[:limit])
    if len(ordered) > limit:
        visible += f"; _+{len(ordered) - limit} more_"
    return visible


def _diagnostics_table(diagnostics: Iterable[Diagnostic], limit: int = 30) -> list[str]:
    items = sorted(set(diagnostics), key=lambda d: (d.path, d.line, d.kind, d.method, d.excerpt))
    rows = ["## Analysis limits found here", ""]
    if not items:
        return rows + ["No unresolved constructs were recorded.", ""]
    rows.append(f"Showing {min(limit, len(items))} of {len(items)} diagnostics; class pages provide the narrower context.")
    rows += ["", "| Kind | Source | Why it matters |", "|---|---|---|"]
    explanations = {
        "untyped_alias": "The receiver type could not be proven.",
        "untyped_iteration": "The collection element type could not be proven.",
        "dynamic_dispatch": "A string/dynamic call has no statically known target.",
        "callable_or_lambda": "Callable/lambda dataflow is outside this analyser.",
        "unresolved_receiver": "A protected field name appeared on an unresolved receiver.",
        "callee_body_unresolved": "The declaration exists but its method body was not indexed.",
        "inner_class_unanalysed": "Godot reflected an inner class, but its indented method bodies are not analysed.",
        "source_effect_contradiction": "Source prose claims purity while the resolved call closure reaches protected writes.",
        "multi_call_statement": "Multiple calls share one statement; the map preserves lexical sites, not nested evaluation order.",
        "nested_index_unanalysed": "Nested collection indexes exceed the balanced-chain subset; this statement contributes no field effects.",
    }
    for diagnostic in items[:limit]:
        excerpt = diagnostic.excerpt.strip()
        if len(excerpt) > 180:
            excerpt = excerpt[:177] + "…"
        source = f"`{diagnostic.path}:{diagnostic.line}` `{excerpt}`"
        rows.append(f"| `{diagnostic.kind}` | {source} | {explanations.get(diagnostic.kind, 'Conservative static analysis stopped here.')} |")
    if len(items) > limit:
        rows.append(f"| _…_ | _{len(items) - limit} additional diagnostics omitted from this page_ | See the called class pages. |")
    rows.append("")
    return rows


def _mermaid_id(value: str) -> str:
    return "n_" + hashlib.sha1(value.encode()).hexdigest()[:12]


def _ordering_filename(method_key: str) -> str:
    class_name, method_name = method_key.rsplit(".", 1)
    return f"ordering_{class_name}_{method_name}.md"


def _linked_call(value: str, analyzer: Analyzer) -> str:
    ordering_keys = {method.key for method in analyzer.ordering_methods()}
    if value in ordering_keys:
        return f"[`{value}`]({_ordering_filename(value)})"
    if value == "GameDataStore.recompute_hex_ownership":
        return "[`GameDataStore.recompute_hex_ownership`](../systems/turn-engine/turn-engine.md#4-resolve_turn-stage-order-turnconductorgd)"
    class_name = value.split(".", 1)[0]
    cls = analyzer.classes.get(class_name)
    if cls:
        parts = Path(cls.path).parts
        if ((len(parts) >= 2 and parts[0] == "scripts" and parts[1] in RENDER_DIRS) or
                class_name in analyzer.coordinator_classes):
            return f"[`{value}`]({class_name}.md)"
    return f"`{value}`"


def render_ordering_page(method: MethodInfo, analyzer: Analyzer, stamp: dict[str, str]) -> str:
    nodes, edges = analyzer.graph_for(method)
    diagnostics = set(method.total.diagnostics)
    for node in nodes:
        diagnostics.update(node.node_effect.diagnostics)
    lines = _header(f"Ordering: `{method.key}`", stamp, len(diagnostics))
    lines += [f"Source: `{method.path}:{method.line}`", "",
              "## Lexical call-site map (CALL edges)", "",
              "> Source order is not an execution count: loop calls repeat, branch calls may be skipped",
              "> or mutually exclusive, and nested arguments execute before their outer call.", "",
              "```mermaid", "flowchart TD"]
    for index, node in enumerate(nodes, 1):
        label = f"{index}. {node.callee} (line {node.line})".replace('"', "'")
        lines.append(f"  {_mermaid_id(node.node_id)}[\"{label}\"]")
    for edge in edges:
        if edge.kind == "CALL":
            lines.append(f"  {_mermaid_id(edge.source)} -->|CALL| {_mermaid_id(edge.target)}")
    if not nodes:
        lines.append("  empty[\"No analysed call sites\"]")
    lines += ["```", "", "## State and RNG constraints", "",
              "| Earlier node | Later node | Kinds | Shared evidence |", "|---|---|---|---|"]
    grouped: dict[tuple[str, str], dict[str, set[str]]] = {}
    for edge in edges:
        if edge.kind == "CALL":
            continue
        row = grouped.setdefault((edge.source, edge.target), {"kinds": set(), "fields": set()})
        row["kinds"].add(edge.kind)
        row["fields"].update(edge.fields)
    node_by_id = {node.node_id: node for node in nodes}
    for (source, target), row in sorted(grouped.items()):
        left = node_by_id[source]
        right = node_by_id[target]
        fields = _compact_values(row["fields"], 8)
        kinds = ", ".join(f"**{kind}**" for kind in sorted(row["kinds"]))
        lines.append(f"| `{left.callee}` (L{left.line}) | `{right.callee}` (L{right.line}) | {kinds} | {fields} |")
    if not grouped:
        lines.append("| _No constraint edge resolved_ | | | This is not evidence that calls are reorderable. |")
    visual_edges = [
        edge for edge in edges
        if edge.kind in {"RAW", "WAR", "WAW", "RNG"} and (
            edge.kind == "RNG" or any(
                field.split("[", 1)[0] in analyzer.protected_fields for field in edge.fields))
    ]
    visual_edges.sort(key=lambda edge: (
        nodes.index(node_by_id[edge.source]), nodes.index(node_by_id[edge.target]), edge.kind))
    visible_edges = visual_edges[:40]
    lines += ["", "## Detected campaign-state/RNG overview", "",
              "This compact diagram shows up to 40 detected RAW/WAR/WAW/RNG constraints involving protected",
              "campaign fields. The table above remains the complete conservative evidence.", "",
              "```mermaid", "flowchart LR"]
    visible_node_ids = {edge.source for edge in visible_edges} | {edge.target for edge in visible_edges}
    for node in nodes:
        if node.node_id in visible_node_ids:
            lines.append(f"  {_mermaid_id(node.node_id)}[\"{node.callee} L{node.line}\"]")
    for edge in visible_edges:
        lines.append(
            f"  {_mermaid_id(edge.source)} -->|{edge.kind}| {_mermaid_id(edge.target)}")
    if not visible_edges:
        lines.append("  empty[\"No protected-state/RNG edge resolved\"]")
    lines += ["```"]
    if len(visual_edges) > len(visible_edges):
        lines += ["", f"_{len(visual_edges) - len(visible_edges)} additional visual edges are kept in the table above._"]
    lines += ["", "## Call-site detail", "",
              "Effects include the called method and every statically resolved helper beneath it.", "",
              "| # | Call site | Reads | Writes | RNG streams |", "|---:|---|---|---|---|"]
    for index, node in enumerate(nodes, 1):
        reads = _compact_values(node.node_effect.reads)
        writes = _compact_values(node.node_effect.writes)
        rng = _compact_values(node.node_effect.rng_streams)
        lines.append(f"| {index} | `{node.callee}` at `{method.path}:{node.line}` | {reads} | {writes} | {rng} |")
    lines.append("")
    lines += _diagnostics_table(diagnostics)
    return "\n".join(lines).rstrip() + "\n"


def render_class_page(cls: ClassInfo, analyzer: Analyzer, stamp: dict[str, str]) -> str:
    methods = [method for method in analyzer.methods.values() if method.class_name == cls.name]
    reads: set[str] = set()
    writes: set[str] = set()
    diagnostics: set[Diagnostic] = set(analyzer.class_diagnostics.get(cls.name, set()))
    for method in methods:
        reads.update(method.total.reads)
        writes.update(method.total.writes)
        diagnostics.update(method.total.diagnostics)
    summary = _summary_for(ROOT / cls.path)
    protected_writes = sorted(
        field for field in writes if field.split("[", 1)[0] in analyzer.protected_fields)
    purity_claim = re.search(
        r"\b(mutates nothing|changes no campaign state|applies no campaign state|pure\s+[—-])",
        summary, re.IGNORECASE)
    if purity_claim and protected_writes:
        diagnostics.add(Diagnostic(
            "source_effect_contradiction", cls.path, cls.name, 0,
            f"source says '{purity_claim.group(1)}' but analysis found {', '.join(protected_writes)}"))
    placements: list[CallSite] = []
    for caller in analyzer.methods.values():
        placements.extend(site for site in caller.callsites if site.callee.startswith(cls.name + "."))
    lines = _header(cls.name, stamp, len(diagnostics))
    if purity_claim and protected_writes:
        lines += ["## Computed effect warning", "",
                  "The source summary claims this class is pure, but the generated call closure reaches",
                  f"protected writes: {_compact_values(protected_writes)}. Treat the computed evidence and",
                  "visible uncertainty as the safer reading; the source claim needs a separate fix.", ""]
    lines += ["## Source summary", "", summary, "", f"Source: `{cls.path}`", "",
              "## Placement in resolution code", ""]
    if placements:
        lines += ["| Caller | Call-site instance |", "|---|---|"]
        for site in sorted(placements, key=lambda s: (s.caller, s.line, s.ordinal)):
            lines.append(f"| {_linked_call(site.caller, analyzer)} | `{site.callee}` at `{site.line}` |")
    else:
        lines.append("No analysed calculator/coordinator call site reaches this class directly.")
    lines.append("")
    callers = sorted({site.caller for site in placements})
    callees = sorted({call for method in methods for call in method.direct.calls})
    class_node = _mermaid_id("class:" + cls.name)
    lines += ["## Dependency diagram", "", "```mermaid", "flowchart LR", f"  {class_node}[\"{cls.name}\"]"]
    for caller in callers:
        caller_node = _mermaid_id("caller:" + caller)
        lines.append(f"  {caller_node}[\"{caller}\"] --> {class_node}")
    for callee in callees:
        callee_node = _mermaid_id("callee:" + callee)
        lines.append(f"  {class_node} --> {callee_node}[\"{callee}\"]")
    if not callers and not callees:
        lines.append(f"  {class_node}")
    lines += ["```", ""]
    if any(d.kind == "inner_class_unanalysed" for d in diagnostics):
        lines += ["## Inner-class boundary", "",
                  "This outer script's budgets are implemented as inner classes. Godot reflects their",
                  "signatures but exposes no body AST, so their class-level effect table is intentionally",
                  "incomplete. Follow the linked Placement rows to inspect effects at each call site.", ""]
    lines += _field_table(reads, writes)
    lines += ["## Method dependencies", "", "| Method | Calls (transitive effects are included above) |", "|---|---|"]
    for method in sorted(methods, key=lambda m: m.name):
        calls = ", ".join(f"`{call}`" for call in sorted(method.direct.calls)) or "—"
        lines.append(f"| `{method.name}` | {calls} |")
    lines.append("")
    lines += _diagnostics_table(diagnostics)
    return "\n".join(lines).rstrip() + "\n"


def render_transition_dictionary(analyzer: Analyzer, stamp: dict[str, str]) -> str:
    methods = [method for method in analyzer.methods.values()
               if method.class_name in analyzer.authority_classes and any(
                   field.split("[", 1)[0] in analyzer.protected_fields for field in method.total.writes)]
    diagnostics = set().union(*(method.total.diagnostics for method in methods)) if methods else set()
    lines = _header("State transition dictionary", stamp, len(diagnostics))
    lines += ["This is a generated view of transition-method effects. Ownership remains authoritative only in",
              "`tools/mutation_authority_manifest.json`.", "", "| Transition method | Model fields it may write |", "|---|---|"]
    for method in sorted(methods, key=lambda m: m.key):
        protected_writes = sorted(field for field in method.total.writes
                                  if field.split("[", 1)[0] in analyzer.protected_fields)
        fields = ", ".join(f"`{field}`" for field in protected_writes)
        lines.append(f"| `{method.key}` | {fields} |")
    lines.append("")
    lines += _diagnostics_table(diagnostics)
    return "\n".join(lines).rstrip() + "\n"


def render_turn_pipeline(analyzer: Analyzer, stamp: dict[str, str]) -> str:
    method = analyzer.methods.get("TurnConductor.resolve_turn")
    if method is None:
        raise DagError("TurnConductor.resolve_turn was not indexed")
    all_nodes, _all_edges = analyzer.graph_for(method)
    nodes = [node for node in all_nodes if (
        node.callee.startswith(("FiresPhases.", "ReinforcementPhases.", "TurnClosure.")) or
        node.callee in {
            "TurnConductor.apply_move_orders", "TurnConductor.resolve_combat_at",
            "TurnConductor.apply_feba_retreats", "GameDataStore.recompute_hex_ownership"})]
    diagnostics = set(method.direct.diagnostics)
    lines = _header("Turn resolution pipeline", stamp, len(diagnostics))
    lines += ["This page is the high-level lexical call-site map. Loop calls repeat; conditional calls may",
              "be skipped. Open linked ordering/class pages to zoom in, or use the",
              "[state transition dictionary](state_transitions.md) to look up mutation verbs.", "",
              "```mermaid", "flowchart TD"]
    for index, node in enumerate(nodes, 1):
        lines.append(f"  {_mermaid_id(node.node_id)}[\"{index}. {node.callee}\"]")
    for source, target in zip(nodes, nodes[1:]):
        lines.append(f"  {_mermaid_id(source.node_id)} --> {_mermaid_id(target.node_id)}")
    lines += ["```", "", "## Ordered call sites", "", "| # | Call | Source |", "|---:|---|---|"]
    for index, node in enumerate(nodes, 1):
        lines.append(f"| {index} | {_linked_call(node.callee, analyzer)} | `{method.path}:{node.line}` |")
    lines += ["", "Lifecycle guards, RNG construction, combat-loop snapshots, and debug-only tripwires are",
              "kept out of this designer overview. The detailed lexical view retains them:",
              "[`ordering_TurnConductor_resolve_turn.md`](ordering_TurnConductor_resolve_turn.md).", "",
              "Transitive uncertainty is reported on the linked phase/class pages; this page's count is",
              "limited to the conductor's own source statements.", ""]
    lines += _diagnostics_table(diagnostics)
    return "\n".join(lines).rstrip() + "\n"


def write_presentations(analyzer: Analyzer, symbols: dict) -> list[Path]:
    stamp = _generation_stamp(symbols)
    PRESENTATIONS.mkdir(parents=True, exist_ok=True)
    expected: dict[Path, str] = {}
    for cls in sorted(analyzer.classes.values(), key=lambda item: item.name):
        parts = Path(cls.path).parts
        if len(parts) >= 2 and parts[0] == "scripts" and parts[1] in RENDER_DIRS:
            expected[PRESENTATIONS / f"{cls.name}.md"] = render_class_page(cls, analyzer, stamp)
        elif cls.name in analyzer.coordinator_classes:
            expected[PRESENTATIONS / f"{cls.name}.md"] = render_class_page(cls, analyzer, stamp)
    for method in analyzer.ordering_methods():
        filename = _ordering_filename(method.key)
        expected[PRESENTATIONS / filename] = render_ordering_page(method, analyzer, stamp)
    expected[PRESENTATIONS / "turn_pipeline.md"] = render_turn_pipeline(analyzer, stamp)
    expected[PRESENTATIONS / "state_transitions.md"] = render_transition_dictionary(analyzer, stamp)

    generated_names = {path.name for path in expected}
    for existing in PRESENTATIONS.glob("*.md"):
        if existing.name not in generated_names and _is_generated(existing):
            existing.unlink()
    for path, content in sorted(expected.items(), key=lambda item: item[0].name):
        path.write_text(content, encoding="utf-8")
    return sorted(expected)


def _is_generated(path: Path) -> bool:
    try:
        return "Reading aid, not an execution contract" in path.read_text(encoding="utf-8")[:500]
    except OSError:
        return False


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate", action="store_true",
                        help="explicit contract flag (current-tree validation always runs before rendering)")
    parser.add_argument("--self-test", action="store_true", help="run source-analysis fixtures without rendering")
    parser.add_argument("--no-render", action="store_true", help="analyse/validate but do not write Markdown")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="Godot executable")
    args = parser.parse_args(argv)
    try:
        self_test_results = run_self_tests()
        if args.self_test and not args.validate:
            for result in self_test_results:
                print(f"PASS: resolution DAG self-test — {result}")
            return 0
        build_dir = ROOT / "build"
        build_dir.mkdir(exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix="resolution_symbols_", suffix=".json", dir=build_dir,
                                         delete=False) as handle:
            symbol_path = Path(handle.name)
        try:
            symbols = export_symbols(symbol_path, args.godot)
            analyzer = Analyzer(symbols, manifest=_load_manifest())
            validation_results = list(self_test_results)
            validation_results += validate_current_ijfs(analyzer)
            validation_results += validate_manifest_reach(analyzer)
            paths = [] if args.no_render else write_presentations(analyzer, symbols)
        finally:
            symbol_path.unlink(missing_ok=True)
        for result in validation_results:
            print(f"PASS: resolution DAG validation — {result}")
        print(f"PASS: resolution DAG generated — {len(paths)} page(s); {len(analyzer.methods)} methods; "
              f"{sum(len(m.callsites) for m in analyzer.methods.values())} call-site nodes")
        return 0
    except (DagError, OSError, subprocess.SubprocessError, ValueError) as exc:
        print(f"FAIL: resolution DAG — {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
