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

## 已知问题

12.5 firmware 在开放无线网络下可能无法连接。使用 WPA2 或 WPA3 加密可规避该问题；11.4 firmware 没有发现此问题。

部分功能和补丁来自 [chenmozhijin/turboacc](https://github.com/chenmozhijin/turboacc)，感谢原作者。
