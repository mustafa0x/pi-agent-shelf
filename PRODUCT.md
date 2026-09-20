# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS

## Stack

SwiftUI and AppKit, packaged as a standalone macOS application.

## Users

A developer running many simultaneous pi agents in Ghostty who needs to find and return to the right agent quickly.

## Product Purpose

Show every live pi agent in one vertically scrollable list, ordered by recent session activity. Selecting an agent focuses its exact Ghostty terminal.

## Operating Context

The app reads live process ancestry, pi runtime records under `~/.pi/agent/session-runtime/`, and pi JSONL sessions under `~/.pi/agent/sessions/`. Ghostty scripting is used only to focus a selected terminal.

## Capabilities and Constraints

- Read-only integration; no daemon or database.
- Ignore stale runtime records and non-Ghostty pi processes.
- Match agents to Ghostty by TTY so temporary foreground child processes do not break navigation.
- Prefer simple native macOS behavior over customization.

## Product Principles

- One shortcut from anywhere to any agent.
- Fresh work is always easiest to reach.
- Show enough identity to distinguish agents without exposing conversation content.
- Fail quietly and preserve the user's existing pi and Ghostty setup.
