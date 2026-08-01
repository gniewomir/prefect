# Propraetor Tag and Role Tag stay separate

Propraetor uses two DigitalOcean tags, not one. The Propraetor Tag (`propraetor`) marks taggable resources as belonging to Propraetor; the Role Tag (`propraetor-public-web`) selects Hosts for policies such as the public-web Firewall. Collapsing them would couple “everything Propraetor owns” to “Hosts that should get the public-web Firewall,” so Propraetor Tag membership and policy attachment stay independent.
