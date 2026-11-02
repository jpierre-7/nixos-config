---
name: diff-notes
description: Read and answer the notes the user left in the hunk diff of this Claude session (the side pane that herdr's Ctrl+Space d opens). Use when the user asks you to look at, check, read, or address their diff notes, hunk notes, review notes, or comments on the diff.
---

The user reviews this session's changes in hunk, a terminal diff viewer, and
leaves notes on lines with `c`. The notes live only in the open hunk window.

## 1. Get the notes

```bash
claude-session-diff notes
```

It prints JSON:

- `hunkSession`: the hunk session ID. Pass it to every `hunk session` command.
  `--repo .` does not find this window.
- `repo`: the repository root. `filePath` values are relative to it.
- `threads`: the threads that need an answer, each in date order. The last
  message in each thread is the user's. Earlier messages are context, such as
  your previous reply.

If it says no diff window is open, ask the user to press Ctrl+Space d in herdr
and leave the notes again. If `threads` is empty, tell the user there are no
unanswered notes.

## 2. Find the code each note points at

A note has `filePath`, `hunkIndex` (0-based), and `newRange` or `oldRange`
(line numbers on the new or old side of the diff). Line numbers are the ones
at the moment the user wrote the note. If the file changed since then, the
note can point at the wrong line. To see the diff as the user saw it:

```bash
hunk session review <hunkSession> --include-patch --json
```

Read the file around the line too. If you cannot tell which code the note
means, ask the user.

## 3. Act on each note

- A question, such as "explain this" or "why?": answer it.
- A change request, such as "rename this" or "handle the error": make the
  change. The diff pane shows it within a second.
- If a note is unclear or you disagree with it, say so instead of guessing.

## 4. Reply in hunk, then in the chat

Post one short reply on each thread, so the user sees it next to the code and
the thread no longer counts as unanswered. Reply to the thread's first note:

```bash
hunk session comment add <hunkSession> --reply-to '<first noteId>' \
  --summary '<one or two sentences>' --author claude
```

Quote `--summary` with single quotes. Then give the full answers in the chat,
grouped by file and line, because the chat has more space than a note.

Do not delete or clear the user's notes (`comment rm`, `comment clear`), do not
run `hunk session reload`, and do not start `hunk diff` or other hunk TUI
commands. For the full `hunk session` reference, run `hunk skill show`.
