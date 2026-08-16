"""Stable documentation numbering for manifest command groups."""

_ADAPTER_ORDER = (
    "contacts",
    "calendar",
    "reminders",
    "notes",
    "mail",
    "messages",
    "phone-calls",
    "photos",
    "safari",
    "shortcuts",
)

_AGENT_COMMAND_ORDER = ("help", "version", "manifest")


def numbered_commands(commands):
    """Merge resource discovery into Agent and number user-facing adapters from one."""
    agent_exists = any(command.get("name") == "agent" for command in commands)
    resources = next((command for command in commands if command.get("name") == "resources"), None)
    adapters = {
        command.get("name"): command
        for command in commands
        if command.get("name") not in ("agent", "resources")
    }
    for command in commands:
        if command.get("name") == "agent":
            merged = dict(command)
            subcommands = {leaf.get("name"): leaf for leaf in command.get("subcommands") or []}
            ordered_names = [name for name in _AGENT_COMMAND_ORDER if name in subcommands]
            ordered_names.extend(name for name in subcommands if name not in _AGENT_COMMAND_ORDER)
            merged["subcommands"] = [subcommands[name] for name in ordered_names]
            if resources is not None:
                merged["subcommands"].append(resources)
            yield "A", merged
            break

    ordered_names = [name for name in _ADAPTER_ORDER if name in adapters]
    ordered_names.extend(name for name in adapters if name not in _ADAPTER_ORDER)
    for numeric_index, name in enumerate(ordered_names, start=1):
        yield str(numeric_index), adapters[name]

    if resources is not None and not agent_exists:
        yield str(len(ordered_names) + 1), resources


def tag_name(command, prefix):
    return f"{prefix}. {command.get('name', '')}"
