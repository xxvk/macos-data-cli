#!/usr/bin/env python3
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class OpenAPIJSONContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = json.loads((ROOT / "docs/openapi.json").read_text())

    def operation(self, path):
        path_item = self.spec["paths"][path]
        return next(iter(path_item.values()))

    def test_notes_runtime_json_inputs_have_request_bodies(self):
        self.assertEqual(
            self.operation("/notes/move")["requestBody"]["content"]["application/json"]["schema"]["$ref"],
            "#/components/schemas/NotesMoveInput",
        )
        self.assertEqual(
            self.operation("/notes/delete")["requestBody"]["content"]["application/json"]["schema"]["$ref"],
            "#/components/schemas/NotesDeleteInput",
        )

    def test_write_account_bind_uses_real_cli_flag_not_json_body(self):
        operation = self.operation("/notes/write-account/bind")
        self.assertNotIn("requestBody", operation)
        parameters = {item["name"]: item for item in operation["parameters"]}
        self.assertTrue(parameters["account-id"]["required"])
        self.assertNotIn("input", parameters)

    def test_typed_success_response_keeps_json_envelope(self):
        schema = self.operation("/photos/get")["responses"]["200"]["content"]["application/json"]["schema"]
        self.assertEqual(schema["type"], "object")
        self.assertEqual(schema["properties"]["ok"]["const"], True)
        self.assertEqual(schema["properties"]["contractVersion"]["example"], "0.1")
        self.assertEqual(schema["properties"]["data"]["$ref"], "#/components/schemas/PhotoAssetPayload")


if __name__ == "__main__":
    unittest.main()
