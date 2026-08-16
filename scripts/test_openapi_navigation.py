#!/usr/bin/env python3
"""Regression tests for documentation-only OpenAPI navigation."""

import unittest

from openapi_navigation import numbered_commands


class OpenApiNavigationTests(unittest.TestCase):
    def test_resources_is_the_fourth_agent_leaf(self):
        commands = [
            {
                "name": "agent",
                "kind": "group",
                "subcommands": [
                    {"name": "help", "kind": "leaf"},
                    {"name": "manifest", "kind": "leaf"},
                    {"name": "version", "kind": "leaf"},
                ],
            },
            {"name": "resources", "kind": "leaf", "usage": "mpia resources --format json"},
            {"name": "mail", "kind": "group", "subcommands": []},
            {"name": "shortcuts", "kind": "group", "subcommands": []},
            {"name": "contacts", "kind": "group", "subcommands": []},
            {"name": "photos", "kind": "group", "subcommands": []},
            {"name": "calendar", "kind": "group", "subcommands": []},
            {"name": "reminders", "kind": "group", "subcommands": []},
            {"name": "notes", "kind": "group", "subcommands": []},
            {"name": "safari", "kind": "group", "subcommands": []},
            {"name": "phone-calls", "kind": "group", "subcommands": []},
            {"name": "messages", "kind": "group", "subcommands": []},
        ]

        numbered = list(numbered_commands(commands))

        self.assertEqual([(prefix, item["name"]) for prefix, item in numbered], [
            ("A", "agent"),
            ("1", "contacts"),
            ("2", "calendar"),
            ("3", "reminders"),
            ("4", "notes"),
            ("5", "mail"),
            ("6", "messages"),
            ("7", "phone-calls"),
            ("8", "photos"),
            ("9", "safari"),
            ("10", "shortcuts"),
        ])
        self.assertEqual(
            [leaf["name"] for leaf in numbered[0][1]["subcommands"]],
            ["help", "version", "manifest", "resources"],
        )


if __name__ == "__main__":
    unittest.main()
