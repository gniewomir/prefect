---
name: refine
description: >-
  Refine a GitHub ticket against current codebase, domain docs, parent, and
  blockers. Use when the user wants to refine a ticket, or mentions refining or
  grooming one.
---

# Refine

Check whether a ticket still matches reality. Frame the work as **refinement** — never "grooming".

Tracker ops: `docs/agents/issue-tracker.md`. Domain vocabulary: `docs/agents/domain.md`.

## Process

### 1. Resolve the ticket

Use the ticket already under investigation. If none is clear, ask which one.

Done when: a single issue number is fixed.

### 2. Load the authority set

Authority-set menu:

- the issue body and comments
- linked issues
- parent (if any); if none, skip parent checks
- preceding closed siblings that share the same parent
- linked assets
- `CONTEXT.md` and relevant ADRs under `docs/adr/`
- enough of the codebase to judge **what to build**, **acceptance criteria**, and any **implementation decisions** the ticket or its parent spec still states

For each item, decide from context already in the session whether a fresh load earns its keep: load it, or skip with a brief reason (irrelevant to this ticket, or already sufficient in context). Always refresh the ticket’s live tracker state (issue + comments, open blockers). Prefer not re-reading large artifacts already loaded this session unless drift checking needs a fresh pass.

Done when: every menu item is loaded or explicitly skipped with a reason, and live ticket state has been refreshed.

### 3. Check for drift

Against the authority set, look for:

- **What to build**, **acceptance criteria**, and any **implementation decisions** (on the ticket or its parent spec) that no longer match code or docs
- **Prerequisites** — open blockers, or wrong/missing assumptions about work already done
- **Parent alignment** — what to build and wording vs parent (skip if no parent)
- **Domain misalignment** — ticket vocabulary vs glossary / related ADRs
- **Ambiguities** — unresolved decisions, preexisting or introduced since the ticket was written

Judge fit. Leave how to achieve what to build to the implementing session.

Done when: every axis above has an explicit pass or finding.

### 4. Report

If nothing fails: say **no refinement required — aligned with reality**. Stop.

Otherwise, for each finding: state the drift, and when the fix is obvious, recommend it (e.g. rewrite wording, retag, close the ticket, run `/grill-with-docs`, wait on a blocker). Prefer a concrete next skill or tracker action over open-ended advice.

Done when: either the aligned-with-reality line is delivered, or every finding has a recommended course of action.

### 5. Mutate only on approval

Do not edit the issue, comments, or labels unless the user approves a specific change or asks for it directly. Then apply only what was approved.

Done when: either no mutation was requested, or every approved mutation is applied.
