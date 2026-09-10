# Improvements

A running list of possible improvements. Items here are deferred, not scheduled
for implementation. When an item is picked up, update the matching specs in
`plan/` alongside the implementation.

## Session navigation from the menu bar

- **Status:** Deferred
- **Added:** 2026-09-10
- **Scope:** Minor macOS UI improvement

Click a session on the main page to open its corresponding conversation in
Codex, Claude Code, or Cursor, then dismiss Buddy's dropdown. Prefer focusing
the existing conversation or terminal tab.

Before implementation, verify each app's supported navigation mechanism:

- **Codex:** Validate an external link to an exact task; internal task navigation
  alone does not establish an integration Buddy can use.
- **Claude Code:** The VS Code extension documents opening a session by ID.
  Terminal resume is available, but focusing an existing terminal tab needs
  terminal-specific support. Do not silently start a second running session.
- **Cursor:** Verify whether existing local agent conversations can be opened
  by ID; documented prompt links do not establish this capability.

Buddy already tracks agent and session IDs. Determine what additional project,
host application, or terminal-tab information is needed. If only opening the
app or project is possible, label that fallback accurately instead of promising
to open the exact session.

References for later investigation:

- [Claude Code editor integration](https://code.claude.com/docs/en/ide-integrations)
- [Claude Code sessions](https://code.claude.com/docs/en/sessions)
- [Cursor deep links](https://cursor.com/docs/reference/deeplinks)
