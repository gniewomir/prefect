# Prefect User in Initial Host Provisioning

The **Prefect User** (`prefect`) and linger are created in Initial Host Provisioning so every applied public Host is ready for rootless user Quadlets without a post-apply ensure script. Acceptance Tests assert the account and linger after cloud-init finishes.

**Initial Host Provisioning over post-apply ensure:** the account is mandatory Host shape for Edge (not optional deploy garnish); baking it into first boot removes a manual/harness step and matches “Edge is part of Prefect.” Cost: user_data changes recreate the Host. Post-apply `ensure-prefect-user.sh` (and runner invocation) is removed.

**Unchanged from ADR-0004 / ADR-0006:** still no Quadlet units in Initial Host Provisioning; the Host stays a carrier for workloads installed later as user Quadlets.
