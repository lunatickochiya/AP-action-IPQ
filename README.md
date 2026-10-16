# AP-action-IPQ

本仓库用于通过 GitHub Actions 构建 Qualcomm IPQ 系列 OpenWrt 固件，仅供自用，禁止商用。

IPQ 支持已从 [AP-action](https://github.com/lunatickochiya/AP-action) 独立到本仓库维护。

## 构建流程

- `Build-Machine-Single-2410-IPQ.yml`：OpenWrt 24.10 IPQ/NSS
- `Build-Machine-Single-2512-IPQ.yml`：OpenWrt 25.12 IPQ/NSS
- `Build-Machine-Single-IPQ50XX.yml`：IPQ50XX

在 Actions 页面选择对应工作流，点击 `Run workflow`，再选择设备和构建参数。

## 支持设备

OpenWrt 24.10 和 25.12：

- Aliyun AP8220（6M/12M）
- JDCloud RE-SS-01（6M/12M）
- Link NN6000 v2（标准版、Lite 版、6M/12M）

IPQ50XX：

- CMCC RAX3000Q
- CMCC RAX3000QY

## 配置说明

- 设备配置位于 `machine-configs/openwrt-2410-ipq` 与 `machine-configs/openwrt-ipq50xx`
- 软件包配置位于 `package-configs/openwrt-2410-ipq` 与 `package-configs/openwrt-ipq50xx`
- 补丁和平台文件位于 `openwrt-2512-ipq`、`openwrt-2410-ipq` 与 `openwrt-ipq50xx`
- 24.10/25.12 工作流使用私有源码仓库时，需要配置 `MY_SECRET_TOKEN`

`patch_repo` 支持通过 JSON 选择源码分支、NSS firmware、SFE、BBR v3、FullCone 等选项。

## 缓存（tools / toolchain / ccache）

三个构建工作流都用 fork 的 `lunatickochiya/cachewrtbuild@save-on-failure` 缓存
`staging_dir/host*`（tools）、`staging_dir/tool*`（toolchain）与 `.ccache`，
key 为 `<mixkey>-cache-openwrt-<工具链hash>`：

- **命中时**：直接复用工具链、跳过 tools/toolchain 编译；
- **保存**：在 job 结束时由 action 的 post 步骤完成。

相关选项都在 `config_repo`（json）里，默认值：
`{"Cache": "1", "CacheSave": "false", "CacheSaveOnFailure": "true", ...}`

| 键 | 默认 | 含义 |
|---|---|---|
| `Cache` | `"1"` | 是否启用缓存步骤（0 则整段跳过） |
| `CacheSave` | `"false"` | 传给 action 的 `skip_saving`：**默认 `"false"` = 保存**；设 `"true"` 则只读不写（命名沿用 autoset） |
| `CacheSaveOnFailure` | `"true"` | 由核心脚本导出成 env `CACHEWRT_SAVE_ON_FAILURE`，fork 的 `post-if` 读它：**`"true"` 时编译失败也执行 post 保存**（避免 tools/toolchain 编完后因后续包编译/打包失败而白编）；`"false"` 恢复上游“只在 job 成功时保存”的行为 |

> 注：`post-if` 里读不到 action 的 `with:` 输入，所以这个开关只能走 env。
> fork 的改动（`lunatickochiya/cachewrtbuild` 分支 `save-on-failure`）只有 action.yml 的 post-if 条件，
> 其余与上游一致，可随时合并回上游后把工作流改回原 action。

## 已知问题

12.5 firmware 在开放无线网络下可能无法连接。使用 WPA2 或 WPA3 加密可规避该问题；11.4 firmware 没有发现此问题。

部分功能和补丁来自 [chenmozhijin/turboacc](https://github.com/chenmozhijin/turboacc)，感谢原作者。
