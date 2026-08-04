# Suite baselines and test isolation

Shared Host / Host Volume for Acceptance and Lifecycle has no DB-style transaction. Peer-pollution cleanup (a case fixing residue left by another) is banned. Suite policies differ.

**Acceptance:** Suite baseline between cases is **Deployed**. The runner re-converges via **Deploy** before each case (failure artifacts remain until the next baseline). Cases restore Environment SoT / Intent to committed truth before exit; the runner owns Host convergence. Host Volume `data/`: no destruction except as expressed operator Intent (Environment absence / Intent **trash** → Orphan Reap / Purge via Deploy is fine); cases own cleanup only of case-created durable residue that would survive the next Deploy; runner **G** is tracked-path only (v1); full preexisting `data/` oracle deferred. Non-**test** Acceptance is diagnostic: typed `diagnose <slug>`, no Environment fixtures / Intent flips that imply undeclared Host data loss, Deploy still runs. No Deployed assert-G in v1.

**Lifecycle:** Suite baseline between cases is Stack **absent** (post-**Teardown**). Runner Teardown before each case. **test Environment only** (fail closed otherwise). Suite start: type `teardown` once. Opt-in; slow by design.

**Unit:** No Host baseline. Lasting side effects outside the test’s own temporary workspace mean it is not a Unit Test — purify, move to Acceptance, or ask a human.

**Rejected:** Full case-owned Host rollback (B) or assert-only (G) as the primary Acceptance isolation story; Host Volume snapshot/restore; namespaced fixtures as isolation; fresh Host per Acceptance case; declared-mutation hybrid restore; Lifecycle on non-**test**; Deployed canary-G in v1.

Amends ADR-0005 (fixture-once → Deploy before each Acceptance case); ADR-0036 (Lifecycle `--env` other than test no longer valid). Glossary: Acceptance / Lifecycle / Unit Test. Issue #159.
