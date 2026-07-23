# Acceptance Test harness at repo root

Operator checks of an applied Stack are **Acceptance Tests**: a root runner builds a shared fixture once, then executes numeric-prefixed capability-slice scripts as subprocesses (fail-fast; optional single-slice selector).

**Why this shape:** a monolith inside the Stack directory hid the extension path and mixed unrelated contracts. Filename sort encodes dependency order without a manifest; subprocesses stop shell state leaking between slices; fixture-once avoids repeating State discovery. Alternatives considered: self-contained cases (duplicated terraform/jq setup), sourced-in-runner cases (shared `set +e` hazards), and an explicit order file (second place to edit on every add).
