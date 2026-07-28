# Remaining usage on Cursor plan upgrade (annual)

**Researched:** 2026-07-28  
**Question:** What happens to remaining/unused usage (included usage, credits, request quota, etc.) when a user upgrades their Cursor subscription to the next tier, specifically when choosing annual billing?  
**Scope:** Individual plan upgrades (Pro → Pro+ / Ultra); annual billing and any documented difference vs monthly; unused included usage / credits remaining in the current period; proration and credit for unused subscription time; mid-cycle upgrade vs renewal. Teams/Enterprise seat proration is out of scope except where it clarifies vocabulary.  
**Method:** Prefer Cursor Help / Docs (billing, pricing, usage-limits), cursor.com/pricing, first-party blog pricing posts, and official forum staff replies. Community anecdotes are labeled separately.

### Credibility labels used here

| Label | Meaning |
| --- | --- |
| **High** | Cursor docs, Help Center, pricing page, or first-party blog; current first-party |
| **Medium-High** | Named Cursor staff on the official forum |
| **Medium** | Older first-party wording that may be superseded, or staff statements that leave mechanics underspecified |
| **Low** | Unverified user reports / community replies (not staff) |

---

## Verdict

1. **Unused included usage does not carry over** across billing periods, and Cursor does not document a “bank remaining API dollars and add them to the new plan” path. Help Center: unused usage does not roll over; usage resets monthly with the billing cycle ([usage-limits](https://cursor.com/help/models-and-usage/usage-limits) — **High**; [billing](https://cursor.com/help/account-and-billing/billing) — **High**).
2. **A mid-cycle upgrade starts a new subscription and resets usage to the new plan’s full included allowance.** Staff (Condor): upgrading “starts a new subscription with a new billing cycle and resets usage to the allowance of the new plan” ([forum](https://forum.cursor.com/t/guys-how-can-i-get-cursor-pro-like-where/119180) — **Medium-High**). Staff (deanrie): monthly → yearly also starts a new cycle and resets usage limits immediately ([forum](https://forum.cursor.com/t/upgrading-from-monthly-to-yearly-credits-reset-timing-proration/158662) — **Medium-High**). Help Center: upgrade takes effect immediately ([pricing](https://cursor.com/help/account-and-billing/pricing) — **High**).
3. **What is prorated is unused subscription *time* (money), not unused included *usage*.** Staff repeatedly describe canceling the old sub and issuing a prorated credit/refund for remaining days/months ([deanrie](https://forum.cursor.com/t/ask-fee-to-upgrade-subscription-plan-from-pro-to-pro/159652), [deanrie](https://forum.cursor.com/t/plan-upgrade-to-pro-one-say-after-plan-end/147853), [condor](https://forum.cursor.com/t/guys-how-can-i-get-cursor-pro-like-where/119180), [condor](https://forum.cursor.com/t/pricing-questions/124768) — **Medium-High**). When a user asked whether the refund tracks leftover API usage dollars vs calendar time, staff deferred to billing support rather than affirming a usage-based refund ([forum](https://forum.cursor.com/t/plan-upgrade-to-pro-one-say-after-plan-end/147853) — **Medium-High** for the deferral; implication **Medium**).
4. **Annual vs monthly does not change the usage-pool rules.** Individual included usage still “reset[s] monthly” even when the subscription renews yearly ([billing](https://cursor.com/help/account-and-billing/billing) — **High**). Annual billing mainly changes how much *subscription time* remains to prorate when you upgrade mid-commitment.
5. **Annual Pro+ / Ultra exist (as of Feb 2026),** so annual-tier upgrades are a real path ([Colin](https://forum.cursor.com/t/is-yearly-billing-available-for-cursor-pro-plus-subscription/150023) — **Medium-High**; [pricing](https://cursor.com/pricing) — **High** for the Monthly/Yearly UI). Checkout often shows the full new annual price; Stripe proration/credit may land on the final invoice, as account credit, or as a delayed refund—**not always visible at checkout** ([deanrie](https://forum.cursor.com/t/upgrading-from-monthly-to-yearly-credits-reset-timing-proration/158662) — **Medium-High**; user/support anecdotes on annual Pro → Pro+ — **Low** / see §5).
6. **Upgrade mid-cycle ≠ waiting for renewal.** Upgrade: immediate new plan + new cycle + fresh usage. Scheduled downgrade / end-of-period switch: keep current plan until period end ([pricing](https://cursor.com/help/account-and-billing/pricing) — **High**). There is no documented “temporary one-month upgrade while keeping annual Pro” ([deanrie](https://forum.cursor.com/t/question-about-pro-cost-with-active-pro-annual/147625) — **Medium-High**).

**Practical summary:** Remaining included usage is effectively forfeited on upgrade because the cycle resets to the new tier’s full allowance. You are compensated (if at all) for unused *paid time* on the old subscription via Stripe proration/credit/refund—not by carrying leftover usage dollars into the new plan. For annual upgrades with many months left, confirm the exact credit path with support before paying; public docs under-specify the annual→annual money mechanics.

---

## 1. What “remaining usage” means in current Cursor billing

Current individual plans use **two monthly usage pools**, not a single legacy “request quota”:

| Pool | What it covers | Included amounts (summary) |
| --- | --- | --- |
| **Other Models** | Third-party models at API prices | Pro $20 · Pro+ $70 · Ultra $400 |
| **Cursor Models** | Cursor Grok 4.5, Composer 2.5 | “Generous” included usage per plan |

([usage-limits](https://cursor.com/help/models-and-usage/usage-limits), [models-and-pricing](https://cursor.com/docs/models-and-pricing) — **High**)

Documented reset / rollover rules:

- Usage resets **monthly** with the billing cycle; reset date is on the Spending dashboard ([usage-limits](https://cursor.com/help/models-and-usage/usage-limits) — **High**).
- **Individual plans reset monthly** even though the subscription may renew monthly or yearly ([billing](https://cursor.com/help/account-and-billing/billing) — **High**).
- **Unused usage does not roll over** ([usage-limits](https://cursor.com/help/models-and-usage/usage-limits) — **High**; staff [kevinn](https://forum.cursor.com/t/does-the-unused-api-limit-carry-over-to-the-next-month/158327) — **Medium-High**).

So “remaining usage” on an annual plan usually means **leftover allowance in the current month’s pools**, not a year-long unused credit bank.

---

## 2. What Help / Docs say about upgrades (and what they omit)

### Documented

| Claim | Source | Credibility |
| --- | --- | --- |
| Upgrade via Dashboard → Adjust plan → Stripe checkout | [pricing help](https://cursor.com/help/account-and-billing/pricing) | **High** |
| Upgrade **takes effect immediately** (Pro, Pro+, Ultra) | same | **High** |
| Downgrade is **scheduled** for end of billing period | same | **High** |
| Switch monthly → yearly via green “Upgrade Now” banner | same | **High** |
| Switch yearly → monthly: **not mid-plan**; schedule at end of yearly period | same | **High** |
| Hitting the limit → enable on-demand **or upgrade** for more included usage | [usage-limits](https://cursor.com/help/models-and-usage/usage-limits) | **High** |
| Same refund eligibility rules for monthly and annual (14-day / unused-sub rules) | [refunds](https://cursor.com/help/account-and-billing/refunds) | **High** for that policy; **not** the same as upgrade proration |

### Not spelled out in Help/Docs

Help Center does **not** explicitly say, on the upgrade FAQ:

- whether leftover included usage is forfeited, carried, or converted to dollars;
- whether usage counters reset on upgrade;
- how Stripe shows vs applies annual-tier upgrade proration.

Those details currently live in **forum staff answers** (§3–§5).

---

## 3. Mid-cycle tier upgrade: usage reset + new cycle

Staff description of the upgrade machine (tier change):

> upgrading to a new plan starts a new subscription with a new billing cycle and **resets usage to the allowance of the new plan**. Old subscription will be **refunded prorated if not used up**… A new subscription does **not** reduce already consumed Usage Based Pricing.

([Condor](https://forum.cursor.com/t/guys-how-can-i-get-cursor-pro-like-where/119180), 2025-07-17 — **Medium-High**)

Aligned staff wording for Pro → Pro+ mid-cycle:

- Current Pro subscription canceled  
- Prorated credit/refund for unused Pro **days**  
- Pro+ starts immediately; **new billing cycle** from upgrade time  

([deanrie](https://forum.cursor.com/t/ask-fee-to-upgrade-subscription-plan-from-pro-to-pro/159652) — **Medium-High**)

Same pattern for “any plan change (upgrade or downgrade)” in an earlier reply: old sub canceled → prorated refund for unused time → new sub starts ([deanrie](https://forum.cursor.com/t/plan-upgrade-to-pro-one-say-after-plan-end/147853) — **Medium-High**; note: Help Center now documents **scheduled** downgrade for individuals, so treat the “downgrade also cancels immediately” part as possibly outdated — **Medium**).

### Implications for leftover usage

| Situation at upgrade | Documented / staff outcome |
| --- | --- |
| Included usage **fully spent** | New plan’s full allowance starts immediately (staff reset language — **Medium-High**; matches product intent of “upgrade for more usage”) |
| Included usage **partially unused** | No first-party statement that leftover pool dollars transfer. Cycle reset + “unused does not roll over” ⇒ remaining old-plan usage is **not** kept as a stackable balance (**High** + **Medium-High** combined inference; see caveats) |
| On-demand / usage-based charges already incurred | “A new subscription does not reduce already consumed Usage Based Pricing” ([Condor](https://forum.cursor.com/t/guys-how-can-i-get-cursor-pro-like-where/119180) — **Medium-High**); on-demand for consumed usage is generally non-refundable ([refunds](https://cursor.com/help/account-and-billing/refunds) — **High**) |

User asked explicitly whether prorated refund tracks leftover **API usage** vs **calendar time**; staff pointed to `hi@cursor.com` for account-specific math rather than affirming usage-based refund ([deanrie](https://forum.cursor.com/t/plan-upgrade-to-pro-one-say-after-plan-end/147853) — **Medium-High**).

**Inference (Medium):** proration is time-based subscription value, not a cash-out of unused included usage.

---

## 4. Annual billing specifically

### Usage still monthly

Even on yearly subscription payment:

- Subscription renews **yearly** ([billing](https://cursor.com/help/account-and-billing/billing) — **High**).
- Included usage for individuals still **resets monthly** ([billing](https://cursor.com/help/account-and-billing/billing) — **High**).
- Unused monthly usage still **does not roll over** ([usage-limits](https://cursor.com/help/models-and-usage/usage-limits) — **High**).

So choosing annual does **not** create a yearly usage bank that you “upgrade with unused credits.”

### Annual tiers availability

- Historically (mid-2025): staff said **no annual Pro+** yet; upgrade from annual Pro would bill Pro+ **monthly** ([Condor](https://forum.cursor.com/t/guys-how-can-i-get-cursor-pro-like-where/119180) — **Medium-High**, dated).
- Feb 2026: staff (Colin) confirmed **annual Pro+ and Ultra** are available ([forum](https://forum.cursor.com/t/is-yearly-billing-available-for-cursor-pro-plus-subscription/150023) — **Medium-High**).
- Pricing page exposes Monthly/Yearly for Individual plans ([pricing](https://cursor.com/pricing) — **High**). Example annual list prices cited by users/staff: Pro ~$192/yr; Pro+ ~$576/yr (community/staff threads — treat exact dollars as **Medium** / verify at checkout).

### Monthly → yearly (same tier)

Staff (deanrie), April 2026:

- New billing cycle starts immediately; **usage limits reset immediately**.
- Checkout may show full yearly list price; Stripe applies proration for unused monthly days on the **final invoice** (example: ~$2.67 credit for 4 days).

([forum](https://forum.cursor.com/t/upgrading-from-monthly-to-yearly-credits-reset-timing-proration/158662) — **Medium-High**)

### Annual Pro → higher tier (annual or monthly)

Staff pattern for leaving an annual plan:

- No “temporary upgrade while keeping annual Pro” ([deanrie](https://forum.cursor.com/t/question-about-pro-cost-with-active-pro-annual/147625) — **Medium-High**).
- Old annual subscription canceled with **prorated refund** for remaining months; may take several days ([condor](https://forum.cursor.com/t/pricing-questions/124768), [deanrie](https://forum.cursor.com/t/question-about-pro-cost-with-active-pro-annual/147625) — **Medium-High**).
- Staff advise emailing support **before** changing an annual plan for exact refund math ([deanrie](https://forum.cursor.com/t/plan-upgrade-to-pro-one-say-after-plan-end/147853) — **Medium-High**).

**Difference vs monthly (usage):** none documented for pools.  
**Difference vs monthly (money):** more unused prepaid months ⇒ larger prorated credit/refund at stake; delivery mechanism more often reported as delayed / invoice credit / account balance (see §5).

---

## 5. Proration mechanics and annual-upgrade friction

### Official / staff baseline

| Mechanism | What sources say | Credibility |
| --- | --- | --- |
| Stripe calculates proration | Checkout may show list price; credit on final invoice ([deanrie](https://forum.cursor.com/t/upgrading-from-monthly-to-yearly-credits-reset-timing-proration/158662)) | **Medium-High** |
| Refund for unused remaining months on annual when changing plan | “standard process” ([condor](https://forum.cursor.com/t/pricing-questions/124768)) | **Medium-High** |
| Refund timing | Often “a few days”; depends on payment method/bank | **Medium-High** |
| 14-day “unused subscription” refund policy | Separate Help policy; same for monthly/annual; requires no usage in period ([refunds](https://cursor.com/help/account-and-billing/refunds)) | **High** — **do not confuse** with upgrade proration |

### Community / support-relayed reports (annual Pro → annual Pro+)

July 2026 forum thread ([Understanding the Pro to Pro+ upgrade process](https://forum.cursor.com/t/understanding-the-pro-to-pro-upgrade-process/164974)):

- Users report checkout charging **full** new annual Pro+ with **no visible** unused-Pro credit at confirmation (**Low** as user report).
- One user relays support saying unused annual Pro value should apply to the Pro+ invoice **or** land as **Cursor account balance**, and that a card refund may be unavailable outside the 14-day window (**Low** for the relay; consistent with staff “contact billing” advice).
- Another user claims support denied a refund after annual→annual upgrade (**Low**).

**Inference (Medium):** money-side proration for annual upgrades is intended, but UX and settlement path (invoice credit vs balance vs card refund) are **not crisply documented** in Help Center; verify on the resulting Stripe invoice / dashboard balance.

---

## 6. Mid-cycle upgrade vs renewal

| Event | Plan / access | Usage pools | Money |
| --- | --- | --- | --- |
| **Natural renewal** | Stay on same plan into next period | Fresh monthly included usage; unused prior month gone ([usage-limits](https://cursor.com/help/models-and-usage/usage-limits) — **High**) | Charge for next period (monthly or annual) |
| **Mid-cycle upgrade** | New plan immediately ([pricing](https://cursor.com/help/account-and-billing/pricing) — **High**) | Reset to **new** plan allowance; new cycle start ([Condor](https://forum.cursor.com/t/guys-how-can-i-get-cursor-pro-like-where/119180), [deanrie](https://forum.cursor.com/t/upgrading-from-monthly-to-yearly-credits-reset-timing-proration/158662) — **Medium-High**) | Pay new plan; prorate unused **time** on old sub |
| **Scheduled downgrade** | Keep current until period end ([pricing](https://cursor.com/help/account-and-billing/pricing) — **High**) | Continues under current plan until then | No mid-cycle charge for the lower plan |
| **Need more usage without upgrading** | Stay on plan | On-demand pay-as-you-go ([overages](https://cursor.com/help/account-and-billing/overages), staff suggestions — **High** / **Medium-High**) | Separate on-demand invoices |

There is **no** documented mid-cycle “refresh included usage with a prorated top-up while staying on the same plan”; staff pointed heavy users to on-demand or a higher plan ([deanrie on feature request](https://forum.cursor.com/t/feature-request-mid-cycle-credit-refresh-option/164984) — **Medium-High**).

---

## 7. Open gaps (not answered by primary sources)

1. Exact Stripe line-item formula for **annual Pro → annual Pro+/Ultra** (whether unused months always reduce the charge due today vs post as balance).
2. Whether any leftover **Other Models / Cursor Models** dollars are ever converted to account credit (no staff affirmation found; docs only say unused does not roll over).
3. Whether “new renewal date” after upgrade always equals the upgrade calendar day for both subscription renewal and monthly usage reset (staff imply yes for cycle start; Help shows usage reset date on Spending — verify per account).
4. Legacy request-based annual plans vs current token/API pools—older staff wording about “requests” may not map 1:1 ([historical](https://forum.cursor.com/t/extending-monthly-requests-in-an-annual-subscription/59556) — **Medium**).

---

## Sources (primary)

| Source | URL | Role |
| --- | --- | --- |
| Usage and limits (Help) | https://cursor.com/help/models-and-usage/usage-limits | Rollover, monthly reset, pools |
| Billing and payments (Help) | https://cursor.com/help/account-and-billing/billing | Monthly usage reset on individual plans; renew monthly/yearly |
| Pricing and plans (Help) | https://cursor.com/help/account-and-billing/pricing | Immediate upgrade; yearly switch rules |
| Refunds (Help) | https://cursor.com/help/account-and-billing/refunds | 14-day unused-sub refund (≠ upgrade proration) |
| Usage-based charges (Help) | https://cursor.com/help/account-and-billing/overages | On-demand alternative to upgrade |
| Models & Pricing (Docs) | https://cursor.com/docs/models-and-pricing | Pool amounts; monthly reset wording |
| Pricing page | https://cursor.com/pricing | Monthly/Yearly Individual UI |
| Clarifying pricing (Blog, Jun 2025) | https://cursor.com/blog/june-2025-pricing | Usage as monthly credit pool (historical framing) |
| Staff: Condor on upgrade reset | https://forum.cursor.com/t/guys-how-can-i-get-cursor-pro-like-where/119180 | New cycle + usage reset + prorated old sub |
| Staff: deanrie Pro→Pro+ | https://forum.cursor.com/t/ask-fee-to-upgrade-subscription-plan-from-pro-to-pro/159652 | Mid-cycle cancel / credit / new cycle |
| Staff: deanrie monthly→yearly | https://forum.cursor.com/t/upgrading-from-monthly-to-yearly-credits-reset-timing-proration/158662 | Immediate usage reset + Stripe time credit |
| Staff: Condor annual remainder refund | https://forum.cursor.com/t/pricing-questions/124768 | Prorated refund for remaining annual months |
| Staff: deanrie annual temporary upgrade | https://forum.cursor.com/t/question-about-pro-cost-with-active-pro-annual/147625 | No keep-annual temporary upgrade |
| Staff: Colin annual Pro+/Ultra | https://forum.cursor.com/t/is-yearly-billing-available-for-cursor-pro-plus-subscription/150023 | Annual higher tiers available (Feb 2026) |
| Staff: kevinn no rollover | https://forum.cursor.com/t/does-the-unused-api-limit-carry-over-to-the-next-month/158327 | Unused API limit does not roll over |
