# Prefect Tag and Role Tag stay separate

Prefect uses two DigitalOcean tags, not one. The Prefect Tag (`prefect`) marks taggable resources as belonging to Prefect; the Role Tag (`prefect-public-web`) selects Hosts for policies such as the public-web Firewall. Collapsing them would couple “everything Prefect owns” to “Hosts that should get the public-web Firewall,” so Prefect Tag membership and policy attachment stay independent.
