"""Error message metadata for the mpia OpenAPI generator.

Holds the realistic, actionable `error.message` strings shown in response
examples, the shared contract version, and the helper that builds an error
envelope example for a given stable error code.
"""

# Realistic, actionable error messages shown in response examples. The CLI's
# own exit-code descriptions stay terse; these are the human-facing messages a
# caller would actually receive in the `error.message` field.
ERROR_MESSAGES = {
    "CLI_ERROR": "Unexpected CLI error. Re-run the command; if it persists, inspect the exit code.",
    "CONTACTS_ERROR": "Contacts access is denied or the input is invalid. Grant access in System Settings → Privacy & Security → Contacts.",
    "CONTACT_QUERY_ERROR": "The contact lookup was ambiguous or returned no match. Provide a more specific external ID.",
    "MAIL_ERROR": "Mail adapter error. Run `mpia OPTIONS \"/mail/doctor\"` to verify fast-path SQLite access.",
    "CALENDAR_ERROR": "Calendar adapter error. Verify full Calendar access and the iCloud CalDAV source.",
    "REMINDERS_ERROR": "Reminders adapter error. Verify full Reminders access and the iCloud CalDAV source.",
    "PHOTOS_ERROR": "Photos access is limited or denied. Check System Settings → Privacy & Security → Photos.",
    "NOTES_ERROR": "Notes Automation is not authorized. Grant access in System Settings → Privacy & Security → Automation.",
    "SHORTCUTS_ERROR": "Shortcuts adapter error. The shortcut could not be resolved, or the operation is unsupported.",
    "SAFARI_ERROR": "Safari adapter error. Safari must be fully exited for local bookmark writes, or the Bookmarks.plist is unavailable.",
    "MESSAGES_ERROR": "Messages adapter error. Grant Full Disk Access to the responsible process and verify the chat.db schema is supported.",
    "PHONE_CALLS_ERROR": "Phone calls adapter error. Grant Full Disk Access to the responsible process and verify the CallHistory.storedata schema is supported.",
    "INVALID_QUERY": "Invalid or malformed arguments. Run `mpia <command> --help` for usage.",
    "ERROR": "The command failed. See the exit code for the error category.",
}

CONTRACT_VERSION = "0.1"


def error_example(error_code):
    """Build a realistic error envelope example for a given stable error code."""
    return {
        "ok": False,
        "contractVersion": CONTRACT_VERSION,
        "error": {
            "code": error_code,
            "message": ERROR_MESSAGES.get(error_code, ERROR_MESSAGES["ERROR"]),
        },
    }
