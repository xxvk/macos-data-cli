"""Reusable OpenAPI schemas for the CLI's stable JSON envelopes."""

from openapi_errors import CONTRACT_VERSION

_PARAM_TYPE_MAP = {
    "string": "string",
    "stringArray": "array",
    "int": "integer",
    "bool": "boolean",
    "file": "string",
    "json": "object",
}


def param_to_openapi(param):
    """Convert one manifest parameter to an OpenAPI query parameter."""
    schema_type = _PARAM_TYPE_MAP.get(param.get("type", "string"), "string")
    spec = {
        "name": param.get("name", ""),
        "in": "query",
        "description": param.get("description", ""),
        "schema": {"type": schema_type},
    }
    if param.get("required"):
        spec["required"] = True
    if schema_type == "array":
        spec["schema"]["items"] = {"type": "string"}
    return spec


def typed_success_schema(output_schema):
    """Wrap one command-specific data schema in the real CLI success envelope."""
    return {
        "type": "object",
        "properties": {
            "ok": {"type": "boolean", "const": True, "example": True},
            "contractVersion": {
                "type": "string",
                "pattern": r"^0\.1$",
                "minLength": 3,
                "maxLength": 3,
                "example": CONTRACT_VERSION,
            },
            "data": {"$ref": "#/components/schemas/" + output_schema},
        },
        "required": ["ok", "contractVersion", "data"],
    }
