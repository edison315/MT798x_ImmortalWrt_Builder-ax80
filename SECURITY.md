# Security

## Supported versions

Only the **latest release** is supported. Older releases are routinely deleted by the prune job.

## Reporting a vulnerability

This template builds firmware images. There are two distinct vulnerability classes:

1. **Build pipeline** (this repo's workflow, scripts, default config) — open a private security advisory via GitHub: **Security -> Report a vulnerability**.
2. **ImmortalWrt itself, MTK drivers, packages** — please report to the source project: [chasey-dev/immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase), [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt), or the relevant package maintainer. This repo only assembles those sources.

Please do not open a public issue for a security report.

## Hardening posture

The default images enable:
- `PKG_ASLR_PIE_ALL`, `PKG_CC_STACKPROTECTOR_ALL`, `PKG_FORTIFY_SOURCE_3`, `PKG_RELRO_FULL`, `USE_SECCOMP`
- WAN input = DROP, BCP38 anti-spoofing (via the uci-defaults overlay)
- HTTPS-redirect on uHTTPd

If you fork and retarget to different devices, **review `devices/<group>/config`** — these are not enabled by default in stock ImmortalWrt.
