# No backwards compatibility during development

Propraetor is pre-stability: interfaces, Manifests, Host layout, and Stack contracts still move. Maintaining backwards compatibility by default would freeze early shapes and accumulate dual-read/dual-write shims that hide the intended design. We prefer clean breaks — update callers, tests, and docs in the same change — unless a surface is explicitly marked stable or is already an external operator contract.

**Agents:** Always-apply rule `.cursor/rules/no-backwards-compat-in-development.mdc` steers day-to-day work from this decision.

**Considered:** Always preserve prior shapes; version every contract from day one; require explicit “breaking OK” per change. Rejected as default — too costly while the domain and Host shape are still settling; the rare external or user-called-out case is the exception, not the rule.

**Revisit when:** a public or cross-repo contract is deliberately stabilized (then document that surface and treat breaks as exceptional).
