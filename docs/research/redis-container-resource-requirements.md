# Minimal resource requirements for a Redis container

**Researched:** 2026-07-28  
**Question:** What are the minimal resource requirements for a container running Redis?  
**Scope:** Redis Open Source in a container (Docker/Podman). Redis Software (enterprise) node hardware tables are out of scope except as a contrast. No Propraetor-specific sizing experiment was run.  
**Method:** Summary of Redis official documentation already reviewed (FAQ, memory optimization, eviction, admin, Docker install). No additional research beyond that pass.

---

## Verdict

Redis publishes **no fixed official container CPU/RAM floor**. Size the container to the dataset and persistence mode.

1. **Absolute process floor:** an empty 64-bit Redis Open Source instance uses about **~3 MB** of memory ([Redis FAQ — memory footprint](https://redis.io/docs/latest/develop/get-started/faq/)).
2. **CPU is rarely the limiting factor.** Redis is typically memory- or network-bound; a fraction of a core is enough for light cache/queue use ([same FAQ](https://redis.io/docs/latest/develop/get-started/faq/)).
3. **Practical container starts** (rules of thumb, not Redis-mandated minima):

| Use | Memory | CPU | Disk |
| --- | --- | --- | --- |
| Idle / smoke test | 32–64 MiB | 0.05–0.1 cores | none (no persistence) |
| Small cache / queues | 128–512 MiB | 0.1–0.5 cores | optional |
| With RDB/AOF | ~2× peak dataset | same | enough for dump + AOF |

4. **Do not use Redis Software hardware minima** (e.g. multi-GB RAM per node) as guidance for a plain OSS Redis container; that product is a different deployment model ([Redis Software hardware requirements](https://redis.io/docs/latest/operate/rs/installing-upgrading/install/plan-deployment/hardware-requirements/)).

---

## Rules that matter more than the floor

1. **Set `maxmemory` below the container memory limit** (often ~70–80% of the cgroup limit) so process overhead, fragmentation, and replication/persistence buffers do not trigger OOM kills. `maxmemory` caps dataset (and related) memory; small extra allocations remain possible ([memory optimization](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/memory-optimization/), [eviction / `maxmemory`](https://redis.io/docs/latest/develop/reference/eviction/)).
2. **With persistence, plan for peak memory up to ~2× normal use** during RDB save or AOF rewrite on write-heavy workloads ([admin guide](https://redis.io/docs/latest/operate/oss_and_stack/management/admin/)). Provision for peak usage, not average ([memory allocation notes](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/memory-optimization/)).
3. **Always set a container memory limit.** Without `maxmemory`, Redis keeps allocating and can exhaust host memory ([memory optimization](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/memory-optimization/)).
4. **Replication/persistence buffers** are not fully counted against `maxmemory` for eviction; leave RAM free for them when those features are enabled ([eviction docs](https://redis.io/docs/latest/develop/reference/eviction/)).

---

## Worked starting point

For a tiny sidecar cache with no persistence: **64–128 MiB memory + ~100m CPU** is a common workable start. Raise memory to match measured `INFO memory` and peak key volume. Official Docker run docs do not prescribe resource limits ([Redis Docker install](https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/docker/)).

---

## Sources

- [Redis FAQ — memory footprint and CPU](https://redis.io/docs/latest/develop/get-started/faq/)
- [Memory optimization](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/memory-optimization/)
- [Using memory as an LRU cache / `maxmemory`](https://redis.io/docs/latest/develop/reference/eviction/)
- [Redis admin / operations notes](https://redis.io/docs/latest/operate/oss_and_stack/management/admin/)
- [Install Redis with Docker](https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/docker/)
- [Redis Software hardware requirements](https://redis.io/docs/latest/operate/rs/installing-upgrading/install/plan-deployment/hardware-requirements/) (contrast only)
