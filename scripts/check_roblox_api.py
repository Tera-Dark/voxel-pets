#!/usr/bin/env python3
"""Static Roblox API checker for code the Luau type checker cannot see.

Our UI is built through prop-table helpers (C.label({ Text = ... })), so a misspelled or
non-scriptable property only explodes at runtime inside Roblox. This script validates, against
the real Roblox API dump (vendored, trimmed):

  * keys of prop tables passed to known constructors (C.new/C.frame/C.label/... and part())
  * `x.Prop = value` assignments where `x` was created by a known constructor in the same file
  * Enum.<Enum>.<Item> references
  * game:GetService("Name") names and Instance.new("Class") class names

Usage:
  python3 scripts/check_roblox_api.py                 # check src/ (exit 1 on findings)
  python3 scripts/check_roblox_api.py --build DUMP    # rebuild tools/data/roblox_api.json from a
                                                      # full API-Dump.json (Roblox-Client-Tracker)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tools", "data", "roblox_api.json")
SKIP_DIRS = ("src/server/Vendor",)

# helper name -> class. "C.new" is special (class from the first string argument).
HELPERS = {
    "C.frame": "Frame",
    "C.panel": "Frame",
    "C.bar": "Frame",
    "C.label": "TextLabel",
    "C.button": "TextButton",
    "C.scroll": "ScrollingFrame",
}
# file-local prop helpers: path suffix -> {function name: class}
LOCAL_HELPERS = {
    "src/server/World/WorldBuilder.luau": {"part": "Part"},
}


# ------------------------------------------------------------------ API data
def build(dump_path):
    dump = json.load(open(dump_path, encoding="utf-8"))
    classes = {}
    for c in dump["Classes"]:
        props, ptypes, events, methods = {}, {}, [], []
        for m in c["Members"]:
            tags = m.get("Tags") or []
            if m["MemberType"] == "Property":
                vt = m.get("ValueType") or {}
                cat, vname = vt.get("Category"), vt.get("Name", "")
                ptypes[m["Name"]] = f"{cat}:{vname}" if cat in ("Enum", "Class") else vname
                sec = m.get("Security") or {}
                write = sec.get("Write", "None") if isinstance(sec, dict) else sec
                writable = (
                    "ReadOnly" not in tags and "NotScriptable" not in tags and write == "None"
                )
                code = "w" if writable else "r"
                if "Deprecated" in tags:
                    code += "D"
                props[m["Name"]] = code
            elif m["MemberType"] == "Callback":
                props[m["Name"]] = "w"  # assignable (e.g. RemoteFunction.OnServerInvoke)
                ptypes[m["Name"]] = "Callback"
            elif m["MemberType"] == "Event":
                events.append(m["Name"])
            else:
                methods.append(m["Name"])
        classes[c["Name"]] = {
            "super": c.get("Superclass"),
            "tags": [t for t in (c.get("Tags") or []) if isinstance(t, str)],
            "props": props,
            "ptypes": ptypes,
            "events": events,
            "methods": methods,
        }
    enums = {e["Name"]: [i["Name"] for i in e["Items"]] for e in dump["Enums"]}
    version = dump.get("Version")
    os.makedirs(os.path.dirname(DATA), exist_ok=True)
    with open(DATA, "w", encoding="utf-8") as f:
        json.dump(
            {"dumpVersion": version, "classes": classes, "enums": enums},
            f,
            separators=(",", ":"),
            sort_keys=True,
        )
    print(f"wrote {DATA} ({os.path.getsize(DATA) // 1024} KB, {len(classes)} classes)")


STATS = {"calls": 0, "keys": 0}


class Api:
    def __init__(self, data):
        self.classes = data["classes"]
        self.enums = {k: set(v) for k, v in data["enums"].items()}
        self._props = {}

    def props(self, cls):
        if cls not in self._props:
            out, name = {}, cls
            while name and name in self.classes:
                for k, v in self.classes[name]["props"].items():
                    out.setdefault(k, v)
                name = self.classes[name]["super"]
            self._props[cls] = out
        return self._props[cls]


# ------------------------------------------------------------------ tokenizer
TOKEN_RE = re.compile(
    r"""
    (?P<comment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\]|--[^\n]*)
  | (?P<lstr>\[(?P<leq>=*)\[.*?\](?P=leq)\])
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<num>0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)
  | (?P<op>==|~=|<=|>=|\.\.\.|\.\.|::|->|[-+*/%^#=<>(){}\[\];:,.])
  | (?P<ws>\s+)
  | (?P<other>.)
    """,
    re.S | re.X,
)


def tokenize(src):
    toks, line = [], 1
    for m in TOKEN_RE.finditer(src):
        kind = m.lastgroup
        text = m.group(0)
        if kind in ("comment", "ws"):
            line += text.count("\n")
            continue
        if kind in ("ceq", "leq"):
            kind = "lstr"
        toks.append((kind, text, line))
        line += text.count("\n")
    return toks


def matching(toks, i):
    """index of the bracket closing toks[i]."""
    pairs = {"(": ")", "{": "}", "[": "]"}
    open_, close = toks[i][1], pairs[toks[i][1]]
    depth = 0
    for j in range(i, len(toks)):
        t = toks[j][1]
        if toks[j][0] == "op":
            if t == open_:
                depth += 1
            elif t == close:
                depth -= 1
                if depth == 0:
                    return j
    return len(toks) - 1


def table_keys(toks, i):
    """top-level `Key =` / `["Key"] =` entries of the table starting at toks[i] == '{'."""
    end = matching(toks, i)
    keys, depth, j = [], 0, i
    while j <= end:
        kind, text, line = toks[j]
        if kind == "op" and text in "({[":
            if depth == 1 and text == "[" and j + 3 <= end and toks[j + 1][0] == "str":
                if toks[j + 2][1] == "]" and toks[j + 3][1] == "=":
                    keys.append((toks[j + 1][1][1:-1], toks[j + 1][2]))
            depth += 1
        elif kind == "op" and text in ")}]":
            depth -= 1
        elif depth == 1 and kind == "name" and j + 1 <= end and toks[j + 1][1] == "=":
            prev = toks[j - 1][1]
            if prev in ("{", ",", ";"):
                keys.append((text, line))
        j += 1
    return keys


def dotted_at(toks, i):
    """('C.label', next_index) for NAME . NAME sequences starting at i."""
    if toks[i][0] != "name":
        return None, i
    parts, j = [toks[i][1]], i + 1
    while j + 1 < len(toks) and toks[j][1] == "." and toks[j + 1][0] == "name":
        parts.append(toks[j + 1][1])
        j += 2
    return ".".join(parts), j


# ------------------------------------------------------------------ checks
def check_file(api, path, rel, findings):
    src = open(path, encoding="utf-8").read()
    toks = tokenize(src)
    helpers = dict(HELPERS)
    for suffix, extra in LOCAL_HELPERS.items():
        if rel.endswith(suffix):
            helpers.update(extra)

    def report(line, msg):
        findings.append(f"{rel}:{line}: {msg}")

    def check_key(cls, key, line, how):
        STATS["keys"] += 1
        props = api.props(cls)
        if key == "Parent":
            return
        code = props.get(key)
        if code is None:
            report(line, f"'{key}' is not a property of {cls} ({how})")
        elif code.startswith("r"):
            report(line, f"'{key}' on {cls} is read-only / not scriptable ({how})")
        elif "D" in code:
            report(line, f"'{key}' on {cls} is deprecated ({how})")

    var_class = []  # (tokenIndex, name, class) from `local x = <constructor>(`
    n = len(toks)
    i = 0
    while i < n:
        kind, text, line = toks[i]
        # Enum.X.Y
        if kind == "name" and text == "Enum" and (i == 0 or toks[i - 1][1] != "."):
            name, j = dotted_at(toks, i)
            parts = name.split(".")
            if len(parts) >= 3:
                enum, item = parts[1], parts[2]
                if enum not in api.enums:
                    report(line, f"unknown enum Enum.{enum}")
                elif item not in api.enums[enum] and item not in ("GetEnumItems", "FromName", "FromValue"):
                    report(line, f"Enum.{enum} has no item '{item}'")
        # :GetService("X")
        if kind == "name" and text == "GetService" and i + 2 < n and toks[i + 1][1] == "(":
            if toks[i + 2][0] == "str":
                svc = toks[i + 2][1][1:-1]
                c = api.classes.get(svc)
                if not c or "Service" not in c["tags"]:
                    report(line, f"GetService('{svc}') is not a known service")
        # constructor calls
        name, j = dotted_at(toks, i)
        if name and j < n and toks[j][1] == "(" and (i == 0 or toks[i - 1][1] not in (".", ":")):
            cls, table_at = None, None
            if name in ("C.new", "Instance.new") and j + 1 < n and toks[j + 1][0] == "str":
                cls = toks[j + 1][1][1:-1]
                if cls not in api.classes:
                    report(line, f"{name}('{cls}'): unknown class")
                    cls = None
                elif "NotCreatable" in api.classes[cls]["tags"]:
                    report(line, f"{name}('{cls}'): class is not creatable")
                if name == "C.new" and j + 3 < n and toks[j + 2][1] == "," and toks[j + 3][1] == "{":
                    table_at = j + 3
            elif name in helpers:
                cls = helpers[name]
                if j + 1 < n and toks[j + 1][1] == "{":
                    table_at = j + 1
            if cls:
                STATS["calls"] += 1
            if cls and table_at is not None:
                for key, kline in table_keys(toks, table_at):
                    check_key(cls, key, kline, f"{name} props")
            if cls and i >= 2 and toks[i - 1][1] == "=" and toks[i - 2][0] == "name":
                if i >= 3 and toks[i - 3][1] == "local":
                    var_class.append((i, toks[i - 2][1], cls))
        i += 1

    # x.Prop = value, where x was bound by `local x = <constructor>(...)` earlier in the file
    for k in range(n - 3):
        if toks[k][0] == "name" and toks[k + 1][1] == "." and toks[k + 2][0] == "name":
            if toks[k + 3][1] != "=" or (k > 0 and toks[k - 1][1] in (".", ":", "local")):
                continue
            var, prop, line = toks[k][1], toks[k + 2][1], toks[k + 2][2]
            binding = None
            for idx, vname, cls in var_class:
                if idx < k and vname == var:
                    binding = cls
            if binding:
                check_key(binding, prop, line, f"assignment to {var}")


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--build":
        build(sys.argv[2])
        return 0
    api = Api(json.load(open(DATA, encoding="utf-8")))
    findings, files = [], 0
    for base, _, names in os.walk(os.path.join(ROOT, "src")):
        for fname in sorted(names):
            if not fname.endswith(".luau"):
                continue
            path = os.path.join(base, fname)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            if rel.startswith(SKIP_DIRS):
                continue
            files += 1
            check_file(api, path, rel, findings)
    for f in findings:
        print(f)
    print(
        f"\ncheck_roblox_api: {files} files, {STATS['calls']} constructor calls, "
        f"{STATS['keys']} property keys checked, {len(findings)} findings"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
