# Reserved IP as the public address

Public Hosts are reached via a Reserved IP assigned to the Host, not via the Host’s own public IP. Domains must point at a stable address that survives rebuilds and other changes in Prefect infrastructure; the Host’s ephemeral public IP does not provide that.
