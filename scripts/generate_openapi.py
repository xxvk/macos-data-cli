#!/usr/bin/env python3
"""Generate an OpenAPI 3.1 document from the mpia command manifest.

This is a documentation-only mapping: a CLI subcommand becomes a path, and
flags become query parameters. It is NOT a real HTTP API and must not be used
to drive HTTP requests. Feed the manifest JSON on stdin (from
`mpia manifest --format json`) and write the OpenAPI document to
`docs/openapi.json` (or stdout when no path is given).

Usage:
  mpia manifest --format json | python3 scripts/generate_openapi.py docs/openapi.json
"""

import json
import sys

_TYPE_MAP = {
    "string": "string",
    "int": "integer",
    "bool": "boolean",
    "file": "string",
    "json": "object",
}


def rewrite_refs(node):
    """Rewrite local `$ref` values ("Name") to component references."""
    if isinstance(node, dict):
        out = {}
        for key, value in node.items():
            if key == "$ref" and isinstance(value, str) and not value.startswith("#"):
                out[key] = "#/components/schemas/" + value
            else:
                out[key] = rewrite_refs(value)
        return out
    if isinstance(node, list):
        return [rewrite_refs(item) for item in node]
    return node


def param_to_openapi(param):
    schema_type = _TYPE_MAP.get(param.get("type", "string"), "string")
    spec = {
        "name": param.get("name", ""),
        "in": "query",
        "description": param.get("description", ""),
        "schema": {"type": schema_type},
    }
    if param.get("required"):
        spec["required"] = True
    return spec


def leaf_operation(leaf):
    method = "post" if leaf.get("mutates") else "get"
    op = {
        "summary": leaf.get("name", ""),
        "description": leaf.get("description", ""),
        "parameters": [param_to_openapi(p) for p in (leaf.get("params") or [])],
        "responses": {
            "200": {
                "description": "Success envelope (ok=true, contractVersion, data).",
                "content": {"application/json": {"schema": {"type": "object"}}},
            }
        },
        "x-safety": leaf.get("safety") or {},
        "x-exit-codes": leaf.get("exitCodes") or [],
    }
    output = leaf.get("outputSchema")
    if output:
        op["responses"]["200"]["content"]["application/json"]["schema"] = {
            "$ref": "#/components/schemas/" + output
        }
    inp = leaf.get("inputSchema")
    if inp:
        op["requestBody"] = {
            "required": True,
            "content": {
                "application/json": {"schema": {"$ref": "#/components/schemas/" + inp}}
            },
        }
    return {method: op}


def build_paths(commands):
    paths = {}
    for cmd in commands:
        if cmd.get("kind") == "leaf":
            paths["/" + cmd.get("name", "")] = leaf_operation(cmd)
        elif cmd.get("kind") == "group":
            for leaf in (cmd.get("subcommands") or []):
                if leaf.get("kind") != "leaf":
                    continue
                path = "/" + cmd.get("name", "") + "/" + leaf.get("name", "")
                paths[path] = leaf_operation(leaf)
    return paths


def main():
    data = json.load(sys.stdin)
    inner = data.get("data", data)
    cli = inner.get("cli", {})
    doc = {
        "openapi": "3.1.0",
        "info": {
            "title": "mpia",
            "version": cli.get("version", ""),
            "description": (
                "Documentation-only OpenAPI view of the mpia macOS data CLI. "
                "Paths are CLI subcommands, not HTTP routes; query parameters are "
                "CLI flags. Write-safety (dry-run/apply/confirmation) and exit codes "
                "are preserved as x-* extensions."
            ),
        },
        "paths": build_paths(inner.get("commands", [])),
        "components": {"schemas": rewrite_refs(inner.get("schemas", {}))},
    }
    text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w", encoding="utf-8") as fh:
            fh.write(text)
        print("wrote", sys.argv[1])
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
