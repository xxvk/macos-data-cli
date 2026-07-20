# CLI Contract

## JSON envelope

Machine-readable responses use `contractVersion: "0.1"`, independent from the
CLI release version.

| Result | Shape | Exit code |
| --- | --- | ---: |
| Success | `{"ok":true,"contractVersion":"0.1","data":...}` | 0 |
| Unexpected CLI error | JSON `error.code = CLI_ERROR` | 1 |
| Contacts / permission / input error | JSON `error.code = CONTACTS_ERROR` | 2 |
| Contact lookup error | JSON `error.code = CONTACT_QUERY_ERROR` | 3 |
| Usage or invalid query | JSON `error.code = INVALID_QUERY` | 64 |

Errors are written to stderr. Successful JSON responses are written to stdout.
The caller should branch on the exit code first, then inspect `error.code` and
`error.message` when a JSON error envelope is requested.
