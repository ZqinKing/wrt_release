# OpenWrt 构建环境更新工具

本项目提供了一个健壮、模块化、配置驱动的脚本，用于准备和更新 OpenWrt/ImmortalWrt 固件构建环境。

## ✨ 特性

- **配置驱动**: 所有设置（仓库、分支、软件包、补丁）都在 `scripts/config/default.json` 中定义
- **模块化设计**: 逻辑拆分为独立模块（feeds、packages、patches、tweaks），便于维护
- **健壮性**: 集成错误处理、日志记录和网络操作重试机制
- **并行处理**: 并行安装自定义软件包，加速准备过程
- **预览模式**: 支持 Dry-run 模式，预览变更而不实际修改文件

## 🚀 使用方法

### 前置依赖

确保系统已安装以下工具：
- `git`
- `curl`
- `jq`
- `sed`

```bash
# Debian/Ubuntu
sudo apt-get install git curl jq

# macOS
brew install git curl jq
```

### 基本用法

运行更新脚本：

```bash
./scripts/update.sh
```

### 命令行选项

| 选项 | 说明 |
|------|------|
| `-c, --config <文件>` | 使用自定义配置文件（默认: `scripts/config/default.json`） |
| `-d, --dry-run` | 预览模式，只打印命令不实际执行 |
| `-v, --verbose` | 启用详细日志输出 |
| `-h, --help` | 显示帮助信息 |

### 配置说明

您可以通过修改 `scripts/config/default.json` 或提供自定义 JSON 配置文件来定制构建环境。

#### 配置文件示例

```json
{
  "repo": {
    "url": "https://github.com/immortalwrt/immortalwrt.git",
    "branch": "master",
    "build_dir": "openwrt"
  },
  "network": {
    "lan_addr": "192.168.1.1"
  },
  "theme": {
    "set": "argon"
  },
  "feeds": {
    "add": [
      { "name": "small8", "url": "https://github.com/kenzok8/small-package" }
    ],
    "remove_lines": ["^#", "packages_ext"]
  },
  "packages": {
    "remove": ["luci-app-passwall", "luci-app-ssr-plus"],
    "custom_add": [
      {
        "name": "smartdns",
        "repo": "https://github.com/ZqinKing/openwrt-smartdns.git",
        "path": "feeds/packages/net/smartdns"
      }
    ]
  }
}
```

## 📁 目录结构

```
wrt_release/
├── scripts/
│   ├── update.sh           # 主入口脚本
│   ├── config/
│   │   └── default.json    # 默认配置文件
│   ├── lib/                # 核心库
│   │   ├── utils.sh        # 工具函数（日志、错误处理）
│   │   ├── config.sh       # 配置解析
│   │   └── git.sh          # Git 操作封装
│   └── modules/            # 业务逻辑模块
│       ├── feeds.sh        # Feeds 管理
│       ├── packages.sh     # 软件包管理
│       ├── patches.sh      # 补丁管理
│       └── config_tweaks.sh # 配置修改
├── patches/                # 本地补丁文件
├── compilecfg/             # 编译配置
├── deconfig/               # 设备配置
└── dts/                    # 设备树文件
```

## 🔧 环境变量

以下环境变量可以覆盖配置文件中的对应值：

| 环境变量 | 说明 |
|----------|------|
| `REPO_URL` | 主仓库 Git 地址 |
| `REPO_BRANCH` | 主仓库分支 |
| `BUILD_DIR` | 构建目录名称 |
| `LAN_ADDR` | 默认 LAN IP 地址 |
| `THEME_SET` | 默认主题 |

示例：
```bash
REPO_BRANCH=openwrt-24.10 ./scripts/update.sh
```

## 📖 详细文档

更详细的使用说明请参阅 [scripts/README.md](scripts/README.md)。

## 📄 许可证

GPL-3.0

## 👤 作者

ZqinKing

---

### 支持的设备

#### CMCC（中国移动）
- RAX3000M (NAND)
- RAX3000M (eMMC)

#### 其他设备
- 请参考 `compilecfg/` 目录下的配置文件
