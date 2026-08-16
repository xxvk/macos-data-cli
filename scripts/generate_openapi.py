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

from openapi_errors import CONTRACT_VERSION, error_example

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


def method_for(leaf):
    """Map a CLI command to the closest HTTP method (documentation-only).

    Read-only commands are GET, except action verbs (run/reveal) that execute
    or activate but do not mutate macOS data — those are POST. Mutating
    commands follow their verb: delete/forget -> DELETE, full replace
    (edit-body/replace) -> PUT, partial edit (edit/rename/move) -> PATCH, and
    everything else (create/add/complete/reopen/migrate/bind/clear) -> POST.
    """
    name = (leaf.get("name") or "").lower()
    # Capability/discovery/verification checks map to OPTIONS.
    if "permission" in name or "doctor" in name or "verify" in name or name in ("resources", "containers", "sources"):
        return "options"
    # Scalar/selection metadata maps to HEAD ("just the summary, not the data").
    if name in ("count", "container"):
        return "head"
    # Actions that materialize an output artifact (export) or execute (run/reveal).
    if "export" in name or "run" in name or "reveal" in name:
        return "post"
    if not leaf.get("mutates"):
        return "get"
    if "delete" in name or "forget" in name:
        return "delete"
    if "edit-body" in name or "replace" in name:
        return "put"
    if "edit" in name or "rename" in name or "move" in name:
        return "patch"
    return "post"


_EXIT_TO_HTTP = {
    0: 200,
    1: 500,   # CLI_ERROR
    2: 400,   # CONTACTS_ERROR (permission/input)
    3: 404,   # CONTACT_QUERY_ERROR (lookup)
    4: 500,   # MAIL_ERROR
    5: 500,   # CALENDAR_ERROR
    6: 500,   # REMINDERS_ERROR
    7: 500,   # PHOTOS_ERROR
    8: 500,   # NOTES_ERROR
    9: 500,   # SHORTCUTS_ERROR
    10: 500,  # SAFARI_ERROR
    64: 400,  # INVALID_QUERY (usage)
}

_HTTP_REASONS = {
    400: "Bad Request",
    404: "Not Found",
    500: "Internal Server Error",
}


def cli_example(command, leaf):
    """Append representative safety flags so the CLI example shows real usage.

    Destructive commands show `--apply --confirm "<phrase>"` (flag + quoted
    value); other write commands show `--apply`; read-only commands keep the
    bare command. This drives the colorized `CLI example:` line in the docs.
    """
    safety = leaf.get("safety") or {}
    confirmation = safety.get("confirmation")
    if confirmation:
        return f'{command} --apply --confirm "{confirmation}"'
    if safety.get("apply"):
        return f"{command} --apply"
    return command


def leaf_operation(leaf, tag=None, command="", title="", group="", leaf_name="", number=None):
    command = cli_example(command, leaf)
    method = method_for(leaf)
    summary = f"{number} {title}" if number else title
    op = {
        "summary": summary,
        "description": leaf.get("description", ""),
        "parameters": [param_to_openapi(p) for p in (leaf.get("params") or [])],
        "responses": {
            "200": {
                "description": "Success envelope (ok=true, contractVersion, data).",
                "content": {"application/json": {"schema": {"$ref": "#/components/schemas/SuccessEnvelope"}}},
            }
        },
        "x-safety": leaf.get("safety") or {},
        "x-exit-codes": leaf.get("exitCodes") or [],
        "x-cli-command": command,
        "x-group": group,
        "x-leaf": leaf_name,
    }
    for exit_spec in (leaf.get("exitCodes") or []):
        exit_code = exit_spec.get("code", 0)
        http_code = _EXIT_TO_HTTP.get(exit_code, 500)
        reason = _HTTP_REASONS.get(http_code, "Error")
        error_code = exit_spec.get("errorCode", "ERROR")
        op["responses"][str(http_code)] = {
            "description": f"{error_code} — {exit_spec.get('description', '')} ({reason})",
            "content": {
                "application/json": {
                    "schema": {"$ref": "#/components/schemas/ErrorEnvelope"},
                    "example": error_example(error_code),
                }
            },
        }
    if tag:
        op["tags"] = [tag]
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


def _tag_name(cmd, index):
    return f"{index}. {cmd.get('name', '')}"


def build_paths(commands):
    paths = {}
    for index, cmd in enumerate(commands, start=0):
        tag = _tag_name(cmd, index)
        name = cmd.get("name", "")
        if cmd.get("kind") == "leaf":
            command = f"mpia {name}"
            number = f"{index}.1"
            paths["/" + name] = leaf_operation(cmd, tag=tag, command=command, title=name, group=name, leaf_name=name, number=number)
        elif cmd.get("kind") == "group":
            for sub_index, leaf in enumerate(cmd.get("subcommands") or [], start=1):
                if leaf.get("kind") != "leaf":
                    continue
                leaf_name = leaf.get("name", "")
                command = f"mpia {name} {leaf_name}"
                title = f"{name} {leaf_name}"
                number = f"{index}.{sub_index}"
                path = "/" + name + "/" + leaf_name.replace(" ", "/")
                paths[path] = leaf_operation(leaf, tag=tag, command=command, title=title, group=name, leaf_name=leaf_name, number=number)
    return paths


def build_tags(commands):
    return [
        {"name": _tag_name(cmd, index), "description": cmd.get("description", "")}
        for index, cmd in enumerate(commands, start=0)
    ]


def build_components(source_schemas):
    schemas = rewrite_refs(source_schemas)
    schemas["SuccessEnvelope"] = {
        "type": "object",
        "description": "Success response envelope (ok=true, contractVersion, data).",
        "properties": {
            "ok": {"type": "boolean", "const": True},
            "contractVersion": {"type": "string"},
            "data": {},
        },
        "required": ["ok", "contractVersion"],
        "example": {
            "ok": True,
            "contractVersion": CONTRACT_VERSION,
            "data": {},
        },
    }
    schemas["ErrorEnvelope"] = {
        "type": "object",
        "description": "Error response envelope (ok=false, error.code, error.message).",
        "properties": {
            "ok": {"type": "boolean", "const": False},
            "contractVersion": {"type": "string"},
            "error": {
                "type": "object",
                "properties": {
                    "code": {"type": "string", "description": "Stable error code (e.g. CONTACTS_ERROR)."},
                    "message": {"type": "string", "description": "Human-readable error message."},
                },
                "required": ["code"],
            },
        },
        "required": ["ok", "error"],
        "example": error_example("ERROR"),
    }
    return schemas


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
                "Paths mirror the CLI command tree (CLI-faithful) with slash-separated "
                "subcommands; query parameters are CLI flags.\n\n"
                "HTTP methods are a semantic mapping:\n"
                "- OPTIONS for permission/discovery/verification\n"
                "- HEAD for scalar metadata\n"
                "- GET for reads\n"
                "- POST for create/execute/export\n"
                "- PUT for full replace\n"
                "- PATCH for partial edit\n"
                "- DELETE for removal\n\n"
                "Write-safety (dry-run/apply/confirmation) and exit codes "
                "are preserved as x-* extensions."
            ),
        },
        "paths": build_paths(inner.get("commands", [])),
        "tags": build_tags(inner.get("commands", [])),
        "components": {"schemas": build_components(inner.get("schemas", {}))},
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
