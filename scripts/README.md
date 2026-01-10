# OpenWrt 构建环境准备脚本

## 概述

本目录包含重构后的 OpenWrt/ImmortalWrt 固件构建环境准备脚本。脚本采用模块化设计，支持 JSON 配置文件和设备型号参数。

## 目录结构

```
scripts/
├── update.sh              # 主入口脚本
├── config/
│   └── default.json       # 默认 JSON 配置文件
├── lib/
│   ├── utils.sh           # 通用工具函数库
│   ├── config.sh          # 配置解析库（支持 JSON 和 INI）
│   └── git.sh             # Git 操作库
└── modules/
    ├── feeds.sh           # Feeds 管理模块
    ├── packages.sh        # 软件包管理模块
    ├── patches.sh         # 补丁管理模块
    └── config_tweaks.sh   # 配置修改模块
```

## 使用方法

### 基本用法

```bash
# 使用默认配置运行
./scripts/update.sh

# 使用设备型号配置（推荐）
./scripts/update.sh -D jdcloud_ipq60xx_immwrt

# 使用自定义 JSON 配置
./scripts/update.sh -c myconfig.json

# 预览模式（不实际执行）
./scripts/update.sh -D redmi_ax6_immwrt --dry-run

# 详细输出模式
./scripts/update.sh -v
```

### 命令行选项

| 选项 | 说明 |
|------|------|
| `-D, --device <型号>` | 指定设备型号（从 deconfig/ 和 compilecfg/ 加载配置） |
| `-c, --config <文件>` | 指定 JSON 配置文件路径（默认: config/default.json） |
| `-d, --dry-run` | 预览模式，只打印命令不实际执行 |
| `-v, --verbose` | 详细输出模式 |
| `-h, --help` | 显示帮助信息 |

## 设备型号配置

### 配置文件位置

- **设备配置文件**: `deconfig/<设备型号>.config`
- **编译配置文件**: `compilecfg/<设备型号>.ini`
- **NSS 配置**: `deconfig/nss.config`（IPQ 平台自动追加）
- **代理配置**: `deconfig/proxy.config`（始终追加）

### INI 配置文件格式

`compilecfg/<设备型号>.ini` 文件格式：

```ini
REPO_URL=https://github.com/immortalwrt/immortalwrt.git
REPO_BRANCH=openwrt-24.10
BUILD_DIR=openwrt
COMMIT_HASH=none
```

### 配置优先级

配置加载优先级（从高到低）：

1. **环境变量** - 最高优先级
2. **INI 配置文件** - 设备特定配置
3. **JSON 配置文件** - 默认配置

## 执行流程

脚本执行分为以下阶段：

1. **检查系统依赖** - 验证 jq, curl, git, sed 等工具
2. **加载 JSON 配置** - 读取默认配置文件
3. **加载设备配置** - 如果指定了 `-D` 参数，加载 INI 配置覆盖默认值
4. **准备主仓库** - 克隆或更新 OpenWrt 源码
5. **配置 Feeds** - 设置 feeds.conf 文件
6. **更新 Feeds** - 执行 feeds update
7. **管理软件包** - 安装/移除/更新软件包
8. **应用补丁和配置修改** - 应用各种 sed 修改
9. **应用设备配置** - 复制 .config 并追加 NSS/代理配置

## JSON 配置文件结构

`config/default.json` 主要配置项：

```json
{
  "repo": {
    "url": "仓库地址",
    "branch": "分支名",
    "build_dir": "构建目录",
    "commit_hash": "指定 commit（可选）"
  },
  "network": {
    "lan_addr": "默认 LAN IP"
  },
  "theme": {
    "set": "默认主题"
  },
  "feeds": {
    "conf_file": "feeds 配置文件名",
    "remove_lines": ["要删除的行"],
    "add": [{"name": "feed名", "url": "地址"}]
  },
  "packages": {
    "remove": ["要移除的包"],
    "golang": {"repo": "golang仓库", "branch": "分支"},
    "custom_add": [{"name": "包名", "repo": "仓库", "path": "目标路径"}]
  },
  "patches": {
    "ath11k_fw": "远程补丁URL",
    "tcping": "远程补丁URL"
  },
  "local_patches": [
    {"src": "源文件", "dest": "目标路径", "mode": "权限"}
  ]
}
```

## 模块说明

### lib/utils.sh

提供通用工具函数：
- `log_info`, `log_warn`, `log_error`, `log_debug` - 日志输出
- `try_run` - 命令执行（支持 dry-run 模式）
- `check_deps` - 依赖检查

### lib/config.sh

配置解析功能：
- `load_config` - 加载 JSON 配置
- `load_ini_config` - 加载 INI 配置
- `read_ini_by_key` - 读取 INI 键值
- `config_get_json`, `config_get_value` - 获取配置值

### lib/git.sh

Git 操作封装：
- `git_clone_or_update` - 克隆或更新仓库
- `git_checkout_hash` - 切换到指定 commit
- `git_sparse_checkout` - 稀疏检出

### modules/feeds.sh

Feeds 管理：
- `setup_feeds` - 配置 feeds.conf
- `update_and_install_feeds` - 更新并安装 feeds

### modules/packages.sh

软件包管理：
- `remove_packages` - 移除不需要的包
- `update_golang` - 更新 Golang 版本
- `install_custom_packages` - 安装自定义包
- `update_geoip`, `update_lucky` - 更新特定包

### modules/patches.sh

补丁管理：
- `apply_remote_patches` - 应用远程补丁
- `apply_local_patches` - 应用本地补丁

### modules/config_tweaks.sh

配置修改：
- `apply_device_config` - 应用设备配置（含 NSS/代理）
- `remove_uhttpd_dependency` - 移除 uhttpd 依赖
- `apply_system_tweaks` - 系统级修改
- `apply_kernel_tweaks` - 内核级修改
- `apply_app_tweaks` - 应用级修改

## 与原始 build.sh 的兼容性

重构后的脚本保持与原始 `build.sh` 的兼容性：

```bash
# 原始用法
./build.sh jdcloud_ipq60xx_immwrt

# 新用法（等效）
./scripts/update.sh -D jdcloud_ipq60xx_immwrt
```

## 故障排除

### 常见问题

1. **设备配置文件不存在**
   - 确保 `deconfig/<设备型号>.config` 和 `compilecfg/<设备型号>.ini` 都存在

2. **jq 命令未找到**
   - 安装 jq: `apt install jq` 或 `brew install jq`

3. **Git 克隆失败**
   - 检查网络连接和仓库 URL 是否正确

4. **NSS 配置未追加**
   - 仅 IPQ60xx/IPQ807x 平台且未设置 CONFIG_GIT_MIRROR 时才追加

### 调试模式

使用 `-v` 参数启用详细输出：

```bash
./scripts/update.sh -D jdcloud_ipq60xx_immwrt -v
```

## 版本历史

- **v2.1.0** - 添加设备型号参数支持，实现 NSS/代理配置自动加载
- **v2.0.0** - 模块化重构，支持 JSON 配置文件
- **v1.0.0** - 原始单文件脚本
