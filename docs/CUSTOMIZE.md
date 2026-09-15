# 自定义指南

一切从 fork 开始。下面按常见需求列出改动点；改完 push 到 `main` 即自动构建。

## 添加 / 删除设备

设备列表在 `devices/<soc>/config`，一行一台：

```
CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_<profile>=y
```

`<profile>` 是源码树里的设备定义名，在
`target/linux/mediatek/image/filogic.mk` 和 `filogic-ext.mk` 里找
（`define Device/<profile>`）。

- 删掉一行即不再构建该设备。
- 新增 SoC 分组：建 `devices/mt7988/config`（含 `CONFIG_TARGET_MULTI_PROFILE=y`、
  `CONFIG_TARGET_PER_DEVICE_ROOTFS=y` 和设备行），并把 `mt7988` 加进
  `.github/workflows/build.yml` 的 matrix。
  - mt7987/mt7988 还需要在 workflow 的 HNAT 步骤旁边把
    `CONFIG_MEDIATEK_NETSYS_V3` 也打开（它们的 XGMAC/USXGMII 需要 NETSYS V3；
    mt7981/mt7986 用的 V2 上游默认已开）。

> [!WARNING]
> 同一台机器若有 `-stock` / `-ubootmod` / `-mtkuboot` 多个变体，构建全部无妨
> （每个变体是独立 profile、独立镜像名），但**刷错布局会变砖**——发布页的
> 说明表按 bootloader 选择。

## 增删软件包

`devices/common/config` 是所有分组共享的 .config 主体。追加
`CONFIG_PACKAGE_<名字>=y` 即可；删掉对应行移除。

注意 prepare-build.sh 会**校验**：defconfig 后请求的符号不在了就直接构建失败
（通常是依赖没选上或包名打错）。这是故意的——宁可构建失败，不出悄悄缺件的固件。

## 预置文件（rootfs overlay）

- `devices/common/files/` — 打进所有镜像；
- `devices/<组>/files/` — 只打进该分组，同名文件覆盖 common 层。

典型用法：`etc/uci-defaults/` 放首次启动脚本（参考自带的 `999-QOL_config`，
用 uci marker 保证只应用一次，避免 sysupgrade 后重置用户改动）、
`etc/config/` 放预置配置。

## 自定义 feed

`.github/workflows/build.yml` 的 `FEEDS`，每行一条：

```
FEEDS: "src-git myfeed https://github.com/me/myfeed.git;main"
```

同名 feed 会替换默认 feed（可用于换 fork）。自定义 feed 默认**不**整体打进镜像，
只装 .config 里显式选中的包。

## 切换上游分支

build.yml `env:` 的 `UPSTREAM_REF`：

| 值 | 基底 |
|---|---|
| `25.12`（默认） | ImmortalWrt 25.12 + MTK feeds |
| `openwrt-25.12` | 官方 OpenWrt 25.12 + MTK 补丁 |
| `25.12-dev-wifi7` | Wi-Fi 7（mt7992/mt7996）开发分支 |

切到 `openwrt-25.12` 时建议同时检查 `devices/common/config` 里的包名是否仍存在于
对应 feeds（defconfig 校验会替你兜底报错）。

## 调整发布保留数量

build.yml `env:` 的 `KEEP`（默认 2）。prune 只删 `<RELEASE_PREFIX>-*` 前缀的
release，手动建的其它 release 不受影响。

## 本地迭代

不用等 CI——README「本地构建」一节就是 prepare-build.sh 的直接用法。想只验证
.config 能过 defconfig 校验：

```sh
OPENWRT_DIR=$PWD BUILDER_REPO=/path/to/builder DEVICE=mt7981 \
  bash /path/to/builder/scripts/prepare-build.sh
# 通过即会打印 "Build environment ready ..."，随后可以只跑 make defconfig 看结果
```
