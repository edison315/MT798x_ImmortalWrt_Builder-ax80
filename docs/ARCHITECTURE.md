# 流水线架构

管线分五个阶段，全部由 [`.github/workflows/build.yml`](../.github/workflows/build.yml) 驱动：

```
check ──┬──> stats
        └──> release (draft) ──> build × N groups ──> publish ──> prune
```

## check（上游检查）

`scripts/check-updates.sh` 用 `git ls-remote` 把 `UPSTREAM_REPO@UPSTREAM_REF`
解析成 commit SHA：

- `push` / 手动触发 → 总是构建（builder 配置变了 / 用户明确要求）；
- 定时触发 → 只有当最新已发布 release 的正文里没有记录这个 SHA 时才构建，
  上游没动就整条管线跳过。

## release（草稿）

按 `<RELEASE_PREFIX>-<UTC 时间戳>-<run id>` 建**草稿** release，正文记录上游 SHA
（check 阶段靠它去重）、设备布局说明和刷机指引。

## build（矩阵构建）

`devices/` 下每个分组一个并行 job（当前 `mt7981`、`mt7986`）。每个 job：

1. `actions/checkout` 拉上游源码（`needs.check.outputs.upstream_sha`，完整历史
   供 `SOURCE_DATE_EPOCH` 使用）和本仓库；
2. **开启 HNAT**：`NET_MEDIATEK_HNAT` 是内核符号，由源码树的 mtkhnat 补丁系列提供，
   默认关闭；它不在 OpenWrt 的 `config/Config-kernel.in` 白名单里，写进 `.config`
   会被 `defconfig` 丢弃，所以直接改 `target/linux/mediatek/filogic/config-6.12`；
3. `scripts/prepare-build.sh`：
   - 追加自定义 feeds（`FEEDS`，默认为空——MTK feeds 已在源码树内）并
     `feeds update/install`；
   - 把 `devices/common/config` + `devices/<组>/config` 拼成 `.config`，
     `make defconfig`；
   - **校验**：请求开启的符号若被 Kconfig 静默丢弃（依赖未满足），构建直接失败，
     不允许悄悄缩水的镜像出厂；
   - 分层覆盖 `files/`：common → 设备组（后者优先）；
4. `make download`（带重试）→ `make -j$(nproc)`；
5. 上传 sysupgrade/factory/recovery 镜像、bootloader artifacts（preloader/FIP/GPT）、
   `sha256sums-<组>.txt` 和 `config-<组>.buildinfo` 到草稿 release
   （`--clobber`，重跑中途失败的 job 是恢复而不是报错）。

构建是**无缓存**的（全新 runner），`SOURCE_DATE_EPOCH` 取上游 HEAD 时间戳，
`KBUILD_BUILD_USER/HOST` 固定，保证可复现性。

## publish（发布）

所有分组成功才把草稿转公开并设为 latest；任何一个分组失败就删掉草稿并以失败收场——
release 永远不会缺设备。

## prune（清理）

`scripts/prune-releases.sh` 按前缀保留最新 `KEEP` 个 release，删除更旧的
（连带 tag）。删除前先经 `scripts/download-stats.sh` 把下载数折叠进 `stats`
孤儿分支的累计徽章；fork 没建 `stats` 分支时自动跳过计数，不影响删除。

## lint

`.github/workflows/lint.yml`：actionlint（固定 commit + sha256 校验下载脚本）、
shellcheck、yamllint、`scripts/tests/prune-releases.test.sh` 单元测试，
对触及 workflows/scripts 的 push 和 PR 运行。
