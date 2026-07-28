# Shell scripts portable between Linux and macOS

**Researched:** 2026-07-28  
**Question:** What are the authoritative recommendations for shell scripts that must run on both Linux and macOS operator machines? Extract actionable essence (dos/don’ts, version floors, tool differences) for expanding `CODING_STANDARDS.md`.  
**Scope:** Primary owners only — GNU Autoconf Portable Shell / tool limitations, POSIX/Open Group utilities, Bash reference / version history, Apple macOS shell docs + stock Darwin man pages, GNU coreutils/sed man pages (via man7.org from upstream tarballs), ShellCheck first-party docs, Greg’s Wiki. Not Medium/Dev.to; Google’s Shell Style Guide is noted only as non-authoritative for portability.

**Repo constraint:** This tree already standardizes on Bash (`#!/usr/bin/env bash`, `set -euo pipefail`) and ShellCheck (`shell=bash` in `.shellcheckrc`). Host/workload scripts may run on Linux (Ubuntu Host); operator CLIs/tests also run on macOS developer machines.

---

## Verdict

| Recommendation | Implication for this repo’s CODING_STANDARDS |
| --- | --- |
| Treat **stock macOS `/bin/bash` as Bash 3.2** unless operators are required to install a newer Bash | Either (A) ban Bash 4+/5-only features in shared scripts, or (B) require Homebrew/etc. Bash and stop relying on `/usr/bin/env bash` finding 3.2 first |
| **`#!/usr/bin/env bash` ≠ “modern Bash”** on macOS | Document which Bash the shebang is allowed to resolve to; PATH order matters on developer machines |
| Prefer **Bash dialect + portable external utilities**, not “POSIX sh only” | Keep Bash shebang/`set -euo pipefail`; Autoconf’s ultra-strict Bourne subset is too tight for this repo’s dialect choice |
| **GNU vs BSD userland is the main Linux↔macOS landmine** | Standards must name forbidden flags (`sed -i`, `date -d`, `grep -P`, `find -printf`, …) with portable replacements |
| **ShellCheck with `shell=bash` does not enforce Linux↔macOS utility portability or a Bash 3.2 floor** | Keep ShellCheck for bashisms/quoting; add human rules (and optional CI probes) for GNU/BSD and Bash version |
| Prefer **`printf` over `echo`** for anything beyond literal text | Aligns with POSIX Application Usage; avoids BSD/SysV `echo` divergence |
| Prefer **`mktemp` with an explicit `XXXXXX` template** (and/or `mktemp -d`) | Portable enough on modern macOS + GNU; avoid bare assumptions about `-t`/`--tmpdir` shapes |
| Do **not** treat Google Shell Style Guide as a portability source | Style ≠ Linux↔macOS utility/version contract |

**Open policy choice (human must decide):** portable-to-stock-Bash-3.2 vs require newer Bash on macOS operators. Everything else below supports either policy; the Bash-floor section spells out the trade.

---

## Authoritative sources ranked

