# Acceptance Test harness at repo root

Operator checks of an applied Stack are **Acceptance Tests**: a internals Acceptance runner builds a shared fixture once, then executes numeric-prefixed capability-slice scripts as subprocesses (fail-fast; optional single-slice selector). They require a live Applied Stack (Host present) and are **non-destructive** to Stack lifecycle — they must not Park or Teardown. Stack lifecycle checks are **Lifecycle Tests** (`internals/lifecycle-tests.sh`), a separate opt-in suite (ADR-0016).

**Why this shape:** a monolith inside the Stack directory hid the extension path and mixed unrelated contracts. Filename sort encodes dependency order without a manifest; subprocesses stop shell state leaking between slices; fixture-once avoids repeating State discovery. Alternatives considered: self-contained cases (duplicated terraform/jq setup), sourced-in-runner cases (shared `set +e` hazards), and an explicit order file (second place to edit on every add).
