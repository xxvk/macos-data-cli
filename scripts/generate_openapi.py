#!/usr/bin/env python3
"""Generate the executable REST-style mpia CLI contract as OpenAPI 3.1.

The paths and methods are executable by the local CLI; this is not a network
HTTP service. Feed the manifest JSON on stdin (from
`mpia GET "/agent/manifest"`) and write the OpenAPI document to
`docs/openapi.json` (or stdout when no path is given).

Usage:
  mpia GET "/agent/manifest" | python3 scripts/generate_openapi.py docs/openapi.json
"""

import json
import sys

from openapi_errors import CONTRACT_VERSION, error_example
from openapi_contracts import param_to_openapi, typed_success_schema
from openapi_examples import REQUEST_BODY_EXAMPLES
from openapi_navigation import tag_name

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
    11: 500,  # MESSAGES_ERROR
    12: 500,  # PHONE_CALLS_ERROR
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
    if leaf.get("params"):
        command += " --params '<JSON object>'"
    if leaf.get("inputSchema"):
        command += " --body '<JSON object>'"
    safety = leaf.get("safety") or {}
    confirmation = safety.get("confirmation")
    if confirmation:
        return f'{command} --apply --confirm "{confirmation}"'
    if safety.get("apply"):
        return f"{command} --apply"
    return command


def leaf_operation(leaf, tag=None, command="", title="", group="", leaf_name="", number=None, path=""):
    command = cli_example(command, leaf)
    method = leaf["method"].lower()
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
        op["responses"]["200"]["content"]["application/json"]["schema"] = typed_success_schema(output)
    inp = leaf.get("inputSchema")
    if inp:
        media = {"schema": {"$ref": "#/components/schemas/" + inp}}
        example = REQUEST_BODY_EXAMPLES.get((leaf["method"], path))
        if example is not None:
            media["example"] = example
        op["requestBody"] = {
            "required": True,
            "content": {"application/json": media},
        }
    return {method: op}


_GROUP_ORDER = [
    "agent", "resources", "contacts", "calendar", "reminders", "notes",
    "mail", "messages", "phone-calls", "photos", "safari", "shortcuts",
]

_GROUP_DESCRIPTIONS = {
    "agent": "Global discovery commands for people, scripts, and agents.",
    "contacts": "Query and manage contacts.",
    "calendar": "Query and manage calendar events in the uniquely verified iCloud CalDAV source.",
    "reminders": "Query and manage reminders in the uniquely verified iCloud CalDAV source.",
    "notes": "Bounded Notes.app Automation access through the public scripting dictionary.",
    "mail": "Read-only Mail access over the local SQLite store with a bounded Apple Events fallback.",
    "messages": "Read-only recent Messages (iMessage/SMS).",
    "phone-calls": "Read-only recent call history (Phone/FaceTime).",
    "photos": "Query photo metadata and export via public PhotoKit.",
    "safari": "Bounded Safari bookmarks and Reading List over a read-only plist snapshot plus guarded local-only mutation.",
    "shortcuts": "Run and author shortcuts; bounded read-only classification and guarded copy-first editing.",
}


def route_group(route):
    return route["path"].strip("/").split("/", 1)[0]


def group_prefix(group):
    if group in ("agent", "resources"):
        return "A"
    domains = [name for name in _GROUP_ORDER if name not in ("agent", "resources")]
    return str(domains.index(group) + 1)


def tag_group(group):
    return "agent" if group == "resources" else group


def build_paths(routes):
    paths = {}
    counts = {}
    order = {name: index for index, name in enumerate(_GROUP_ORDER)}
    for route in sorted(routes, key=lambda item: (order.get(route_group(item), 999), item["path"])):
        group = route_group(route)
        prefix = group_prefix(group)
        count_group = tag_group(group)
        counts[count_group] = counts.get(count_group, 0) + 1
        number = f"{prefix}.{counts[count_group]}"
        leaf_name = route["path"].strip("/").split("/", 1)[-1].replace("/", " ")
        tag_name_group = tag_group(group)
        tag = tag_name({"name": tag_name_group}, group_prefix(tag_name_group))
        command = f'mpia {route["method"]} "{route["path"]}"'
        paths[route["path"]] = leaf_operation(
            route, tag=tag, command=command, title=f"{group} {leaf_name}",
            group=group, leaf_name=leaf_name, number=number, path=route["path"],
        )
    return paths


def build_tags_from_routes(routes):
    groups = []
    for group in _GROUP_ORDER:
        normalized = tag_group(group)
        if any(route_group(route) == group for route in routes) and normalized not in groups:
            groups.append(normalized)
    return [
        {"name": tag_name({"name": group}, group_prefix(group)), "description": _GROUP_DESCRIPTIONS[group]}
        for group in groups
    ]


def build_components(source_schemas):
    schemas = rewrite_refs(source_schemas)
    schemas["SuccessEnvelope"] = {
        "type": "object",
        "description": "Success response envelope (ok=true, contractVersion, data).",
        "properties": {
            "ok": {"type": "boolean", "const": True},
            "contractVersion": {"type": "string", "pattern": r"^0\.1$", "minLength": 3, "maxLength": 3},
            "data": {},
        },
        "required": ["ok", "contractVersion", "data"],
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
            "contractVersion": {"type": "string", "pattern": r"^0\.1$", "minLength": 3, "maxLength": 3},
            "error": {
                "type": "object",
                "properties": {
                    "code": {"type": "string", "pattern": r"^[A-Z][A-Z0-9_]*$", "minLength": 1, "maxLength": 128, "description": "Stable error code (e.g. CONTACTS_ERROR)."},
                    "message": {"type": "string", "minLength": 1, "maxLength": 4096, "description": "Human-readable error message."},
                },
                "required": ["code", "message"],
            },
        },
        "required": ["ok", "contractVersion", "error"],
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
                "Executable REST-style contract for the local mpia macOS data CLI. "
                "Invoke a path with `mpia METHOD \"/path\"`; this document does not describe "
                "a network HTTP server. Parameters are passed as one strict inline JSON "
                "object through `--params`; structured request bodies use `--body`.\n\n"
                "HTTP methods are a semantic mapping:\n"
                "| HTTP method | CLI semantics |\n"
                "| --- | --- |\n"
                "| `OPTIONS` | Permission, discovery, or verification |\n"
                "| `HEAD` | Scalar metadata |\n"
                "| `GET` | Read |\n"
                "| `POST` | Create, execute, or export |\n"
                "| `PUT` | Full replacement |\n"
                "| `PATCH` | Partial edit |\n"
                "| `DELETE` | Delete |"
            ),
        },
        "paths": build_paths(inner.get("routes", [])),
        "tags": build_tags_from_routes(inner.get("routes", [])),
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
