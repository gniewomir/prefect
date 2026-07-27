---
name: close
description: >-
  Close out the session's GitHub ticket — commit gate, summary comment, close,
  next-step suggestion.
disable-model-invocation: true
---

# Close

End work on a ticket: pass the **commit gate**, leave a **reference**-heavy summary on the issue, **close** it, and name the next unit of work.

tracker ops: `docs/agents/issue-tracker.md`.

## Process

### 1. Resolve the ticket

Use the ticket this session is focused on. If more than one is in play or none is clear, ask which to close.

Done when: a single issue number is fixed.

### 2. Commit gate

Check `git status` (and the relevant diff) for uncommitted work tied to the ticket.

- Dirty with ticket work: tell the user what is uncommitted, offer to commit, and stop. Commit only after they accept, using the session's git commit protocol. Re-check the tree after.
- Clean: proceed.

Do not advance past this step while uncommitted ticket work remains, unless the user explicitly waives the commit.

Done when: the working tree has no uncommitted ticket work, or the user has explicitly waived committing.

### 3. Summary comment

Post one comment on the issue covering this session only:

- what was done
- decisions made, changed, or updated for this ticket
- documentation created or updated

Prefer **references** (paths, commit SHAs, ADR ids, PR/issue URLs) over pasting content.

Done when: that comment exists on the issue.

### 4. Close the ticket

Close the issue via the tracker.

Done when: the issue state is closed.

### 5. Next step

Suggest the logical next unit of work — e.g. an unblocked sibling under the same parent, a wayfinder frontier ticket, or a related open issue — with enough context to pick it up. If nothing is obvious, say so and point at how to find the frontier (`docs/agents/issue-tracker.md`).

Done when: a concrete next pick is delivered, or an explicit "nothing obvious" with a discovery pointer.
