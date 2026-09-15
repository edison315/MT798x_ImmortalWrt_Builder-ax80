# MT798x ImmortalWrt Builder

### 用 GitHub Actions 构建 [immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) 的固件流水线

[![Build](https://img.shields.io/github/actions/workflow/status/Glucy2/MT798x_ImmortalWrt_Builder/build.yml?branch=main&style=flat-square&logo=github&label=Build)](https://github.com/Glucy2/MT798x_ImmortalWrt_Builder/actions/workflows/build.yml)
[![Lint](https://img.shields.io/github/actions/workflow/status/Glucy2/MT798x_ImmortalWrt_Builder/lint.yml?branch=main&style=flat-square&logo=github&label=Lint)](https://github.com/Glucy2/MT798x_ImmortalWrt_Builder/actions/workflows/lint.yml)
[![Downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2FGlucy2%2FMT798x_ImmortalWrt_Builder%2Fstats%2Fdownloads.json&style=flat-square)](https://github.com/Glucy2/MT798x_ImmortalWrt_Builder/releases)

工作流程：定时/手动检查上游更新 → 建草稿 Release → 按设备分组并行构建 → 全部成功后发布 → 清理旧版本。

源码树基于 ImmortalWrt 25.12，已合并 MTK OpenWrt Feeds 补丁；本 builder 在其上启用
**MTK HNAT 硬件卸载（PPE）**，并带一套桌面路由器常用的默认配置（LuCI、SQM、BCP38、加固编译选项）。

---

## 使用固件

到 [Releases](../../releases) 下载最新 `mt798x-*` 版本，按设备与闪存布局选择镜像。

**同一台机器可能有多种布局变体，镜像互不通用**，选匹配你 bootlaoder 的那个：

| 后缀 | 布局 | 首次刷入 |
|---|---|---|
| `-stock` | 原厂布局 | 先刷 `*-initramfs-factory.ubi`，再 sysupgrade |
| `-ubootmod` | OpenWrt U-Boot 布局 | 从 U-Boot 网页刷 `*-initramfs-recovery.itb`，再 sysupgrade |
| `-mtkuboot` | MTK U-Boot 布局 | 从 MTK U-Boot 网页直接刷 `*-squashfs-factory.bin` |
| （无） | 该机唯一布局 | 见该机 Wiki |

日常升级直接 `sysupgrade -n <镜像>` 或 LuCI **系统 → 备份/升级**。

`*-preloader.bin` / `*-bl31-uboot.fip` / `*-emmc-gpt.bin` 是 BL2/FIP/GPT 引导 artifacts，
仅在你需要重建 bootloader 时使用，普通刷机用不到。

当前构建设备（要加机器见 [自定义](#自定义)）：

| 分组 | 设备 |
|---|---|
| `mt7981` | CMCC RAX3000M、Xiaomi WR30U（stock / ubootmod / mtkuboot）、H3C NX30 Pro（OpenWrt U-Boot / mtkuboot） |
| `mt7986` | Netcore N60 Pro（默认 / mtkuboot） |

> [!NOTE]
> Netcore N60 Pro 是 MT7986（Filogic 830），其余三台是 MT7981（Filogic 820）。
> 内核选项（HNAT、NETSYS）是整镜像级的，所以按 SoC 分组构建。

无线默认**关闭且无密码**：插网线进 LuCI → 网络 → 无线，设好 SSID/密码再启用。

## 默认包含

| 类别 | 内容 |
|---|---|
| 硬件卸载 | MTK HNAT（PPE），内核级开启；`hnat-detect` 在防火墙重载时自动维持卸载状态；`mtk-smp` 中断/RPS 亲和 |
| 工具链 | GCC 15 + LTO + Mold 链接器，`-mcpu=cortex-a53+crc+crypto` |
| 加固 | PIE/ASLR、强 stack protector、FORTIFY_SOURCE=3、full RELRO、seccomp |
| 网络 | SQM（cake，默认未启用，先填带宽再开）、BCP38 反欺骗、WAN 入站 DROP |
| 界面 | LuCI（HTTPS 跳转）+ 中文语言包 |
| 工具 | `htop`、`iperf3`、`curl` |

HNAT 状态检查：SSH 上机 `cat /sys/kernel/debug/hnat/hnat_entry | head`，或看
`logread | grep hnat`。想彻底关掉硬件卸载：`fw4` 里关掉 flow offloading 即可

## 自己构建

### GitHub Actions（推荐）

1. Fork 本仓库，编辑 `.github/workflows/build.yml` 顶部 `env:`（上游分支、保留数量等）。
2. 按需编辑 `devices/mt7981/config` / `devices/mt7986/config` 里的设备列表
   （profile id 在源码树 `target/linux/mediatek/image/filogic.mk` / `filogic-ext.mk` 里，
   一行 `CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_<profile>=y` 加一台）。
3. push 到 `main` 即触发构建；流水线也会每 2 小时检查一次上游，上游动了才重建。

可选：想要 README 的下载计数徽章，建一个孤儿分支 `stats`：

```sh
git checkout --orphan stats
git rm -rf .
echo '{"schemaVersion":1,"label":"Downloads","message":"0","color":"blue","pruned":0}' > downloads.json
git add downloads.json && git commit -m "init stats" && git push origin stats
git checkout main
```

不建也不影响构建——统计与 prune 的计数环节会自动跳过。

### 本地构建

```sh
git clone --depth 1 --branch 25.12 https://github.com/chasey-dev/immortalwrt-mt798x-rebase openwrt
cd openwrt

# 开启 HNAT（内核符号，.config 带不了它）
cfg=$(ls target/linux/mediatek/filogic/config-* | head -1)
sed -i 's/^# CONFIG_NET_MEDIATEK_HNAT is not set$/CONFIG_NET_MEDIATEK_HNAT=y/' "$cfg"

B=../MT798x_ImmortalWrt_Builder
OPENWRT_DIR=$PWD BUILDER_REPO=$B DEVICE=mt7981 bash $B/scripts/prepare-build.sh
make -j"$(nproc)"
```

> [!IMPORTANT]
> 上游分支会不定期 **rebase**（历史被重写）。更新已有检出不要用 `git pull`：
>
> ```sh
> git fetch origin && git reset --hard origin/25.12
> ```

## 自定义

- **加设备**：在 `devices/<soc>/config` 追加 `CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_<profile>=y`。
  mt7987/mt7988 设备新建 `devices/mt7988/config` 等目录并加进 build.yml 的 matrix
  （mt7988 还需要在内核配置里开 `CONFIG_MEDIATEK_NETSYS_V3`）。
- **加软件包**：追加到 `devices/common/config`（所有分组共享）。
- **预置文件/默认配置**：放进 `devices/common/files/`（所有机型）或 `devices/<group>/files/`
  （单分组），构建时会覆盖进 rootfs，后层覆盖先层。
- **切换上游分支**：改 build.yml 里的 `UPSTREAM_REF`（可选 `25.12` / `openwrt-25.12` / `25.12-dev-wifi7`）。
- **加自己的 feed**：build.yml 的 `FEEDS` 每行一条 `src-git <name> <url>`。

更多细节见 [docs/CUSTOMIZE.md](docs/CUSTOMIZE.md)，流水线工作原理见
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 目录结构

```
devices/common/        # 所有镜像共享：config + rootfs overlay
devices/mt7981/        # 按 SoC 分组的设备列表
devices/mt7986/
scripts/               # check-updates / prepare-build / prune-releases / download-stats（带测试与 lint）
docs/
.github/workflows/     # build.yml（构建发布）、lint.yml
```

## 致谢

- **[JuliusBairaktaris/Qualcommax_NSS_Builder](https://github.com/JuliusBairaktaris/Qualcommax_NSS_Builder)** — 本仓库的管线结构与脚本来源
- **[chasey-dev/immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase)** — 构建的上游源码
- **[hanwckf](https://github.com/hanwckf/immortalwrt-mt798x)**、**[padavanonly](https://github.com/padavanonly/immortalwrt-mt798x-6.6)** — MT798x HNAT 工作的源头

## License

[GPL-2.0](LICENSE)，与 OpenWrt/ImmortalWrt 一致。
