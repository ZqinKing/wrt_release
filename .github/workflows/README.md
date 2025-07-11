# WRT 构建工作流说明

本项目将WRT固件构建过程分为三个步骤，以支持用户通过SSH进行交互式配置，并优化缓存策略以加速构建。

## 工作流结构

### 1. build-wrt-1.yml - 前期准备、SSH配置和配置备份
**功能：**
- 初始化构建环境
- 克隆代码仓库（pre_clone_action.sh）
- 复制配置文件
- **执行update.sh**（feeds更新、包安装、配置修复等）
- **SSH连接**（在make defconfig之前）
- 用户通过SSH进行 `make menuconfig` 配置
- 备份用户修改后的配置文件到config_backup
- 执行 `make defconfig`
- 处理x86_64特殊配置
- 备份make defconfig后的配置文件到config_backup
- 比较原始配置和用户配置，判断是否有变更
- 如果有变更，打包config.zip并上传
- 上传完整项目供Step 2使用

**生成的Artifacts：**
- `build-info-YYYY.MM.DD_HH.MM.SS-jdcloud_ipq60xx_immwrt`: 构建信息（保留1天）
  - `repo_flag`: 代码仓库标识（用于缓存键生成和缓存管理）
- `step1-full-YYYY.MM.DD_HH.MM.SS-jdcloud_ipq60xx_immwrt`: 完整项目（保留1天）
  - 整个 `action_build/` 目录（包含feeds和包）
  - `repo_flag`: 代码仓库标识（用于缓存键生成和缓存管理）
  - `config.zip`: 配置文件备份包（如果用户修改了配置）

**使用步骤：**
1. 在GitHub Actions中手动触发 `build-wrt-1.yml`
2. 选择设备型号（目前支持 `jdcloud_ipq60xx_immwrt`）
3. 选择运行环境（ubuntu-20.04 或 ubuntu-22.04）
4. 选择是否启用SSH连接（默认启用）
5. 等待环境准备完成和SSH连接建立
6. 通过SSH进入终端执行 `make menuconfig` 进行配置
7. 工作流会自动备份配置并执行后续步骤

### 2. build-wrt-2.yml - 依赖下载 ⚡
**功能：**
- 下载Step 1的完整项目（包含feeds和包）
- 如果存在config.zip，解压并恢复用户配置
- 执行 `make download` 下载依赖包（**关键优化点**）
- 缓存下载的依赖包以加速后续构建

**输入参数：**
- `step1_full_artifact`: Step 1完整项目artifact名称

**缓存优化：**
- `make download` 会检查 `dl` 目录，跳过已下载的文件
- 依赖包缓存可以显著加速重复构建
- 支持多线程下载：`-j$(($(nproc) * 2))`

**使用步骤：**
1. 在Step 1完成后，手动触发 `build-wrt-2.yml`
2. 输入Step 1完整项目artifact名称（格式：`step1-full-YYYY.MM.DD_HH.MM.SS-jdcloud_ipq60xx_immwrt`）
3. 选择相同的设备型号和运行环境
4. 等待依赖下载完成

### 3. build-wrt-3.yml - 最终构建
**功能：**
- 下载Step 2的构建产物（包含已下载的依赖包）
- 执行完整的固件构建：`make -j$(($(nproc) + 1)) || make -j1 V=s`
- 收集生成的固件文件
- 清理构建环境

**输入参数：**
- `step2_artifact`: Step 2构建产物artifact名称

**使用步骤：**
1. 在Step 2完成后，手动触发 `build-wrt-3.yml`
2. 输入Step 2生成的artifact名称（格式：`step2-YYYY.MM.DD_HH.MM.SS-jdcloud_ipq60xx_immwrt`）
3. 选择相同的设备型号和运行环境
4. 等待构建完成并下载固件

## 工作流逻辑说明

### 正确的执行顺序：
1. **Step 1**: 
   - 环境初始化 → 代码克隆 → 配置文件复制 → **update.sh执行** → SSH连接 → 用户配置 → 备份用户配置到config_backup → make defconfig → 备份defconfig结果到config_backup → x86_64特殊处理 → 打包config.zip → 比较配置变更 → 上传config.zip（如果有变更）
2. **Step 2**: 
   - 恢复完整项目 → 解压config.zip并恢复用户配置（如果存在）→ make download
3. **Step 3**: 
   - 恢复构建环境 → 清理旧固件 → 最终构建 → 收集固件

### 关键步骤说明：
- **update.sh**: 执行feeds更新、包安装、配置修复等关键步骤
- **SSH连接**: 使用 `mxschmitt/action-tmate@v3`，支持180分钟超时
- **配置变更检测**: 比较原始配置文件 `./deconfig/$model.config` 和用户修改后的配置文件
- **x86_64特殊处理**: 自动处理x86_64架构的特殊配置
- **智能配置检测**: 只有在配置变更时才生成配置文件artifact

## Artifact管理策略

