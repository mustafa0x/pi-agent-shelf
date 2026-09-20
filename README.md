# Pi Agent Shelf

A small macOS menu-bar app for jumping between live pi agents in Ghostty.

It lists agents in one horizontal shelf, newest activity first. It reads the existing pi runtime registry and session JSONL files; it does not run a daemon or modify sessions.

## Build and run

```bash
./scripts/build-app.sh
open ".build/Pi Agent Shelf.app"
```

macOS will ask for permission to automate Ghostty the first time the app focuses a terminal.

Open the shelf from the menu-bar icon or press **Control-Option-P**.

## Requirements

- macOS 14 or newer
- Ghostty with scripting support
- pi's existing `ghostty-session-registry.ts` extension, which writes `~/.pi/agent/session-runtime/<pid>.json`
