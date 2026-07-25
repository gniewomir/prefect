# Cloud Project owns Hosts; Reserved IP follows the Host when assigned

The Stack creates Cloud Project `Prefect` and assigns Hosts to it. A Reserved IP **attached** to a Host follows that Host’s Cloud Project at the provider; listing the Reserved IP URN explicitly is avoided when assigned because the Projects API still exposes assigned Reserved IPs as floatingip URNs and causes State drift.

While **Parked**, the Reserved IP is unassigned: it must remain in Cloud Project `Prefect` (with the Host Volume) and must not drift to the account default — implement the Parked assignment story with ADR-0016 (split address vs assignment).
