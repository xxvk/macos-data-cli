"""Concrete request-body examples keyed by executable mpia route."""

SAMPLE_SHA256 = "a" * 64

REQUEST_BODY_EXAMPLES = {
    ("POST", "/contacts/create"): {
        "kind": "person", "externalID": "person-ada-001",
        "givenName": "Ada", "familyName": "Lovelace",
        "organizationName": "Northwind", "jobTitle": "Engineer",
        "emails": [{"label": "work", "value": "ada.lovelace@example.com"}],
        "phones": [{"label": "mobile", "value": "+81 90 1234 5678"}],
        "urls": [{"label": "homepage", "value": "https://example.com/ada"}],
        "addresses": [{
            "label": "work", "street": "1-1 Marunouchi",
            "city": "Chiyoda-ku", "state": "Tokyo",
            "postalCode": "100-0005", "country": "JP",
        }],
        "metadata": {"source": "agent-example"}, "imageAvailable": False,
    },
    ("PATCH", "/contacts/edit"): {
        "organizationName": "Northwind Labs", "jobTitle": "Principal Engineer",
        "emails": [{"label": "work", "value": "ada@example.com"}],
    },
    ("POST", "/calendar/create"): {
        "calendarID": "calendar_opaque_id", "title": "Project review",
        "startDate": "2026-08-20T10:00:00+09:00",
        "endDate": "2026-08-20T11:00:00+09:00",
        "timeZone": "Asia/Tokyo", "location": "Meeting Room A",
        "notes": "Review milestones and risks.",
    },
    ("PATCH", "/calendar/edit"): {
        "title": "Project review",
        "startDate": "2026-08-20T10:00:00+09:00",
        "endDate": "2026-08-20T11:00:00+09:00",
        "timeZone": "Asia/Tokyo", "location": "Meeting Room A",
    },
    ("POST", "/reminders/create"): {
        "listID": "reminderlist_opaque_id", "title": "Submit project report",
        "due": "2026-08-20T18:00:00+09:00", "priority": "high",
        "notes": "Attach the final review notes.",
    },
    ("PATCH", "/reminders/edit"): {
        "title": "Submit final project report",
        "due": "2026-08-21T18:00:00+09:00", "priority": "high",
    },
    ("POST", "/notes/create"): {
        "folderID": "notesfolder_opaque_id", "title": "Project notes",
        "bodyFormat": "plaintext", "body": "Review milestones and next actions.",
    },
    ("DELETE", "/notes/delete"): {
        "expectedModificationDate": "2026-08-15T09:00:00Z",
    },
    ("PUT", "/notes/edit-body"): {
        "bodyFormat": "plaintext", "body": "Updated project notes.",
        "expectedModificationDate": "2026-08-15T09:00:00Z",
        "expectedBodySHA256": SAMPLE_SHA256,
    },
    ("POST", "/notes/folder/create"): {
        "name": "Projects", "parentFolderID": "notesfolder_parent_opaque_id",
    },
    ("DELETE", "/notes/folder/delete"): {
        "expectedParentFolderID": "notesfolder_parent_opaque_id",
        "expectedNameSHA256": SAMPLE_SHA256,
    },
    ("PATCH", "/notes/folder/move"): {
        "destinationParentFolderID": "notesfolder_destination_opaque_id",
        "expectedParentFolderID": "notesfolder_parent_opaque_id",
        "expectedNameSHA256": SAMPLE_SHA256,
    },
    ("PATCH", "/notes/folder/rename"): {
        "name": "Archived Projects", "expectedNameSHA256": SAMPLE_SHA256,
    },
    ("PATCH", "/notes/move"): {
        "destinationFolderID": "notesfolder_destination_opaque_id",
        "expectedModificationDate": "2026-08-15T09:00:00Z",
    },
    ("PATCH", "/notes/rename"): {
        "title": "Project notes (updated)",
        "expectedModificationDate": "2026-08-15T09:00:00Z",
    },
    ("POST", "/safari/bookmarks/create"): {
        "parentID": "safarifolder_parent_opaque_id", "index": 0,
        "title": "Example", "url": "https://example.com",
        "expectedSourceSHA256": SAMPLE_SHA256,
    },
    ("DELETE", "/safari/bookmarks/delete"): {
        "id": "safaribookmark_opaque_id", "expectedSourceSHA256": SAMPLE_SHA256,
    },
    ("PATCH", "/safari/bookmarks/edit"): {
        "id": "safaribookmark_opaque_id", "title": "Example (updated)",
        "url": "https://example.com/updated", "expectedSourceSHA256": SAMPLE_SHA256,
    },
    ("PATCH", "/safari/bookmarks/move"): {
        "id": "safaribookmark_opaque_id",
        "parentID": "safarifolder_destination_opaque_id", "index": 0,
        "expectedSourceSHA256": SAMPLE_SHA256,
    },
    ("POST", "/safari/folders/create"): {
        "parentID": "safarifolder_parent_opaque_id", "index": 0,
        "title": "Research", "expectedSourceSHA256": SAMPLE_SHA256,
    },
    ("DELETE", "/safari/folders/delete"): {
        "id": "safarifolder_opaque_id", "expectedSourceSHA256": SAMPLE_SHA256,
    },
    ("PATCH", "/safari/folders/move"): {
        "id": "safarifolder_opaque_id",
        "parentID": "safarifolder_destination_opaque_id", "index": 0,
        "expectedSourceSHA256": SAMPLE_SHA256,
    },
    ("PATCH", "/safari/folders/rename"): {
        "id": "safarifolder_opaque_id", "title": "Research Archive",
        "expectedSourceSHA256": SAMPLE_SHA256,
    },
    ("POST", "/safari/reading-list/add"): {
        "url": "https://example.com/article", "title": "Example article",
        "previewText": "A short summary for the Reading List item.",
    },
}