### 分层Artifact设计
- **配置文件Artifact**: 仅在有变更时生成，保留7天，便于重用和版本控制
- **构建信息Artifact**: 包含代码仓库标识，保留1天
- **完整项目Artifact**: 包含整个构建环境（feeds和包）和配置文件备份，保留1天
- **构建产物Artifact**: 包含依赖包和中间文件，保留1天
- **固件Artifact**: 最终构建结果，长期保留

### 配置文件重用
- 配置文件打包成config.zip，包含在step1-full中
- 支持配置版本管理
- 便于调试和问题排查
- 只有在用户实际修改配置时才生成config.zip

## 缓存策略优化

### 分层缓存设计
所有三个工作流都使用了GitHub Actions的缓存功能：

- **ccache**: 编译缓存，加速重复编译
- **staging_dir**: 构建中间文件缓存
- **dl**: 下载的依赖包缓存（**关键优化**）

### 缓存键策略
缓存键基于：
- 运行环境（ubuntu版本）
- 代码仓库标识（repo_flag文件哈希，包含REPO_URL/REPO_BRANCH信息）
- 构建日期
- 步骤标识

**repo_flag文件作用：**
- 包含代码仓库URL和分支信息
- 用于生成唯一的缓存键，确保不同仓库的缓存不会冲突
- 支持缓存清理时精确删除特定仓库的缓存

### 性能优化效果
1. **Step 2优化**: `make download` 移到第二步，利用缓存跳过已下载文件
2. **重复构建加速**: 依赖包缓存可节省大量下载时间
3. **编译缓存**: ccache和staging_dir缓存加速重复编译
4. **配置重用**: 配置文件单独管理，支持跨构建重用
5. **智能配置检测**: 只有在配置变更时才生成配置文件artifact
6. **完整环境传递**: Step 1包含完整的feeds和包环境

## 设备支持

目前支持以下设备：
- `jdcloud_ipq60xx_immwrt` (包含01和02两个型号)

## 注意事项

1. **SSH配置**: 使用 `mxschmitt/action-tmate@v3`，无需额外配置
   - 支持180分钟超时
   - 限制访问权限给触发者
   - 可通过 `enable_ssh` 参数控制是否启用

2. **构建顺序**: 必须按照Step 1 → Step 2 → Step 3的顺序执行

3. **Artifact名称**: 每个步骤都会生成带有时间戳的artifact，需要手动输入到下一步

4. **配置文件管理**: 配置文件打包成config.zip，包含在step1-full中，仅在配置变更时生成

5. **缓存清理**: 构建完成后会自动清理旧的缓存文件

6. **错误处理**: 如果某一步骤失败，需要重新执行该步骤，后续步骤会自动使用最新的artifact

7. **依赖下载优化**: Step 2中的 `make download` 会自动跳过已下载的文件，大幅提升重复构建速度

8. **配置变更检测**: 系统会自动检测用户是否修改了配置，只有在有变更时才生成config.zip

9. **update.sh执行**: Step 1中会执行update.sh，确保feeds和包正确安装

10. **简化的输入参数**: Step 2只需要输入step1-full artifact名称，无需额外的配置文件参数

11. **repo_flag文件**: 用于缓存管理，确保不同代码仓库的缓存不会冲突，必须保留

12. **简化的artifact结构**: 移除了重复的config artifact，只保留在step1-full中

## 故障排除

### 常见问题

1. **SSH连接失败**
   - 检查 `enable_ssh` 参数是否正确设置
   - 确认GitHub Actions支持tmate
   - 检查网络连接

2. **Artifact下载失败**
   - 确认artifact名称正确
   - 检查artifact是否已过期（配置文件保留7天，其他保留1天）

3. **构建失败**
   - 检查配置文件是否正确
   - 查看构建日志获取详细错误信息
   - 确认update.sh执行成功

4. **依赖下载失败**
   - 检查网络连接
   - 查看Step 2的下载日志
   - 某些包可能需要手动处理

5. **配置文件问题**
   - 检查配置文件artifact是否正确下载
   - 确认配置文件格式正确
   - 可以重用之前的配置文件

6. **配置变更未检测到**
   - 检查用户是否实际进行了SSH配置
   - 查看Step 1的配置比较日志
   - 确认配置文件路径正确

7. **update.sh执行失败**
   - 检查INI文件配置是否正确
   - 查看feeds更新日志
   - 确认网络连接正常

### 日志查看

每个步骤的详细日志可以在GitHub Actions页面查看，包括：
- 构建环境信息
- 缓存状态
- 下载进度
- 配置比较结果
- update.sh执行日志
- 编译输出
- 错误信息

### 性能监控

每个步骤都会输出缓存状态信息：
```bash
========cache status========
ccache: 1.2G
staging: 5.8G
dl: 2.1G
```

这些信息可以帮助监控构建性能和缓存效果。

### 配置文件管理

配置文件artifact的管理特点：
- **智能生成**: 只有在配置变更时才生成
- **保留时间**: 7天（比其他artifact更长）
- **重用性**: 可以跨构建重用
- **版本控制**: 支持配置版本管理
- **调试友好**: 便于问题排查和配置对比 