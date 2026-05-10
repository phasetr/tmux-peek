# tmux-peek Agent Notes

Codex must read this file before making implementation decisions.

## Required Context

- Requirements live in `.self-local/tmux-peek-requirements.md`.
- The implementation plan lives in `.self-local/tmux-peek-implementation-plan.md`.
- The requirements document is not a complete specification. It is a working requirements memo.
- Return values, parser details, field lists, and public API details must be refined gradually during implementation.
- Do not invent broad specifications up front.

## Project Intent

- tmux-peek is a small Emacs Lisp library for inspecting tmux live state.
- It is built in this repository, `phasetr/tmux-peek`.
- It is related to, but independent from, enkan-repl: <https://github.com/phasetr/enkan-repl>.
- enkan-repl already handles start/send/attach/mirror operational flows. Do not reimplement those here.
- tmux-peek should prioritize state inspection, one-shot pane capture, and explicit session cleanup.
- The primary interactive cleanup command is `tmux-peek-session-list`, which
  lists tmux sessions in an Emacs buffer and lets the user refresh, kill the
  selected session, or quit.

## Hard Scope Rules

- Prioritize asynchronous APIs. Synchronous helpers are secondary.
- Keep the package small. Do not add broad tmux wrappers without a concrete need.
- Implement only `kill-session` for cleanup.
- Do not expose or implement:
  - `kill-pane`
  - `kill-window`
  - `kill-server`
  - `new-session`
  - `new-window`
  - `split-window`
  - `send-keys`
  - `attach-session`
  - tmux interactive UI wrappers such as `choose-*`, `display-menu`, `display-popup`, `command-prompt`
- The intent of cleanup is killing one explicitly selected tmux session, matching
  enkan-repl's session-level tmux lifecycle. Window, pane, and server cleanup
  wrappers are intentionally sealed off.

## Development Rules

- Use TDD as the baseline: add focused ERT coverage before or alongside each implementation slice.
- Work in small implementation slices suitable for pull requests.
- Keep implementation minimal. Do not add convenience APIs until the need is demonstrated.
- Refactor aggressively at phase boundaries, especially around:
  - async executor
  - process handle/result shape
  - command builder
  - parser
  - public API
- Remove unused abstractions, unused options, and wrapper functions that are not needed.
- When implementation changes clarify requirements, update the requirements and plan documents.
