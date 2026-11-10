# 编译指南

本仓库用于按设备配置自动拉取 OpenWrt / ImmortalWrt / LiBwrt 源码、应用自定义补丁与软件包配置，并输出固件到 `firmware/` 目录。

## 1. 环境准备

推荐使用 Ubuntu LTS 或其他主流 Linux 发行版。OpenWrt 编译对磁盘空间、内存和文件系统大小写敏感性有要求，建议预留充足磁盘空间并在原生 Linux 文件系统中编译。

## 2. 安装编译依赖

```bash
sudo apt -y update
sudo apt -y full-upgrade
sudo apt install -y dos2unix libfuse-dev
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
```

容器构建还需要已安装并可正常运行的 Docker。

## 3. 获取源码

```bash
git clone https://github.com/ZqinKing/wrt_release.git
cd wrt_release
```

## 4. 编译用法

### 交互式选择

直接运行脚本会列出当前 `wrt_core/compilecfg/*.ini` 与 `wrt_core/deconfig/*.config` 同时存在的设备配置，并提示选择构建模式：

```bash
./build.sh
```

### 直接指定设备

```bash
./build.sh <设备配置名> [debug|container|container_debug|config_preview]
```

构建模式说明：

| 模式 | 命令示例 | 说明 |
| --- | --- | --- |
| 默认 | `./build.sh x64_immwrt` | 拉取源码、应用配置、下载依赖并完整编译固件。 |
| `debug` | `./build.sh x64_immwrt debug` | 执行到 `make defconfig` 后停止，用于检查配置，不产出固件。 |
| `container` | `./build.sh x64_immwrt container` | 使用 Docker 容器执行完整构建，减少本机环境差异。 |
| `container_debug` | `./build.sh x64_immwrt container_debug` | 在 Docker 容器中执行 debug 流程并进入交互 shell。 |
| `config_preview` | `./build.sh x64_immwrt config_preview` | 只预览配置片段组合，不拉取源码、不写构建目录。 |

可通过环境变量临时追加或移除配置片段：

```bash
ADD_CONFIG_FRAGMENTS=docker_deps ./build.sh gemtek_w1701k_immwrt config_preview
REMOVE_CONFIG_FRAGMENTS=proxy ./build.sh x64_immwrt config_preview
```

GitHub Actions 的手动构建也提供 `add_fragments` 与 `remove_fragments` 输入项，语义与上述环境变量一致。

编译完成后，脚本会从 `<BUILD_DIR>/bin/targets/` 收集固件文件到仓库根目录的 `firmware/`。每次完整构建前会清理旧的目标固件文件，`firmware/Packages.manifest` 会被移除。

## 5. 支持设备

设备配置名来自 `wrt_core/compilecfg/` 和 `wrt_core/deconfig/` 中同名文件。当前支持：

| 厂商 / 平台 | 设备 | 配置名 |
| --- | --- | --- |
| 京东云 | 雅典娜(02)、亚瑟(01)、太乙(07)、AX5(JDC版) | `jdcloud_ipq60xx_immwrt` |
| 京东云 | 雅典娜(02)、亚瑟(01)、太乙(07)、AX5(JDC版) - LiBwrt | `jdcloud_ipq60xx_libwrt` |
| 京东云 | 百里 / AX6000 | `jdcloud_ax6000_immwrt` |
| 阿里云 | AP8220 | `aliyun_ap8220_immwrt` |
| 阿里云 | AP8220 - LiBwrt | `aliyun_ap8220_libwrt` |
| Linksys | MX4200v1、MX4200v2、MX4300 | `linksys_mx4x00_libwrt` |
| Link | NN6000v2 | `link_nn6000v2_immwrt` |
| 奇虎 | 360v6 | `qihoo_360v6_immwrt` |
| 红米 | AX5 | `redmi_ax5_immwrt` |
| 红米 | AX6 | `redmi_ax6_immwrt` |
| 红米 | AX6 - LiBwrt | `redmi_ax6_libwrt` |
| CMCC（中国移动） | RAX3000M | `cmcc_rax3000m_immwrt` |
| Cudy | TR3000 | `cudy_tr3000_immwrt` |
| 斐讯 | N1 | `n1_immwrt` |
| 兆能 | M2 | `zn_m2_immwrt` |
| 兆能 | M2 - LiBwrt | `zn_m2_libwrt` |
| Gemtek | W1701K | `gemtek_w1701k_immwrt` |
| SuperGateway | S20M | `supergateway_s20m_immwrt` |
| Nokia | XG-040G-MD UBI | `nokia_040g_immwrt` |
| x86 | X64 | `x64_immwrt` |

