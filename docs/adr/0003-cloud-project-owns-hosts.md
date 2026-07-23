# Cloud Project owns Hosts; Reserved IP follows the Host

The Stack creates Cloud Project `Prefect` and assigns Hosts to it. A Reserved IP attached to a Host follows that Host’s Cloud Project at the provider; listing the Reserved IP URN explicitly is avoided because the Projects API still exposes assigned Reserved IPs as floatingip URNs and causes State drift.