| Rank | Source | Owns |
| --- | --- | --- |
| 1 | [GNU Autoconf — Portable Shell Programming](https://www.gnu.org/software/autoconf/manual/html_node/Portable-Shell.html) + [Limitations of Shell Builtins](https://www.gnu.org/software/autoconf/manual/html_node/Limitations-of-Builtins.html) + [Limitations of Usual Tools](https://www.gnu.org/software/autoconf/manual/html_node/Limitations-of-Usual-Tools.html) (Autoconf 2.72 texinfo used for excerpts) | Classic portability contract for shell + common utilities across Unix lineages |
| 2 | [POSIX Shell Command Language](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html) and utility pages (e.g. [echo](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/echo.html), [find](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/find.html), [sed](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/sed.html)) | What is standard vs implementation-defined for utilities/options |
| 3 | [Bash reference manual](https://www.gnu.org/software/bash/manual/) + release feature map ([BashFAQ/061](https://mywiki.wooledge.org/BashFAQ/061), grounded in Bash `NEWS`/`CHANGES`) | Which language features require Bash 4/5 |
| 4 | Apple: [Use zsh as the default shell on Mac](https://support.apple.com/102360); Terminal guide ([default shell is zsh](https://support.apple.com/guide/terminal/change-the-default-shell-trml113/mac)); stock Darwin man pages (`man sed`, `date`, `stat`/`readlink`, …) | Login-shell reality vs script shebang; BSD-flavored flags |
| 5 | GNU tool manuals via upstream man pages hosted at man7.org (e.g. [sed(1)](https://man7.org/linux/man-pages/man1/sed.1.html), [date(1)](https://man7.org/linux/man-pages/man1/date.1.html), [stat(1)](https://man7.org/linux/man-pages/man1/stat.1.html), [mktemp(1)](https://man7.org/linux/man-pages/man1/mktemp.1.html), [readlink(1)](https://man7.org/linux/man-pages/man1/readlink.1.html), [grep(1)](https://man7.org/linux/man-pages/man1/grep.1.html)) | GNU-only options operators commonly assume on Linux |
| 6 | [ShellCheck](https://www.shellcheck.net/) / [README](https://github.com/koalaman/shellcheck/blob/master/README.md) / [wiki](https://www.shellcheck.net/wiki/) | Static checks for shell dialect vs shebang; **not** GNU/BSD CLI matrix |
| 7 | Greg’s Wiki: [BashPitfalls](https://mywiki.wooledge.org/BashPitfalls), [Bashism](https://mywiki.wooledge.org/Bashism), [BashFAQ/028](https://mywiki.wooledge.org/BashFAQ/028) | High-trust community primary reference for pitfalls and bashisms |

Autoconf’s Portable Shell chapter is aimed at `configure`-class `/bin/sh` across decades of Unix. For this repo (Bash on Linux + macOS only), use Autoconf primarily for **utility** pitfalls and historically sticky builtins (`echo`, `test -a/-o`, `set` quirks); do not rewrite the dialect back to 1977 Bourne.

---

## Bash version floor (Linux vs stock macOS)

### Facts

- Apple documents that **starting with macOS 10.15, zsh is the default login and interactive shell**; bash remains listed among shells in `/etc/shells`, and scripts may still invoke bash explicitly ([HT208050](https://support.apple.com/102360); [Terminal User Guide](https://support.apple.com/guide/terminal/change-the-default-shell-trml113/mac)).
- Stock macOS still ships **`/bin/bash`**. On a current Darwin host used for this research: `GNU bash, version 3.2.57(1)-release` (`/bin/bash --version`). Bash 3.2’s release date in the community version map is **2006-10-12** ([BashFAQ/061](https://mywiki.wooledge.org/BashFAQ/061)).
- Login shell ≠ script interpreter: a zsh login shell does not upgrade `#!/usr/bin/env bash` if `env` resolves to `/bin/bash` 3.2.
- Linux (Ubuntu Host and typical developer Linux) ships Bash 5.x via distro packages — features from Bash 4.0+ are available there.
- Features **absent on Bash 3.2** that operators often treat as “just Bash” (from [BashFAQ/061](https://mywiki.wooledge.org/BashFAQ/061); verified on stock `/bin/bash` 3.2.57):

  | Feature | Added in | Stock macOS 3.2 |
  | --- | --- | --- |
  | Associative arrays `declare -A` | 4.0 | Fails (`declare: -A: invalid option`) |
  | `mapfile` / `readarray` | 4.0 | Command not found |
  | `globstar` (`**`) | 4.0 | `shopt: globstar: invalid shell option name` |
  | `|&`, `&>>`, case `;&` / `;;&` | 4.0 | Unavailable |
  | `${var,,}` / `${var^^}` case mods | 4.0 | Unavailable |
  | `declare -n` namerefs | 4.3 | Unavailable |
  | `read -N`, `{var}>file` FD assign | 4.1 | Unavailable / limited |
  | `EPOCHSECONDS` / `EPOCHREALTIME` | 5.0 | Unavailable |

- Features already present by 3.0–3.2 (safe if the floor is 3.2): arrays, `[[ ]]`, `$(( ))`, `<( )` process substitution, `pipefail` (3.0), `=~` (3.0), `+=` (3.1), `printf -v` (3.1), `local`, `source`, here-strings `<<<`, etc. ([BashFAQ/061](https://mywiki.wooledge.org/BashFAQ/061)).

Apple’s public HT208050 does **not** spell out a GPLv3 rationale for freezing Bash; treat “Bash is stuck at 3.2 on stock macOS” as an **observed platform fact** (version string + Apple shipping `/bin/bash`), not as a claim Apple documents in that article.

### Policy options

| Option | Rule | Pros | Cons |
| --- | --- | --- | --- |
| **A. Portable-to-3.2** | Shared scripts must run under stock `/bin/bash` 3.2 | Zero macOS bootstrap; `env bash` works as shipped | Forbids associative arrays, `mapfile`, `globstar`, many 4.x conveniences |
| **B. Require newer Bash** | Operators install Bash ≥4.4/5.x (e.g. Homebrew); CI asserts `BASH_VERSINFO[0] -ge 4`; prefer shebang that finds it (document PATH) | Modern dialect matches Linux Host | Extra install step; easy to accidentally run 3.2 if PATH puts `/bin` first |

**Draft leaning for this repo (not applied):** Option A for anything an operator might run with a clean macOS PATH; Option B only if the team explicitly mandates a brew Bash and gates it in CI. Mixed policy (Host-only scripts may use 4+, operator CLIs stay 3.2-safe) is coherent if paths are labeled.

---

## Actionable don’t / do list

Each item is tied to a primary owner. “Portable” here means **Linux GNU userland + stock macOS Bash 3.2 + BSD utilities**, unless Option B is chosen for the Bash side.

### Shell language

| Don’t | Do | Source |
| --- | --- | --- |
| Assume Bash 4+ (`declare -A`, `mapfile`, `globstar`, `|&`, namerefs, …) under `env bash` on macOS | Stick to ≤3.2 features, **or** require/assert newer Bash (policy B) | [BashFAQ/061](https://mywiki.wooledge.org/BashFAQ/061); local `/bin/bash` 3.2.57 |
| Rely on interactive default shell being bash | Keep explicit `#!/usr/bin/env bash`; know login shell is zsh on modern macOS | [HT208050](https://support.apple.com/102360) |
| Use `echo -n` / `echo -e` / escapes for anything that must be portable | Use `printf '%s\n' ...` / `printf '%b\n' ...` | POSIX [echo APPLICATION USAGE](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/echo.html); Autoconf builtins (`echo`); [Bashism](https://mywiki.wooledge.org/Bashism) |
| Use `test`/`[` with `-a` / `-o` chaining | Use separate tests joined by `&&` / `||` | Autoconf Limitations of Builtins (`test`); POSIX marks these obsolete |
| Parse `$0` / `readlink -f "$0"` as a bulletproof “script directory” | Prefer fixed install paths, `PWD`/bundle conventions, or careful `BASH_SOURCE` with documented caveats | [BashFAQ/028](https://mywiki.wooledge.org/BashFAQ/028) |
| Write `#!/bin/sh` while using bashisms | Keep Bash shebang (already repo standard); ShellCheck SC30xx exists for the opposite mistake | [ShellCheck Portability gallery](https://github.com/koalaman/shellcheck/blob/master/README.md); [SC3011](https://www.shellcheck.net/wiki/SC3011) etc. |

### External utilities (highest-churn)

| Don’t | Do | Source |
| --- | --- | --- |
| `sed -i` (GNU optional suffix glued to `-i`) | macOS: `sed -i '' …` or write to temp + `mv`; or avoid in-place | macOS `sed(1)` (`-i extension` required); GNU [sed(1)](https://man7.org/linux/man-pages/man1/sed.1.html) (`-i[SUFFIX]`); empirical: GNU-style `sed -i 's/…/'` misparsed on Darwin |
| `date -d` / `date --date` | `date -v` adjustments on BSD; or pass epoch/`+%s` / generate timestamps in Bash/`python3` | macOS `date(1)` (`-v`, no `-d`); GNU [date(1)](https://man7.org/linux/man-pages/man1/date.1.html); empirical `date: illegal option -- d` |
| `grep -P` (PCRE) | `grep -E` / `grep -F`, or `sed`/`awk` | macOS `grep(1)` has no `-P`; empirical `grep: invalid option -- P`; GNU grep documents `-P` as Perl regexp |
| `find -printf` | `-print` / `-print0`, or `stat`/`ls` carefully | Autoconf Usual Tools (`find`: `-printf` nonportable); empirical macOS `find: -printf: unknown primary` |
| `stat -c '%…'` (GNU) | macOS: `stat -f '%…'`; or avoid `stat` formatting entirely | GNU [stat(1)](https://man7.org/linux/man-pages/man1/stat.1.html) (`-c`); macOS `stat(1)` (`-f`) |
| Assume `readlink -f` is identical everywhere | Prefer `realpath` where available, or document Darwin vs GNU; BashFAQ notes `readlink -f` is not historically universal | GNU [readlink(1)](https://man7.org/linux/man-pages/man1/readlink.1.html); macOS combines `readlink` with `stat(1)` (`-f` canonicalize); [BashFAQ/028](https://mywiki.wooledge.org/BashFAQ/028) |
| `cp -r` as the recursive flag of choice | Prefer `cp -R` (POSIX); Autoconf: avoid `-r` | Autoconf Usual Tools (`cp`) |
| Locale-sensitive `sort` / `[A-Z]` regex ranges without `LC_ALL=C` | Export `LC_ALL=C` for machine parsing | Autoconf Usual Tools (`sort`, `sed`) |

---

## GNU / BSD utility landmines

Verified against GNU man pages (man7.org from coreutils/sed upstream) and stock macOS man pages / commands (2026-07-28).

| Operator intent | GNU (Linux) | BSD / macOS | Portable alternative |
| --- | --- | --- | --- |
| In-place `sed` | `sed -i` or `sed -iSUFFIX` ([sed(1)](https://man7.org/linux/man-pages/man1/sed.1.html)) | `sed -i extension` — extension **required** (empty `''` allowed) (Darwin `sed(1)`) | Temp file + `mv`, or branch on `sed --version` **only if** you accept detection complexity |
| Parse / convert dates | `date -d STRING`, `date --date=` ([date(1)](https://man7.org/linux/man-pages/man1/date.1.html)) | No `-d`; use `-v[+|-]val…`, `-f`+`-j`, `+%fmt` (Darwin `date(1)`) | Prefer `date +%s` / `+%Y-%m-%d` for output; do arithmetic in Bash or a small Python helper |
| File metadata format | `stat -c '%n %s'` ([stat(1)](https://man7.org/linux/man-pages/man1/stat.1.html)) | `stat -f '%N %z'` (Darwin `stat(1)`) | Avoid formatted `stat`; use `wc -c <file`, `test`, or Python |
| Canonical path | `readlink -f` / `realpath` ([readlink(1)](https://man7.org/linux/man-pages/man1/readlink.1.html)) | `realpath` exists (`realpath(1)`); `readlink -f` is Darwin-specific canonicalize via `stat` | `realpath -- "$path"` when both platforms provide it; still handle missing targets carefully |
| Temp files | `mktemp`, `mktemp -d`, `--tmpdir` ([mktemp(1)](https://man7.org/linux/man-pages/man1/mktemp.1.html)) | `mktemp`, `mktemp -d`, `-t prefix` (Darwin `mktemp(1)`); Autoconf still warns not all systems have it historically | `dir=$(mktemp -d "${TMPDIR:-/tmp}/foo.XXXXXX")` with `umask 077` (Autoconf sample pattern) |
| PCRE grep | `grep -P` (GNU grep) | Not supported (Darwin `grep(1)`; empirical failure) | `grep -E` or `awk` |
| NUL-safe find pipelines | `find … -print0` \| `xargs -0` (GNU + modern BSD) | Both support `-print0` / `-0` on current macOS | Prefer `-print0`/`-0` over line splitting ([BashPitfalls](https://mywiki.wooledge.org/BashPitfalls)-adjacent; Autoconf notes portable `find` operands) |
| `find` pretty-print | `-printf '%p\0'` | Missing (`-printf` unknown) | `-print0` or `-exec printf '%s\0' {} +` where needed |
| `find` depth limits | `-maxdepth` (GNU; Autoconf still flags as non-POSIX) | Present on modern Darwin `find(1)` | Prefer portable structure; if used, know Autoconf still classifies it nonportable vs strict POSIX |
| `head`/`tail` counts | `head -n N`, also historic `head -N` | Darwin documents `head [-n count \| -c bytes]` | Prefer `head -n N` / `tail -n N` (both accept here) |
| `sort` stability / locale | GNU extensions + locale | BSD `sort` + locale | `LC_ALL=C sort` for byte order |
| `cp` archive / recursive | `cp -a` (GNU almost-archive), `cp -R` | Darwin `cp -a` ≡ `-RpP`; recursive is `-R` (Darwin `cp(1)`); Autoconf: prefer `-R` over `-r` | `cp -R` for recursion; use `cp -a` only if both sides agree |
| `ln` relative symlink | GNU `ln -r` | No `-r` in Darwin `ln(1)` synopsis | Compute relative path in Bash or use absolute targets |

Autoconf’s Usual Tools list is broader (ancient Solaris/AIX quirks). For **Linux↔macOS today**, the table above is the practical subset; keep Autoconf as the deeper backstop when touching `sed` regex portability, `tr`, `expr`, etc.

---

## What ShellCheck enforces vs gaps

### Enforces (relevant here)

- Dialect consistency with the declared shell: with `shell=bash` / `#!/usr/bin/env bash`, bashisms are **allowed**; with `sh`, SC30xx warns ([README Portability](https://github.com/koalaman/shellcheck/blob/master/README.md); e.g. [SC3011](https://www.shellcheck.net/wiki/SC3011), [SC3040](https://www.shellcheck.net/wiki/SC3040)).
- Quoting, word-splitting, common pitfalls, some robustness issues (core ShellCheck goals in the README).
- This repo’s `.shellcheckrc` sets `shell=bash` and baseline disables unrelated to OS portability.

### Does **not** cover (Linux↔macOS)

- **GNU vs BSD utility flags** — ShellCheck does not treat `sed -i`, `date -d`, `grep -P`, `stat -c`, `find -printf` as cross-OS errors when `shell=bash`.
- **Bash version floors** — with `shell=bash`, associative arrays / `mapfile` / `globstar` are accepted even though stock macOS Bash 3.2 rejects them.
- **Runtime PATH / which binary `env bash` finds** — static analysis cannot see Homebrew vs `/bin/bash`.
- **Full behavioral compatibility** of ostensibly shared flags (subtle `sed`/`find`/`xargs` differences).

**Clear statement for CODING_STANDARDS:** ShellCheck is authoritative for SC\* correctness under the declared Bash dialect; it is **not** a Linux↔macOS portability gate. Portability rules for Bash 3.2 and GNU/BSD utilities must be written (and optionally tested) separately.

---

## Suggested CODING_STANDARDS.md bullets

*Draft suggestions only — not already applied. Distill/edit before pasting.*

1. **Targets:** Shared Bash scripts must run on Ubuntu Host **and** macOS operator machines unless a path is explicitly Host-only or operator-only.
2. **Bash floor (pick one and delete the other):**
   - *3.2 floor:* No Bash 4+ features (`declare -A`, `mapfile`/`readarray`, `globstar`, `|&`, namerefs, `${var,,}` / `${var^^}`, …). Assume stock `/bin/bash` 3.2 may be what `#!/usr/bin/env bash` finds on macOS.
   - *Modern Bash:* Require Bash ≥4.4 (document install); CI must fail if `BASH_VERSINFO[0] < 4`. Do not rely on `/bin/bash` on macOS.
3. **Shebang stays** `#!/usr/bin/env bash` with `set -euo pipefail` (unchanged); do not switch the tree to POSIX `sh` for portability theater.
4. **Prefer `printf` over `echo`** whenever flags or escapes matter.
5. **Forbid GNU-only date parsing:** no `date -d` / `date --date`; use `date +FMT`, BSD `date -v` only in macOS-only paths, or non-shell helpers.
6. **Forbid `sed -i` without an OS-safe pattern;** prefer temp + `mv`, or document `sed -i ''` vs GNU `-i` branching if in-place is unavoidable.
7. **Forbid `grep -P`.** Use `grep -E`/`-F`, `sed`, or `awk`.
8. **Forbid `find -printf` and GNU `stat -c`.** Use `-print0`, portable `find` primaries, Darwin `stat -f` only in macOS-only paths, or avoid formatted `stat`.
9. **Temp files:** `mktemp` / `mktemp -d` with an explicit `XXXXXX` template under `"${TMPDIR:-/tmp}"`; `umask 077` when creating dirs.
10. **Recursive copy:** `cp -R` (not historic `cp -r` as the documented choice).
11. **Machine-oriented text:** set `LC_ALL=C` for `sort`, `sed` ranges, and similar.
12. **NUL-safe file lists:** `find … -print0` with `read -d ''` or `xargs -0` when names may contain spaces/newlines.
13. **ShellCheck** remains the SC\* gate (`./lint-shell.sh`); reviewers must still check Bash-floor and GNU/BSD rules — ShellCheck will not.
14. **Script location:** do not build critical logic on `$0` / `readlink -f "$0"`; follow BashFAQ/028 guidance.
15. **Google Shell Style Guide** may inform style taste; it is **not** the portability standard for this repo.

---

## Sources

- GNU Autoconf 2.72 manual: [Portable Shell](https://www.gnu.org/software/autoconf/manual/html_node/Portable-Shell.html), [Limitations of Builtins](https://www.gnu.org/software/autoconf/manual/html_node/Limitations-of-Builtins.html), [Limitations of Usual Tools](https://www.gnu.org/software/autoconf/manual/html_node/Limitations-of-Usual-Tools.html) (excerpts from `autoconf-2.72` texinfo tarball on ftp.gnu.org)
- POSIX: [Shell Command Language](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html), [echo](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/echo.html), [find](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/find.html), [sed](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/sed.html)
- Bash: [Bash reference manual](https://www.gnu.org/software/bash/manual/), [BashFAQ/061](https://mywiki.wooledge.org/BashFAQ/061)
- Apple: [HT208050 — zsh default shell](https://support.apple.com/102360), [Change the default shell in Terminal](https://support.apple.com/guide/terminal/change-the-default-shell-trml113/mac)
- GNU man pages (man7.org): [sed](https://man7.org/linux/man-pages/man1/sed.1.html), [date](https://man7.org/linux/man-pages/man1/date.1.html), [stat](https://man7.org/linux/man-pages/man1/stat.1.html), [mktemp](https://man7.org/linux/man-pages/man1/mktemp.1.html), [readlink](https://man7.org/linux/man-pages/man1/readlink.1.html), [grep](https://man7.org/linux/man-pages/man1/grep.1.html)
- Darwin man pages consulted locally: `sed(1)`, `date(1)`, `stat(1)`/`readlink`, `mktemp(1)`, `realpath(1)`, `grep(1)`, `find(1)`, `xargs(1)`, `head(1)`, `cp(1)`, `ln(1)`
- ShellCheck: [site](https://www.shellcheck.net/), [README](https://github.com/koalaman/shellcheck/blob/master/README.md), [wiki index](https://www.shellcheck.net/wiki/), [SC3011](https://www.shellcheck.net/wiki/SC3011), [SC3040](https://www.shellcheck.net/wiki/SC3040)
- Greg’s Wiki: [BashPitfalls](https://mywiki.wooledge.org/BashPitfalls), [Bashism](https://mywiki.wooledge.org/Bashism), [BashFAQ/028](https://mywiki.wooledge.org/BashFAQ/028)