示例：

```bash
./build.sh jdcloud_ipq60xx_immwrt
./build.sh aliyun_ap8220_libwrt
./build.sh redmi_ax6_libwrt container
```

## 6. 配置来源

每个设备由两类文件共同定义：

- `wrt_core/compilecfg/<设备配置名>.ini`：定义源码仓库、分支、构建目录、默认配置片段、可选提交哈希和容器 SDK 镜像。
- `wrt_core/deconfig/<设备配置名>.config`：定义 OpenWrt 目标平台、设备和软件包配置。

不同设备会使用不同上游源码，例如 `VIKINGYFY/immortalwrt`、`immortalwrt/immortalwrt`、`LiBwrt/openwrt-6.x`、`padavanonly/immortalwrt-mt798x` 或本仓库维护的特定分支。`BUILD_TARGET_SDK` 未配置时，容器构建默认使用 `immortalwrt/sdk:openwrt-25.12`。

构建时会按顺序组合配置：

1. 设备专用 `.config`
2. `compile_base.config`
3. `wrt_core/deconfig/fragments/<name>.config` 中的有效配置片段

默认片段由 `compilecfg/*.ini` 的 `CONFIG_FRAGMENTS` 指定：

- 所有设备默认包含 `proxy`。
- IPQ60xx / IPQ807x 设备默认额外包含 `nss`。
- 只有已显式选择 Dockerman 或明确适合运行 Docker 的设备默认包含 `docker_deps`，用于预置手动安装 Docker 所需的运行依赖，避免 NAND 空间紧张或无 USB 设备被默认加入 Docker 依赖。

`ADD_CONFIG_FRAGMENTS` 会在默认片段后追加，`REMOVE_CONFIG_FRAGMENTS` 会从最终片段中移除对应配置片段。移除只表示“不追加这个 fragment”，不会反向修改设备 `.config` 或 `compile_base.config` 中已经写明的配置。

## 7. 三方插件

三方插件主要通过 feeds 机制加入，其中 small-package 源自：

```text
https://github.com/kenzok8/small-package.git
```

相关增删和同步逻辑位于 `wrt_core/update.sh` 编排的 `wrt_core/modules/` 静态阶段。配置片段只选择 Kconfig，不负责 clone 仓库、修改 feeds 或安装 feeds。

## 8. 项目结构说明

- `build.sh`：主编译入口，负责设备选择、模式选择、配置组合、容器构建和固件收集。
- `firmware/`：完整构建后的固件输出目录，由脚本自动创建和刷新。
- `wrt_core/build_container.sh`：容器内构建入口。
- `wrt_core/update.sh`：源码更新、feeds 调整、软件包同步和补丁应用主流程。
- `wrt_core/pre_clone_action.sh`：GitHub Actions 预克隆辅助脚本。
- `wrt_core/compilecfg/`：设备构建元信息 `.ini`。
- `wrt_core/deconfig/`：设备和共享默认配置 `.config`。
- `wrt_core/deconfig/fragments/`：可组合配置片段。
- `wrt_core/modules/`：模块化脚本，包括仓库准备、网络重试、feeds/custom_feed、源码修正、LuCI 修正、服务修正、验证、Docker、CUPS 等静态职责模块。
- `wrt_core/patches/`：补丁、默认设置、Wi-Fi 初始化、NSS 诊断、PBR 规则和其他构建时注入文件。

## 9. OAF（应用过滤）功能使用说明

当前固件默认禁用 OAF（应用过滤）功能，目的是规避 OAF 驱动可能对网络栈产生的影响。需要使用 OAF 的用户，请确认能够接受启用后的潜在影响。

新版本更新后，首次启用 OAF 需要进入命令行模式（SSH 或串口）执行：

```sh
cd /etc/init.d/
./appfilter start
uci set fwx.record.enable=1
uci commit fwx
./appfilter start
```

命令执行完成后，OAF 即完成首次初始化并启动。
