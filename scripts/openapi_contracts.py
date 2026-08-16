"""Reusable OpenAPI schemas for the CLI's stable JSON envelopes."""

from openapi_errors import CONTRACT_VERSION


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
