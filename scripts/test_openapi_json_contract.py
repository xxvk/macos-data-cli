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

    def test_every_request_body_has_a_concrete_object_example(self):
        routes_with_bodies = []
        for path, path_item in self.spec["paths"].items():
            for method, operation in path_item.items():
                request_body = operation.get("requestBody")
                if request_body is None:
                    continue
                routes_with_bodies.append((method.upper(), path))
                media = request_body["content"]["application/json"]
                self.assertIsInstance(media.get("example"), dict, f"missing object example for {method.upper()} {path}")
                self.assertTrue(media["example"], f"empty object example for {method.upper()} {path}")

        self.assertEqual(len(routes_with_bodies), 24)

    def test_calendar_edit_keeps_its_concrete_request_body_example(self):
        media = self.operation("/calendar/edit")["requestBody"]["content"]["application/json"]
        self.assertEqual(media["schema"]["$ref"], "#/components/schemas/CalendarEventPatch")
        self.assertEqual(media["example"], {
            "title": "Project review",
            "startDate": "2026-08-20T10:00:00+09:00",
            "endDate": "2026-08-20T11:00:00+09:00",
            "timeZone": "Asia/Tokyo",
            "location": "Meeting Room A",
        })

    def test_safari_shared_schema_examples_follow_each_route_contract(self):
        expected_keys = {
            "/safari/bookmarks/create": {"parentID", "index", "title", "url"},
            "/safari/bookmarks/edit": {"id", "title", "url"},
            "/safari/bookmarks/move": {"id", "parentID", "index"},
            "/safari/bookmarks/delete": {"id"},
            "/safari/folders/create": {"parentID", "index", "title"},
            "/safari/folders/rename": {"id", "title"},
            "/safari/folders/move": {"id", "parentID", "index"},
            "/safari/folders/delete": {"id"},
        }
        for path, required in expected_keys.items():
            example = self.operation(path)["requestBody"]["content"]["application/json"]["example"]
            self.assertTrue(required.issubset(example), f"incomplete route-specific example for {path}")
            self.assertRegex(example["expectedSourceSHA256"], r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
