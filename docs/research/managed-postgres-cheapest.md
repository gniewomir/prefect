# Cheapest managed PostgreSQL offerings

**Researched:** 2026-07-23  
**Question:** Across major cloud providers and DBaaS vendors, what is the absolute cheapest entry tier for a *usable managed* PostgreSQL instance (provider runs Postgres for you — backups, patching; HA optional)?

**Scope:** First-party pricing pages and docs only. Self-managed Postgres on a bare VM is noted only as a cheaper *non-managed* alternative. Fly.io Postgres is excluded from the “managed” ranking (Fly documents it as unmanaged).

**Method notes:** Monthly figures use ~730 hours/month where only hourly rates are published. Hyperscaler totals usually need **compute + provisioned storage** (and sometimes backups/egress). Region assumptions are called out when material.

---

## Verdict

| Lens | Winner | Price | Caveat |
| --- | --- | --- | --- |
| **Absolute cheapest (including free)** | Tie among permanent free tiers — strongest contenders: **Neon Free**, **Aiven Free**, **Supabase Free** | **$0/mo** | Sleep / pause / power-off, tiny storage, not production-grade |
| **Cheapest paid, always-on-ish (no free-tier sleep)** | **Aiven Developer** | **$5/mo** | 1 GB RAM / 8 GB disk; limited region choice on cheapest plans |
| **Cheapest DO-comparable classic managed cluster** | **DigitalOcean Managed PostgreSQL** Basic | **$15.15/mo** | Predictable; 1 GiB / 10–30 GiB disk |

There is no single “always free + always awake + production SLA” option. For **$0**, Neon / Aiven / Supabase win. For the **lowest paid bill without relying on a free-tier sleep/pause policy**, **Aiven Developer at $5/mo** is the clear floor among surveyed products.

---

## Free / $0 managed Postgres (absolute cheapest)

### Neon — Free plan — **$0/mo**

