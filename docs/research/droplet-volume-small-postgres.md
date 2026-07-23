# Droplet + Block Storage Volume for small PostgreSQL

**Researched:** 2026-07-23  
**Question:** Is a DigitalOcean Droplet with an attached Block Storage Volume a realistic option for running a **small** PostgreSQL database (dev / small production, modest data size and concurrency — not a large multi-tenant OLTP system)?  
**Scope:** Primary sources only — DigitalOcean product docs and PostgreSQL official docs. Framed for a later architecture decision vs Managed Databases; this note is not an ADR.

---

## Verdict

**Yes, conditionally — realistic for small/dev and modest single-node production if the team accepts self-managed Postgres ops.** DigitalOcean officially positions Volumes as suitable for “database data directories,” publishes SSD-backed IOPS/throughput floors that are ample for modest workloads, and treats volumes as independent of the Droplet (survive destroy/rebuild and reattach in the same datacenter). The main trade-off vs Managed Databases is operational: you own backups, updates, monitoring, and HA; volume snapshots alone are crash-consistent, not application-consistent, unless you coordinate with Postgres. It stops being a good fit when you need standby failover, 7-day PITR without building it yourself, multi-datacenter durability of the data volume, or when ops burden exceeds what “small” justifies.

---

## 1. DigitalOcean Block Storage / Volumes

### Facts

**What volumes are**

