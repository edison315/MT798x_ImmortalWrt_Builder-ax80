# Repository Guidelines

Guidance for AI assistants working in this repository.

## Project Overview

A GitHub Actions pipeline that builds ImmortalWrt firmware images for MediaTek
Filogic (MT798x) routers from
[`chasey-dev/immortalwrt-mt798x-rebase`](https://github.com/chasey-dev/immortalwrt-mt798x-rebase)
(branch `25.12`), with MTK HNAT (PPE) hardware offload enabled. There is no
application code — the repo is workflows, bash scripts, OpenWrt `.config`
fragments, and a rootfs overlay. Modeled after `JuliusBairaktaris/Qualcommax_NSS_Builder`.

## Architecture & Data Flow

One pipeline, `.github/workflows/build.yml`, five stages:

```
check ──┬──> stats
        └──> release (draft) ──> build [matrix: mt7981, mt7986] ──> publish ──> prune
```

- **check** — `scripts/check-updates.sh` resolves `UPSTREAM_REPO@UPSTREAM_REF`
  to a SHA via `git ls-remote`. Push/dispatch always rebuild; scheduled runs
  rebuild only if the latest `<RELEASE_PREFIX>-*` release body lacks that SHA
  (the SHA embedded in release notes is a load-bearing data channel — do not
  remove it from the notes template). Outputs `upstream_sha`, `need`.
- **release** — creates draft tag `<RELEASE_PREFIX>-<UTC stamp>-<run id>`;
  `gh release create ... >&2` keeps gh's URL printout out of the stdout tag.
- **build** (matrix, `fail-fast: false`, one job per `devices/<group>/`):
  checkout upstream at the resolved SHA (full depth, for `SOURCE_DATE_EPOCH`)
  → **flip `NET_MEDIATEK_HNAT` in the filogic kernel config** (see Patterns)
  → `scripts/prepare-build.sh` → `make download` (3 retries) → `make -j` →
  upload images + `sha256sums-<group>.txt` + `config-<group>.buildinfo` with
  `gh release upload --clobber` (3 explicit retries).
- **publish** — `if: always()`; deletes the draft and fails the run if any
  group failed (a release never ships missing device groups; no
  `--cleanup-tag` — draft tags exist only inside the release).
- **prune** — `scripts/prune-releases.sh` keeps newest `KEEP` (default 2)
  releases per prefix; folds deleted download counts into the stats badge
  first (skipped gracefully if no `stats` orphan branch).

All tunables live in build.yml's top-level `env:` block
(`UPSTREAM_REPO`, `UPSTREAM_REF`, `TARGET`, `RELEASE_PREFIX`, `KEEP`, `FEEDS`).

## Key Directories

- `devices/common/` — `.config` bulk shared by every image (target, toolchain,
  hardening, packages) + `files/` rootfs overlay shipped in all images.
- `devices/<soc>/` (mt7981, mt7986) — per-SoC group: `config` holds
  `CONFIG_TARGET_MULTI_PROFILE=y`, `CONFIG_TARGET_PER_DEVICE_ROOTFS=y` and one
  `CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_<profile>=y` per board/variant.
  Groups split by SoC because kernel options (HNAT, NETSYS) are image-wide.
- `scripts/` — `check-updates.sh`, `prepare-build.sh`, `prune-releases.sh`,
  `download-stats.sh`, `lib/log.sh`, `tests/prune-releases.test.sh`.
- `docs/`, `README.md` — Chinese user docs; code comments stay English.
- `.github/` — workflows, lint config, dependabot, issue/PR templates.

## Development Commands

Local validation (run before committing; mirrors the Lint workflow):

```sh
shellcheck -x scripts/*.sh scripts/lib/*.sh scripts/tests/*.sh
yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, truthy: {check-keys: false}}}" .github/workflows/
bash scripts/tests/prune-releases.test.sh          # needs jq
```

actionlint is pinned (commit + sha256) — install exactly as
`.github/workflows/lint.yml` does (script into a scratch dir; the repo has no
`.gitignore`, so do not leave `actionlint`/`download-actionlint.bash` in the
root). Must run from repo root to pick up `.github/actionlint.yaml`.

Smoke-test config assembly against a real or stub tree:

```sh
OPENWRT_DIR=/path/to/openwrt BUILDER_REPO=$PWD DEVICE=mt7981 \
  bash scripts/prepare-build.sh
```

## Code Conventions & Common Patterns

**Bash** (all of `scripts/`): `set -euo pipefail` first; source
`scripts/lib/log.sh` via
`source "$(dirname -- "$0")/lib/log.sh"` and use `log::info/warn/error/die`
(`die` = stderr + exit 1). Required env vars are `: "${VAR:?...}"`-guarded;
optional ones defaulted with `${VAR:-}`. Two-space indent. Every external
network/tool call that may flake gets an explicit retry loop that fails
loudly (`::error::` + exit) after the last attempt.

**Config fragments** are concatenated least→most specific and resolved with
`make defconfig`: `devices/common/config` → `devices/<group>/config` →
optional `CONFIG_FRAGMENT`. `prepare-build.sh` then **hard-fails if defconfig
silently dropped any requested `=y` symbol** (Kconfig drops symbols with unmet
deps) — when adding a package, a verification failure means fix the
dependency, not the check. `=n` requests are exempt by design.

**Kernel symbols not in `config/Config-kernel.in` cannot go in `.config`** —
defconfig would drop them and the verification would fail. That is why
`NET_MEDIATEK_HNAT` is sed-flipped in `target/linux/mediatek/filogic/config-*`
by a dedicated workflow step before `prepare-build.sh` runs (glob + grep
guard so a kernel bump breaks loudly, not silently).

**Overlay layering**: `rsync -a` into `$OPENWRT_DIR/files/` in order
common → group (→ `files.<variant>` on top of each when `VARIANT` set); most
specific wins. uci-defaults scripts must be idempotent across sysupgrades —
see the run-once UCI marker (`system.@system[0].qol_defaults`) and the stable
`@bcp38[0]` anonymous-section reference (never a generated `cfgXXXXXX` hash)
in `devices/common/files/etc/uci-defaults/999-QOL_config`.

**Feeds**: `FEEDS` lines are appended idempotently; a custom feed sharing a
name with a default feed replaces it; custom feeds are then forced out of
image bundling (`CONFIG_FEED_<name>` off) so only explicitly selected
packages ship.

**Commits**: conventional (`feat:`/`fix:`/`ci:`/`docs:`/`test:`/`chore:`),
body explains the why. Formatting per `.editorconfig` (UTF-8, LF, 2-space
sh/yaml; Makefile tabs; never trim `*.md`/`*.patch` whitespace) and
`.gitattributes` (LF forced for sh/yaml/config/patch and uci-defaults files,
which have no `.sh` extension).

## Important Files

- `.github/workflows/build.yml` — the entire build/release pipeline.
- `.github/workflows/lint.yml` — actionlint (pinned) / shellcheck / yamllint /
  prune tests; triggers only on `.github/workflows/**` or `scripts/**`.
- `scripts/prepare-build.sh` — feeds, config assembly + defconfig
  verification, overlay layering. Env: `OPENWRT_DIR`, `BUILDER_REPO`,
  `DEVICE` (required); `VARIANT`, `FEEDS`, `CONFIG_FRAGMENT`, `COMMON`.
- `scripts/check-updates.sh` — upstream SHA resolution + rebuild decision.
- `scripts/prune-releases.sh` — retention; env knobs `REPO`, `KEEP`,
  `PREFIX`, `CURRENT_TAG`, `DRY_RUN`, `RELEASES_JSON_STDIN`.
- `scripts/download-stats.sh` — lifetime download badge on orphan `stats`
  branch (seed instructions in README); sha-conditional PUT with 5-retry
  conflict loop; `log::die` on corrupt `.pruned`.
- `devices/common/config` — toolchain/package/hardening policy for all images.
- `.github/actionlint.yaml` — teaches actionlint 1.7.7 the `ubuntu-26.04`
  runner label; deleting it breaks every workflow's lint job.

## Runtime/Tooling Preferences

- CI runners are `ubuntu-26.04`; everything must work there (GNU coreutils —
  e.g. `base64 -w0` is Linux-only, acceptable here).
- No package manager, no JS/Python runtime in the deliverable: pure bash +
  `gh` CLI + `jq` + `git` + `rsync`/`patch`.
- Builds are uncached and reproducibility-pinned (`SOURCE_DATE_EPOCH` from
  upstream HEAD, `TZ=UTC`, `LC_ALL=C`, fixed `KBUILD_BUILD_USER/HOST`).
- Supply-chain posture: the actionlint installer is pinned by commit +
  sha256 because it is piped to bash; keep that pattern for any new
  downloaded-and-executed tooling.

## Testing & QA

- Sole test harness: `scripts/tests/prune-releases.test.sh` — 9 cases driving
  `prune-releases.sh` purely through env knobs (`DRY_RUN=1
  RELEASES_JSON_STDIN=1` + synthetic `gh release list` JSON on stdin).
  **Gotcha**: the harness greps the exact `printf '  - %s\n'` plan-line
  format; changing that printf silently breaks every case. `want` lists are
  compared after `sort`.
- Untested by design: `download-stats.sh`, `check-updates.sh`,
  `prepare-build.sh` (shellcheck only), and all real `gh` interactions —
  validate these with a stub-tree smoke test (above) or CI.
- Expected baseline before commit: all four lint jobs' local equivalents
  green. Per CONTRIBUTING.md: fix red lint, never disable the check.

Known caveat: the `make download` retry loop in build.yml swallows total
failure (the loop exits 0 after the 3rd failed attempt; the build then fails
later in `make` with a messier log). Match the upload loop's explicit
`exit 1` pattern if you touch it.