| | |
| --- | --- |
| **Product** | Neon Free |
| **Price** | $0/month (permanent free plan, not a time-limited trial) |
| **Included** | 100 CU-hours/project; storage **0.5 GB**/project; egress **5 GB**; autoscaling up to 2 CU; scale-to-zero after **5 minutes** inactivity |
| **Caveats** | Hitting CU/storage/egress limits **suspends compute** until next billing month. Cold starts after scale-to-zero. |
| **Source** | [neon.tech/pricing](https://neon.tech/pricing) |

### Aiven for PostgreSQL — Free — **$0/mo**

| | |
| --- | --- |
| **Product** | Aiven for PostgreSQL Free |
| **Price** | $0/month; no credit card; no time limit |
| **Included** | **1 dedicated VM**, 1 CPU, **1 GB RAM**, **1 GB storage**; backups; networking included; extensions (e.g. PostGIS) |
| **Caveats** | Powers off after inactivity (notified first); `max_connections` = 20; no VPC/static IPs/pooling/integrations; one free service per type per org; not under 99.99% SLA; cloud/region selection constrained |
| **Source** | [aiven.io/pricing?product=pg](https://aiven.io/pricing?product=pg), [aiven.io/free-postgresql-database](https://aiven.io/free-postgresql-database), [docs: free tier](https://aiven.io/docs/products/postgresql/concepts/pg-free-tier) |

### Supabase — Free — **$0/mo**

| | |
| --- | --- |
| **Product** | Supabase Free (includes managed Postgres) |
| **Price** | $0/month |
| **Included** | **500 MB** database; Shared CPU · **500 MB RAM**; 5 GB egress; 2 active free projects |
| **Caveats** | Projects **paused after 1 week of inactivity**; platform is broader than “Postgres only” (Auth/Storage/etc.) |
| **Source** | [supabase.com/pricing](https://supabase.com/pricing) |

### Render Postgres — Free — **$0** (time-limited)

| | |
| --- | --- |
| **Product** | Render Postgres Free |
| **Price** | $0 (explicit **30-day limit**) |
| **Included** | 0.1 CPU, **256 MB RAM**, 100 connections |
| **Caveats** | Not a permanent free tier — expires after 30 days |
| **Source** | [render.com/pricing](https://render.com/pricing) |

### Railway — Free plan credit — effectively **~$0–1/mo**

| | |
| --- | --- |
| **Product** | Railway Free (+ usage-based Postgres as a service/volume) |
| **Price** | Free plan **$0** subscription with **$1 free credit/month**; Hobby starts at **$5/mo** (includes $5 usage) |
| **Included** | Free: max 0.5 GB RAM / 1 vCPU / **0.5 GB** volume per service |
| **Caveats** | Credit is tiny; Postgres is usage-metered (CPU/RAM/volume), not a flat “DB plan.” Trial is a separate one-time **$5** grant |
| **Source** | [railway.com/pricing](https://railway.com/pricing), [docs.railway.com/reference/pricing/plans](https://docs.railway.com/reference/pricing/plans) |

### AWS RDS / Aurora — Free Tier (new accounts / credits) — **$0 for a limited period**

| | |
| --- | --- |
| **Product** | Amazon RDS for PostgreSQL (and Aurora) under AWS Free Tier |
| **Price** | New customers: Free plan exploration with credits (offer details on AWS Free Tier pages); legacy: 12-month free tier for older signups |
| **Included (Free plan / eligible)** | `db.t3.micro` / `db.t4g.micro` among eligible engines including PostgreSQL; Aurora Serverless Free-plan caps (e.g. up to 4 ACU / 1 GiB storage per cluster — see AWS page) |
| **Caveats** | **Not “always free forever”** for classic RDS in the old sense for all accounts; after credits/limits, on-demand rates apply |
| **Source** | [aws.amazon.com/rds/free](https://aws.amazon.com/rds/free/), [aws.amazon.com/rds/postgresql/pricing](https://aws.amazon.com/rds/postgresql/pricing/) |

### Oracle Cloud — Always Free Autonomous DB — **not PostgreSQL**

Oracle **Always Free** includes Autonomous Database (Oracle engine), **not** OCI Database with PostgreSQL. Managed Postgres on OCI is a **paid** service (compute + optimized storage + service fee).  
Sources: [oracle.com/cloud/free](https://www.oracle.com/cloud/free/), [oracle.com/cloud/postgresql/pricing](https://www.oracle.com/cloud/postgresql/pricing/).

---

## Cheapest paid managed Postgres (floor prices)

### Aiven Developer — **$5/mo** ← cheapest paid surveyed

| | |
| --- | --- |
| **Product** | Aiven for PostgreSQL Developer |
| **Price** | **$5/month** |
| **Included** | 1 dedicated VM, 1 CPU, **1 GB RAM**, **8 GB storage**; all-inclusive hourly model on higher plans |
| **Caveats** | Cheapest plans cannot pick arbitrary cloud/region; no integrations/connection pooling (per pricing page); Free→Developer is the step for more disk / continuous use |
| **Source** | [aiven.io/pricing?product=pg](https://aiven.io/pricing?product=pg) |

### Render Postgres Basic-256mb — **$6/mo**

| | |
| --- | --- |
| **Product** | Render Postgres Basic-256mb |
| **Price** | **$6/month** |
| **Included** | 0.1 CPU, **256 MB RAM**, 100 connections; expandable storage **$0.30/GB** (paid); logical backups / PITR on paid |
| **Source** | [render.com/pricing](https://render.com/pricing) |

### Crunchy Bridge Hobby-0 — **$9/mo** (+ storage)

| | |
| --- | --- |
| **Product** | Crunchy Bridge (AWS/Azure/GCP) Hobby-0 |
| **Price** | **$9/month** compute; storage **$0.10/GB-month** |
| **Included** | 2 cores, **0.5 GB** memory; backups, PITR, transfer included in machine pricing narrative |
| **Source** | [crunchydata.com/pricing](https://www.crunchydata.com/pricing) |

### GCP Cloud SQL (shared-core) — **~$7.7/mo compute + storage**

| | |
| --- | --- |
| **Product** | Cloud SQL for PostgreSQL `db-f1-micro` |
| **Price** | **$0.0105/hour** ≈ **$7.67/mo** (730h) in Iowa (`us-central1`) for shared-core; SSD ≈ **$0.000232877/GiB-hour** ≈ **$0.17/GiB-month** |
| **Included** | Shared CPU, **0.6 GB** RAM; **not covered by Cloud SQL SLA** |
| **Caveats** | Storage billed separately; HA doubles instance rate |
| **Source** | [cloud.google.com/sql/pricing](https://cloud.google.com/sql/pricing) |

### AWS RDS PostgreSQL `db.t4g.micro` — **~$11.68/mo + storage**

| | |
| --- | --- |
| **Product** | Amazon RDS for PostgreSQL |
| **Price (us-east-1, Single-AZ)** | **$0.016/hour** ≈ **$11.68/mo** (`db.t4g.micro`); gp2 storage **$0.115/GB-month** (20 GB min common → ~$2.30) ⇒ **~$14/mo** all-in for a tiny instance |
| **Included** | 2 vCPU burstable, **1 GiB** RAM; Multi-AZ doubles instance (~$0.032/hr) |
| **Source** | AWS Price List API `AmazonRDS` us-east-1 On-Demand (fetched 2026-07-23); storage from same offer file; overview [aws.amazon.com/rds/postgresql/pricing](https://aws.amazon.com/rds/postgresql/pricing/) |

### Azure Database for PostgreSQL Flexible Server — **$12.41/mo + storage**

| | |
| --- | --- |
| **Product** | Flexible Server Burstable **B1ms** |
| **Price** | **$12.41/month** (compute, USD list as shown on pricing page) |
| **Included** | 1 vCore, **2 GiB** RAM; storage is **Premium SSD / SSD v2**, provisioned separately (docs show Premium SSD sizes from **32 GiB** upward) |
| **Caveats** | All-in cost exceeds compute-only sticker; region/currency matter |
| **Source** | [azure.microsoft.com/pricing/details/postgresql/flexible-server](https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/), [Storage concepts](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-storage) |

### DigitalOcean Managed Databases PostgreSQL — **$15.15/mo**

| | |
| --- | --- |
| **Product** | DigitalOcean Managed PostgreSQL Basic Regular |
| **Price** | **$0.02254/hr · $15.15/mo** |
| **Included** | **1 GiB** RAM, 1 vCPU, disk **10–30 GiB** (extra disk **$0.215/GiB/mo**) |
| **Source** | [digitalocean.com/pricing/managed-databases](https://www.digitalocean.com/pricing/managed-databases) |

### Scaleway Managed PostgreSQL — **~€11.4/mo + storage** (Paris)

| | |
| --- | --- |
| **Product** | Managed PostgreSQL / MySQL Cost Optimized **DB-DEV-S** |
| **Price** | **€0.0156/hour** main node ≈ **€11.39/mo** (~$12–13 USD depending on FX) before tax |
| **Included** | 2 vCPU, **2 GB** RAM; Block Storage 5K **€0.0993/GB/mo**; backups **€0.03/GB/mo** |
| **Source** | [scaleway.com/en/pricing/managed-databases](https://www.scaleway.com/en/pricing/managed-databases/) |

### Akamai / Linode Managed Databases — **$16/mo**

| | |
| --- | --- |
| **Product** | Managed Databases PostgreSQL Nanode 1GB (`g6-nanode-1`) |
| **Price** | **$16/month** (1 node); 3-node **$37/month** |
| **Included** | 1 vCPU, **1 GB** RAM, **9 GB** disk (API: memory 1024 MiB, disk 9216 MiB) |
| **Source** | Linode API `GET /databases/types` (2026-07-23); product overview [linode.com/products/databases](https://www.linode.com/products/databases/) |

### Supabase Pro — **from $25/mo**

| | |
| --- | --- |
| **Product** | Supabase Pro (paid always-on projects) |
| **Price** | **$25/month** plan + compute (Micro **$10/mo**, covered by **$10** compute credits on Pro) |
| **Included** | 8 GB disk/project included; daily backups 7 days; no pausing |
| **Source** | [supabase.com/pricing](https://supabase.com/pricing) |

### Neon Launch (always-on) — usage-based, typically **≫ $5** if never suspended

| | |
| --- | --- |
| **Product** | Neon Launch |
| **Price** | Pay-as-you-go: compute **$0.106/CU-hour**; storage **$0.35/GB-month**; no monthly minimum |
| **Caveats** | Idle can be $0 with scale-to-zero; **disabling** scale-to-zero means continuous CU billing (e.g. 0.25 CU × 730h × $0.106 ≈ **~$19/mo** compute alone) |
| **Source** | [neon.tech/pricing](https://neon.tech/pricing) |

### Aiven Hobbyist — **from $12/mo**

| | |
| --- | --- |
| **Product** | Aiven Hobbyist |
| **Price** | From **$12/month** ($0.02/hour) |
| **Included** | 1 VM, 1 CPU, 1 GB RAM, 8 GB storage (same shape class as Developer on the plan table; higher tiers add HA/SLA) |
| **Source** | [aiven.io/pricing?product=pg](https://aiven.io/pricing?product=pg) |

---

## Explicitly not ranked as “managed Postgres DBaaS”

| Offering | Why excluded / noted |
| --- | --- |
| **Fly.io Postgres** | Documented as **“Fly Postgres (Unmanaged)”** — app with sugar, not a managed DB service. [fly.io/docs/postgres](https://fly.io/docs/postgres/) |
| **Hetzner Cloud** | No managed PostgreSQL product; cheap VMs only (e.g. Cost-Optimized from **€5.99/mo**). Postgres on a VM is **self-managed**. [hetzner.com/cloud](https://www.hetzner.com/cloud) |
| **Hetzner Managed Server** | Web-hosting style managed server with MariaDB/PostgreSQL available in the stack — not a standalone Postgres DBaaS comparable to RDS/DO. [hetzner.com/managed-server](https://www.hetzner.com/managed-server) |
| **OCI Database with PostgreSQL** | Managed, but **paid** (OCPU + optimized storage + fees); Always Free Autonomous is **Oracle**, not Postgres. [Pricing](https://www.oracle.com/cloud/postgresql/pricing/), [Billing](https://docs.oracle.com/en-us/iaas/Content/postgresql/billing.htm) |

**Non-managed cheaper alternative (brief):** A small Hetzner/DO Droplet running Postgres yourself can undercut managed entry prices, but you own backups, patching, and failover.

---

## Comparison snapshot (entry tier)

| Provider | Product | Entry price | Always awake? | Approx. RAM / disk |
| --- | --- | --- | --- | --- |
| Neon | Free | $0 | No (scale-to-zero 5m) | shared CU / 0.5 GB |
| Aiven | Free | $0 | No (powers off if idle) | 1 GB / 1 GB |
| Supabase | Free | $0 | No (pause after 1 week idle) | 0.5 GB / 0.5 GB |
| Aiven | Developer | **$5** | Yes (paid) | 1 GB / 8 GB |
| Render | Basic-256mb | $6 | Yes | 256 MB / paid storage |
| GCP | Cloud SQL db-f1-micro | ~$7.7 + disk | Yes | 0.6 GB + disk |
| Crunchy | Hobby-0 | $9 + disk | Yes | 0.5 GB + disk |
| AWS | RDS db.t4g.micro | ~$11.7 + disk | Yes | 1 GB + disk |
| Azure | Flexible B1ms | $12.41 + disk | Yes | 2 GB + disk |
| Scaleway | DB-DEV-S | ~€11.4 + disk | Yes | 2 GB + disk |
| DigitalOcean | Managed PG Basic | $15.15 | Yes | 1 GB / 10–30 GB |
| Akamai/Linode | Nanode 1GB | $16 | Yes | 1 GB / 9 GB |
| Supabase | Pro | from $25 | Yes | Micro 1 GB + 8 GB disk |

---

## Important caveats

1. **“$0” ≠ production.** Free tiers sleep, pause, power off, or expire; storage is sub-GB to 1 GB; connection limits are low; SLAs usually absent.
2. **Hyperscaler stickers omit storage.** AWS/GCP/Azure entry compute looks mid-pack until you add minimum SSD (often 10–32 GiB) and backups/egress.
3. **Serverless Postgres (Neon) can be cheapest *or* expensive** depending on whether compute stays suspended. Always-on Neon is not the price leader.
4. **“Managed” marketing varies.** Prefer vendors that explicitly run backups/patching/HA for you (RDS, Cloud SQL, DO, Aiven, Crunchy, Render paid, etc.). Fly’s own docs say unmanaged.
5. **Prices move.** Figures were fetched **2026-07-23** from first-party pages/APIs; re-check before budgeting.

---

## Sources (primary)

- Neon: https://neon.tech/pricing  
- Supabase: https://supabase.com/pricing  
- DigitalOcean: https://www.digitalocean.com/pricing/managed-databases  
- AWS RDS PostgreSQL: https://aws.amazon.com/rds/postgresql/pricing/  
- AWS RDS Free Tier: https://aws.amazon.com/rds/free/  
- AWS Price List API: `https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/us-east-1/index.json` (fetched 2026-07-23)  
- GCP Cloud SQL: https://cloud.google.com/sql/pricing  
- Azure Flexible Server: https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/  
- Azure storage concepts: https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-storage  
- Aiven: https://aiven.io/pricing?product=pg · https://aiven.io/free-postgresql-database · https://aiven.io/docs/products/postgresql/concepts/pg-free-tier  
- Render: https://render.com/pricing  
- Crunchy Bridge: https://www.crunchydata.com/pricing  
- Railway: https://railway.com/pricing · https://docs.railway.com/reference/pricing/plans  
- Fly.io: https://fly.io/docs/postgres/ · https://fly.io/docs/about/pricing/  
- Oracle Free Tier: https://www.oracle.com/cloud/free/  
- OCI Postgres pricing/billing: https://www.oracle.com/cloud/postgresql/pricing/ · https://docs.oracle.com/en-us/iaas/Content/postgresql/billing.htm  
- Scaleway: https://www.scaleway.com/en/pricing/managed-databases/  
- Akamai/Linode Databases: https://www.linode.com/products/databases/ · API `GET https://api.linode.com/v4/databases/types`  
- Hetzner Cloud: https://www.hetzner.com/cloud  
