# Fast-mode reporting

The shelf shows a native `bolt.fill` icon only when a live agent reports Fast mode on for its current model. Hover text distinguishes off from unknown. It never guesses from the shared Fast config: each running extension has independent in-memory state.

## Setup

The included patch extends the existing [pi-openai-fast-mode](https://github.com/johncmunson/pi-openai-fast-mode) 0.5.0 package. It does not install another extension or change model requests.

```sh
./scripts/enable-fast-mode-status.sh
# Or supply the installed package directory explicitly:
./scripts/enable-fast-mode-status.sh /path/to/pi-openai-fast-mode
```

The installer checks the source checksum, is idempotent, and refuses unknown versions or other local edits. Package updates can overwrite the patch; reapply it after a compatible reinstall. Review and update the patch for other versions.

Run `/reload` in existing pi sessions. New sessions report automatically. No existing pi process is restarted by the installer. Until an agent loads the patch, its Fast status remains unknown and no bolt is shown.

## Runtime contract

On session startup, `/fast` changes, and model changes, the extension atomically writes:

`~/.pi/agent/session-runtime/<pid>.fast.json`

It honors pi's configured agent directory. The file contains only `pid`, `session_id`, `session_file`, `provider`, `model`, and `enabled`. `enabled` means the setting is on **and** the model matches the Fast extension's configured targets. This indicates the requested Fast setting, not proof that the provider served priority inference.

The file is removed on session shutdown/reload. The shelf validates PID, session ID, session path, provider, and model against its live agent record. Missing, corrupt, or mismatched reports are unknown, not off. Files from dead agents are never consulted. Status is reread on each shelf refresh, independently of session-file caching; changing Fast mode does not change activity ordering.

## Tests

```sh
swift test --filter FastModeStatusTests
# Node test requires jiti from a pi source checkout's node_modules:
NODE_PATH=/path/to/pi/node_modules node --test Tests/fast-mode-reporting.test.mjs
```

Set `FAST_MODE_PACKAGE_DIR` to test another patched package location. Tests use fake pi hooks and temporary directories: no model calls, real config changes, or live session reloads.

The patch includes context from upstream MIT-licensed source; see `LICENSE`.
