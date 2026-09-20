# Pi Agent Shelf

A small macOS app for jumping between live pi agents in Ghostty.

It lists agents vertically, newest activity first. It reads the existing pi runtime registry and session JSONL files; it does not run a daemon or modify sessions.

## Build and run

```bash
./scripts/build-app.sh
open ".build/Pi Agent Shelf.app"
```

The build script uses the first available Developer ID Application identity. Set `CODE_SIGN_IDENTITY` to override it. Stable signing is required so macOS Automation approval survives rebuilds.

The agent list does not require Automation permission. macOS asks for Ghostty access so selecting an agent can focus its terminal.

Focus caches terminal IDs in memory. Each cached ID is checked against the selected agent's TTY before use. Missing or mismatched IDs trigger one fresh, server-side lookup; switching Ghostty processes clears the cache. There is no background Automation polling, and permission errors or timeouts are not retried.

Open the menu-bar agent list from its icon or the global **Control-Option-P** shortcut. The regular shelf window remains available through Cmd-Tab.

## Tests

```bash
swift test --filter GhosttyClientTests
```

These tests use a fake script runner; they do not contact Ghostty or change terminal focus.

## Requirements

- macOS 14 or newer
- Ghostty with scripting support
- pi's existing `ghostty-session-registry.ts` extension, which writes `~/.pi/agent/session-runtime/<pid>.json`