- Volumes are **network-attached block storage**. Attached to a Droplet, they “function like local block devices” and can be partitioned, formatted, and mounted with standard tools. ([Volume Features](https://docs.digitalocean.com/products/volumes/details/features/))
- They are independent resources: data lives outside any individual Droplet and is replicated across multiple hosts in DO’s Ceph-based storage cluster; volumes are encrypted at rest with LUKS. ([Volume Features](https://docs.digitalocean.com/products/volumes/details/features/))

**Size, attach, and regional constraints**

- Size range: **1 GiB to 16 384 GiB (16 TiB)**. ([Volume Limits](https://docs.digitalocean.com/products/volumes/details/limits/))
- A volume can attach to **only one Droplet at a time**. ([Volume Limits](https://docs.digitalocean.com/products/volumes/details/limits/))
- Maximum **15 volumes** per Droplet (and per DOKS node). ([Volume Limits](https://docs.digitalocean.com/products/volumes/details/limits/))
- Volumes are **region-/datacenter-specific**. You can only move them between Droplets in the **same datacenter**; you cannot transfer volumes or volume snapshots to another region (workaround: new volume + copy tools such as `rsync`). ([Volume Availability](https://docs.digitalocean.com/products/volumes/details/availability/); [Volume Quickstart](https://docs.digitalocean.com/products/volumes/getting-started/quickstart/); move/reattach workflow also described under create/move docs)
- Volumes are created in the same region and project as the Droplet they attach to. ([Create Volumes](https://docs.digitalocean.com/products/volumes/how-to/create/))
- Volumes are available in all listed DO regions in DO’s availability matrix (NYC1/2/3, AMS3, SFO2/3, SGP1, LON1, FRA1, TOR1, BLR1, SYD1, ATL1, RIC1, MKC1). ([Volume Availability](https://docs.digitalocean.com/products/volumes/details/availability/))

**IOPS / throughput (published)**

Performance depends on the **Droplet type** the volume is attached to (not on volume size, per DO’s limits/features tables):

| Type | IOPS | Throughput |
| --- | --- | --- |
| Shared | 7,500 | 300 MB/s |
| Shared (burst) | 10,000 | 450 MB/s |
| Dedicated | 10,000 | 450 MB/s |
| Dedicated (burst) | 15,000 | 525 MB/s |

Burst lasts up to **60 seconds**, then cools down for **60 seconds**. Storage is described as SSD-backed. ([Volume Limits](https://docs.digitalocean.com/products/volumes/details/limits/); [Volume Features](https://docs.digitalocean.com/products/volumes/details/features/))

**Attach / detach / resize / survive Droplet destroy**

- **Detach** removes the volume from the Droplet but **keeps the volume and its data**; you can reattach later. Billing continues until the volume is deleted. ([Detach and Delete Volumes](https://docs.digitalocean.com/products/volumes/how-to/detach/))
- Moving between Droplets in the same datacenter: unmount → detach → attach → mount. ([Volume Quickstart](https://docs.digitalocean.com/products/volumes/getting-started/quickstart/))
- **Destroying a Droplet does not destroy attached volumes by default.** Associated volumes (and volume snapshots) are only deleted if you explicitly select them in the destroy flow. ([Destroy a Droplet](https://docs.digitalocean.com/products/droplets/how-to/destroy/))
- **Resize:** you can **increase** size (not decrease). DO recommends unmounting before resize and taking a snapshot first; after resize you must expand the filesystem (`resize2fs` / `xfs_growfs`). ([Increase Volume Size](https://docs.digitalocean.com/products/volumes/how-to/increase-size/))
- Features page also states you can increase size **without powering off** the attached Droplet; the how-to still recommends unmount before resize to prevent corruption — treat unmount as the safer documented path for DB data. ([Volume Features](https://docs.digitalocean.com/products/volumes/details/features/); [Increase Volume Size](https://docs.digitalocean.com/products/volumes/how-to/increase-size/))

**Snapshots / backups**

- Volumes are **not included in Droplet backups**. Protect volume data with **volume snapshots**, then create new volumes from those snapshots. ([Volume Limits](https://docs.digitalocean.com/products/volumes/details/limits/))
- Volume snapshots are **crash-consistent** (storage freezes writes at a point in time) but **do not guarantee filesystem or application consistency**. DO says if apps are writing, power off the Droplet, run `sync`, **or stop any database services** before snapshotting. ([Snapshot Volumes](https://docs.digitalocean.com/products/snapshots/how-to/snapshot-volumes/))

**Mount / filesystem guidance (first-party)**

- Recommended mount options (auto and manual): `defaults,nofail,discard,noatime`. ([Mount and Unmount](https://docs.digitalocean.com/products/volumes/how-to/mount-unmount/); [Create Volumes](https://docs.digitalocean.com/products/volumes/how-to/create/))
- Filesystem choices on create: **Ext4** (default; stability) or **XFS** (large files / write-heavy). ([Create Volumes](https://docs.digitalocean.com/products/volumes/how-to/create/))
- Persistent mounting via `/etc/fstab` or systemd automount units; remount required after each attach if not configured for boot. ([Mount and Unmount](https://docs.digitalocean.com/products/volumes/how-to/mount-unmount/))

**Pricing (high level)**

- Volumes: **$0.10 per GiB per month**, hourly accrual; charged **whether or not attached**. ([Volume Pricing](https://docs.digitalocean.com/products/volumes/details/pricing/))
- Volume snapshots: **$0.06 per GiB per month** (plus a $0.01 minimum charge for tiny/short-lived snapshots). ([Snapshots Pricing](https://docs.digitalocean.com/products/snapshots/details/pricing/))

### Implications

- Putting Postgres `data` (and ideally WAL) on a volume — not the Droplet root disk — matches DO’s product model: durable, reattachable storage that outlives Host rebuilds.
- Same-datacenter attach means a volume is **not** a multi-region DR mechanism by itself.
- Published IOPS/throughput are fixed by Droplet class; upsizing the volume alone does not buy more IOPS.

---

## 2. Running databases on volumes / Droplets vs Managed Databases

### Facts

**DO guidance on volumes for databases**

- Official use cases for Volumes explicitly include **“Database data directories.”** ([Volume Features](https://docs.digitalocean.com/products/volumes/details/features/))
- Broader use-case list also covers web content, backups/archives, etc. ([Volume Features](https://docs.digitalocean.com/products/volumes/details/features/))
- Marketplace offers 1-Click Postgres-on-Droplet images (Postgres runs on a Droplet you manage). Example: [PostgreSQL on Ubuntu 24.04 marketplace](https://docs.digitalocean.com/products/marketplace/catalog/postgresql-on-ubuntu24-04/). That is self-managed, not Managed Databases.

**Operational caveats from DO (volumes)**

- Unmount before detach/resize; stop processes using the mount (`lsof`) to avoid data loss/errors. ([Detach](https://docs.digitalocean.com/products/volumes/how-to/detach/); [Mount/Unmount](https://docs.digitalocean.com/products/volumes/how-to/mount-unmount/))
- Droplet backups **omit** volume data — separate snapshot strategy required. ([Volume Limits](https://docs.digitalocean.com/products/volumes/details/limits/))
- Volume snapshots: stop database services (or power off / `sync`) for consistency expectations DO documents. ([Snapshot Volumes](https://docs.digitalocean.com/products/snapshots/how-to/snapshot-volumes/))

**Managed Databases for PostgreSQL (comparison baseline)**

DO presents Managed Databases as “an alternative to manually installing, configuring, maintaining, and securing databases.” ([Managed Databases](https://docs.digitalocean.com/products/databases/))

Documented Managed Postgres cluster features include:

| Capability | What DO documents |
| --- | --- |
| Backups | Daily full backups + WAL for **point-in-time restore within the previous seven days**; backup time not user-modifiable; restores create a **new** cluster. ([PostgreSQL Features](https://docs.digitalocean.com/products/databases/postgresql/details/features/); [Restore from Backups](https://docs.digitalocean.com/products/databases/postgresql/how-to/restore-from-backups/)) |
| Failover / HA | All clusters have **automated failover** (replace degraded nodes). **High availability** (service stays up on primary failure) requires **≥1 standby node**. Without standbys, primary failure means downtime until reprovision (time depends on data size). ([Managed Databases](https://docs.digitalocean.com/products/databases/); [Add Standby Nodes](https://docs.digitalocean.com/products/databases/postgresql/how-to/add-standby-nodes/)) |
| Standbys | Up to **two** standbys; supported on plans with **≥2 GiB RAM**. ([Add Standby Nodes](https://docs.digitalocean.com/products/databases/postgresql/how-to/add-standby-nodes/)) |
| Security / ops | LUKS at rest, SSL in transit; selectable weekly OS/engine updates; metrics/alerting; VPC by default. ([PostgreSQL Features](https://docs.digitalocean.com/products/databases/postgresql/details/features/); [Managed Databases](https://docs.digitalocean.com/products/databases/)) |
| Pricing (entry) | Single-node clusters from **$15.00/mo** (1 GiB RAM); DO recommends these for **preliminary development and testing** (not highly available, but with automatic failover). HA clusters from **$30.00/mo** for a 2 GiB/1 vCPU primary **plus** a matching standby. Extra storage **$0.21/GiB/mo**. ([PostgreSQL Pricing](https://docs.digitalocean.com/products/databases/postgresql/details/pricing/)) |
| WAL backup cadence note | If no running nodes remain to copy from, recovery uses the most recent backup + WAL; WAL is backed up **every five minutes**, so recent writes may be lost in that edge case. ([Managed Databases](https://docs.digitalocean.com/products/databases/)) |

### Implications (self-managed Host+Volume vs Managed)

For a **small** DB, Managed gives you PITR, optional standby HA, patching, and metrics out of the box. Host+Volume gives you cheaper/flexible block storage ($0.10/GiB vs $0.21/GiB managed extra storage) and reuse of existing Host provisioning — but you must implement equivalent backup, upgrade, and availability practices yourself. Neither path is “set and forget” without a backup plan; Managed’s retention window is fixed at seven days in DO’s docs.

---

## 3. PostgreSQL storage / durability requirements (relevant to block storage)

### Facts

**What Postgres needs from storage**

- Committed transaction data must land in a **nonvolatile** area safe from power loss, OS failure, and hardware failure (except failure of that storage itself). Writing to permanent storage (disk or equivalent) is the normal way to meet that. Disks that survive can be moved to similar hardware and committed data remains. ([Reliability](https://www.postgresql.org/docs/current/wal-reliability.html))
- Postgres relies on OS facilities to force writes out of the buffer cache (`wal_sync_method` / `fsync`). Administrators must ensure the storage stack honors durability (caches, flush behavior). ([Reliability](https://www.postgresql.org/docs/current/wal-reliability.html); [WAL configuration — `fsync`](https://www.postgresql.org/docs/current/runtime-config-wal.html))
- **WAL:** data file changes are logged and WAL is flushed to permanent storage before those changes need to be durable at commit; crash recovery replays WAL (REDO). ([WAL intro](https://www.postgresql.org/docs/current/wal-intro.html))
- Turning **`fsync` off** can cause unrecoverable corruption after crash/power loss; only advisable if the DB can be easily recreated from external data. ([WAL configuration](https://www.postgresql.org/docs/current/runtime-config-wal.html))

**Network-attached / remote block storage**

- PostgreSQL’s reliability chapter discusses OS and drive/controller write caches; it does **not** specially forbid network-attached block devices. The requirement is that `fsync`/sync methods actually reach durable media. ([Reliability](https://www.postgresql.org/docs/current/wal-reliability.html))
- DigitalOcean documents Volumes as network-attached but presented as local block devices, with Ceph replication and encryption — not as “unsafe for databases.” ([Volume Features](https://docs.digitalocean.com/products/volumes/details/features/))

**Backup / restore when self-managing**

Postgres documents three approaches: SQL dump, filesystem-level backup, continuous archiving (PITR). ([Backup and Restore](https://www.postgresql.org/docs/current/backup.html))

Filesystem-level specifics:

- A naive copy while the server is running is **not** a usable backup; the server must be shut down for a simple file copy, **or** you use a consistent/frozen volume snapshot (treated like a crash; WAL replay on restore; include WAL), **or** continuous archiving. ([File System Level Backup](https://www.postgresql.org/docs/current/backup-file.html))
- That aligns with DO’s statement that volume snapshots are crash-consistent and that databases should be stopped (or Droplet powered off / `sync`) for safer snapshots. ([Snapshot Volumes](https://docs.digitalocean.com/products/snapshots/how-to/snapshot-volumes/))

### Implications

- Keep `fsync` on; put the data directory on the volume; treat volume snapshots as **crash-consistent** backups unless coordinated with Postgres (stop service, or `pg_backup_start`/continuous archiving patterns from Postgres docs — continuous archiving details are in [Continuous Archiving](https://www.postgresql.org/docs/current/continuous-archiving.html)).
- Moving a volume to a rebuilt Droplet is consistent with Postgres’s “move the disks to another machine” recovery story — provided the cluster files are intact and you remount/configure correctly.

---

## 4. Realistic verdict for “small” Postgres

### Synthesis

| Scenario | Realistic? | Why (sourced) |
| --- | --- | --- |
| Dev / staging on existing Host + Volume | **Yes** | DO lists database data dirs as a volume use case; detach/reattach and Droplet destroy-without-volume-delete support rebuild workflows. |
| Small single-node production, modest size/concurrency, team will operate Postgres | **Yes, with conditions** | Published volume IOPS/throughput are high relative to “modest” needs; durability model (Ceph + Postgres WAL/`fsync`) is coherent; you must own backups (dumps and/or coordinated snapshots / WAL archiving), updates, monitoring. |
| Need HA / low downtime on host failure without building replicas | **Prefer Managed (or self-built replicas)** | Managed HA needs standby nodes; single Host+Volume is a single compute failure domain (volume helps data survival, not automatic failover). |
| Need turnkey 7-day PITR | **Prefer Managed** | Documented on Managed; self-managed must implement continuous archiving or equivalent. |
| Multi-region / multi-AZ volume for the same disk | **Not available as a DO volume feature** | Volumes stay in one datacenter; cross-region requires copy. |
| Large multi-tenant OLTP / sustained high concurrency | **Out of scope / not validated here** | No DO first-party Postgres-on-Volume benchmark suite in current product docs; IOPS caps are per Droplet class with burst limits. |

**What “small” implies here (operational, not a DO-defined SLA):** data fits comfortably within a single volume and Droplet RAM/CPU; concurrency well below what would saturate published IOPS; willingness to run one primary without DO-managed standbys; backup RPO/RTO that can be met with dumps + occasional snapshots or self-built WAL archiving.

**When this stops being realistic:** required automatic failover with near-zero downtime; compliance/ops policy that forbids self-managed databases; need for DO-managed PITR without owning backup infrastructure; growth into sustained I/O that needs more than shared/dedicated volume limits allow without larger Droplet classes; multi-datacenter durability of a single attached volume.

### Facts vs implications (short)

- **Fact:** DO markets Volumes for database data directories and publishes concrete attach, size, IOPS, pricing, and snapshot semantics.  
  **Implication:** Self-managed Postgres on Host+Volume is a **supported product pattern**, not an undocumented hack.
- **Fact:** Volumes survive Droplet destroy unless you opt in to deleting them; they reattach in-region.  
  **Implication:** Separating Host lifecycle from data lifecycle is first-class — useful for this repo’s Host provisioning model.
- **Fact:** Managed Postgres includes daily + PITR (7 days), optional standbys for HA, automatic updates.  
  **Implication:** Choosing Host+Volume trades money/control for **ops ownership**; for true “small production” that is often acceptable, for “we don’t want to be DBAs” it is not.

---

## Open questions / gaps

Primary sources do **not** answer (do not invent):

1. **Latency / Postgres-specific TPS** — Current DO Volumes docs publish IOPS and MB/s by Droplet type, not p99 latency or Postgres benchmark numbers for Volumes.
2. **Whether root-disk Postgres vs volume Postgres differs in durability guarantees** beyond “volumes are Ceph-replicated outside the Droplet” — no head-to-head durability SLA comparison in the docs reviewed.
3. **Exact behavior of live volume resize while Postgres is writing** — Features say size can increase without powering off; how-to recommends unmount; no Postgres-specific procedure.
4. **Multi-AZ within a region for a single volume** — Docs describe same-datacenter attach and Ceph replication across hosts; they do not define customer-visible AZ failover for a self-managed volume+Postgres pair.
5. **Compliance certifications / shared-responsibility details** specific to self-managed Postgres on Volumes vs Managed Databases — not covered in the pages used for this note.
6. **Cost of Droplet+Volume vs Managed for a concrete size/plan** — requires picking a Host size from Droplet pricing (out of scope unless fixed); volume and managed storage unit prices are cited above for comparison only.

---

## Primary sources

- [Volume Features](https://docs.digitalocean.com/products/volumes/details/features/)
- [Volume Limits](https://docs.digitalocean.com/products/volumes/details/limits/)
- [Volume Pricing](https://docs.digitalocean.com/products/volumes/details/pricing/)
- [Volume Availability](https://docs.digitalocean.com/products/volumes/details/availability/)
- [Create Volumes](https://docs.digitalocean.com/products/volumes/how-to/create/)
- [Mount and Unmount Volumes](https://docs.digitalocean.com/products/volumes/how-to/mount-unmount/)
- [Detach and Delete Volumes](https://docs.digitalocean.com/products/volumes/how-to/detach/)
- [Increase Volume Size](https://docs.digitalocean.com/products/volumes/how-to/increase-size/)
- [Volume Quickstart](https://docs.digitalocean.com/products/volumes/getting-started/quickstart/)
- [Destroy a Droplet](https://docs.digitalocean.com/products/droplets/how-to/destroy/)
- [Snapshot Volumes](https://docs.digitalocean.com/products/snapshots/how-to/snapshot-volumes/)
- [Snapshots Pricing](https://docs.digitalocean.com/products/snapshots/details/pricing/)
- [Managed Databases](https://docs.digitalocean.com/products/databases/)
- [PostgreSQL Features (Managed)](https://docs.digitalocean.com/products/databases/postgresql/details/features/)
- [PostgreSQL Pricing (Managed)](https://docs.digitalocean.com/products/databases/postgresql/details/pricing/)
- [Restore Managed Postgres from Backups](https://docs.digitalocean.com/products/databases/postgresql/how-to/restore-from-backups/)
- [Add Standby Nodes](https://docs.digitalocean.com/products/databases/postgresql/how-to/add-standby-nodes/)
- [PostgreSQL Reliability](https://www.postgresql.org/docs/current/wal-reliability.html)
- [PostgreSQL WAL](https://www.postgresql.org/docs/current/wal-intro.html)
- [PostgreSQL WAL settings (`fsync`)](https://www.postgresql.org/docs/current/runtime-config-wal.html)
- [PostgreSQL Backup and Restore](https://www.postgresql.org/docs/current/backup.html)
- [PostgreSQL File System Level Backup](https://www.postgresql.org/docs/current/backup-file.html)
