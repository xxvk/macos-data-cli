### Why CLI instead of MCP

For mpia, the CLI is the stable, canonical interface. MCP can still be useful, but making it the only entry point would add coupling to an Agent Host, host-specific configuration, server lifecycle, and TCC identity. Those limitations conflict with mpia's agent-neutral, local-first, ready-to-use goals.

| Comparison | CLI<br>*Command-Line Interface* | MCP<br>*Model Context Protocol* |
| --- | --- | --- |
| Callable from any agent with terminal access | ✅ | ❌<br>*The Host must support and configure MCP first* |
| Independent of a specific client such as Codex or Claude | ✅ | ❌<br>*Support and configuration vary by Host* |
| Ready after Homebrew installation | ✅ | ❌<br>*Server registration and Host configuration remain* |
| No persistent server lifecycle | ✅<br>*Starts and exits per request* | ❌<br>*Server startup, connection, and recovery must be managed* |
| Shell, pipeline, and workflow composition | ✅ | ❌<br>*Requires an MCP Client or another bridge* |
| Direct Terminal use and debugging | ✅ | ❌<br>*Normally mediated by an Agent Host* |
| Stable signed App and TCC identity | ✅<br>*Permissions stay with the mpia App* | ❌<br>*Host, server, and data-process identities can diverge* |
| One installation shared by multiple agents | ✅ | ❌<br>*Each Host commonly needs separate configuration* |
| JSON, Manifest, and Schema discovery | ✅ | ✅ |
| Native tool discovery inside MCP clients | ❌<br>*Requires an optional wrapper* | ✅ |

The CLI therefore remains mpia's only canonical interface. A lightweight MCP wrapper may be added later by consuming the same Manifest and delegating execution to the CLI, but it must remain optional and must never duplicate business logic, alter safety rules, or replace the CLI.
