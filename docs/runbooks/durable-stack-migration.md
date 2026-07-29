# Stack lifecycle — operator notes

ADR-0025 defines two structural lifecycle classes. `module.durables` owns the Cloud Project, Reserved IP, Host Volume, Domains, records, and their Cloud Project memberships. Conditional `module.recreatables` owns the Host and Applied-only companions and relationships.

**Environment:** `./apply.sh`, `./park.sh`, and `./teardown.sh` default safely to the **test** Environment. `--env test` and `--env default` select the same Environment; every other slug must be explicit.

## Apply

`./apply.sh [--yes] [--env <slug>]` uses the default presence intent. Terraform converges the complete Durable module before creating any Recreatable.

## Park

`./park.sh [--env <slug>]` supplies Recreatable absence for that invocation and applies one complete Terraform plan. It does not persist Parked configuration, inspect State to build a preserve list, or use targets. Repeating Apply restores Recreatables.

Park keeps every Durable and its Cloud Project membership. They remain provider-visible and may continue billing.

## Teardown

`./teardown.sh [--env <slug>]` is the only normal operation that removes Durables. Terraform requires literal `prevent_destroy`, so Teardown temporarily installs the complete override in `internals/terraform/modules/durables/` and pairs it with `allow_durable_destroy=true`. A module precondition rejects either half by itself, and the script removes the override on exit.

## Structural-model adoption

There is no in-place State migration or compatibility path from the superseded root-resource layout. Adopt this shape by explicitly tearing down and recreating the disposable test Environment. Review the destructive plan before confirming Teardown; normal Apply, Park, and Teardown after adoption require no imports, State edits, targets, or provider-console repair.
