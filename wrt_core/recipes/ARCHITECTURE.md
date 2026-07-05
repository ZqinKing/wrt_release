# Recipe 架构设计

## 目标

将构建定制从 `wrt_core/update.sh` 的固定函数序列中解耦出来，改为：

- 每个 recipe 在 `wrt_core/recipes/<recipe-name>/` 下独立存放
- 每个目标 ini 只负责声明启用/禁用哪些 recipe
- recipe 用 `recipe.json` 自描述 feed、包、补丁、文件、config fragment、脚本钩子
- `wrt_core/recipe.sh` 提供统一 planner/runner，并挂接到现有 `build.sh` / `wrt_core/update.sh` 流程

目标 `wrt_core/compilecfg/*.ini` 继续作为构建入口配置；本架构只统一 recipe 元数据与 import registry。

---

## 目录结构

采用扁平结构：`recipes` 下一级目录就是一个 recipe；不再分层级。

```text
wrt_core/
  recipe.sh                              # planner/runner；Bash + jq
  recipes/
    import_registry.json                 # IMPORT_PACKAGES 来源 registry
    recipe.schema.json
    import-registry.schema.json
    <recipe-name>/
      recipe.json
      apply.sh                           # 可选；复杂动作钩子
      files/                             # 可选；覆盖到 BUILD_DIR 的文件
      patches/                           # 可选；补丁文件
      configs/                           # 可选；config fragment
```

约束：

- recipe 名即目录名，必须全局唯一
- 不引入 `recipes/core/`、`recipes/ui/` 之类二级层级
- 所有 recipe 都必须包含 `recipe.json`
- 不保留 `recipe.ini` 兼容路径
- JSON 读取统一使用 `jq`；不引入 Python / Node / YAML 解析层

---

## 目标 ini 扩展设计

每个 `wrt_core/compilecfg/*.ini` 保留现有字段，并新增 recipe 相关字段。

```ini
REPO_URL=
REPO_BRANCH=
BUILD_DIR=
COMMIT_HASH=

BASE_CONFIG=
CONFIG_FRAGMENTS=

RECIPES=
DISABLE_RECIPES=
TARGET_TAGS=

KERNEL_VERMAGIC=
KERNEL_MODULES=
```

含义：

- `BASE_CONFIG`：主 `.config` 文件路径，默认仍回退到 `deconfig/<target>.config`
- `CONFIG_FRAGMENTS`：目标级通用 config 片段，逗号分隔
- `RECIPES`：追加启用的 recipe 名列表，逗号分隔；即使某 recipe 的 `enabled` 为 `false`，只要出现在这里也会进入候选集
- `DISABLE_RECIPES`：从默认集或 `RECIPES` 注入集中显式移除的 recipe
- `TARGET_TAGS`：当前目标标签，供 recipe 条件过滤使用，例如 `x86_64,immortalwrt,master`
- `KERNEL_VERMAGIC` / `KERNEL_MODULES`：target 参数；供 `fix_kernel_magic` 等 recipe 使用
- 默认启用集来自各 recipe 的 `enabled: true`，然后由目标 ini 的 `RECIPES` / `DISABLE_RECIPES` 做增量调整

示例：

```ini
REPO_URL=https://github.com/immortalwrt/immortalwrt.git
REPO_BRANCH=master
BUILD_DIR=immortalwrt

BASE_CONFIG=deconfig/x64_immwrt.config
CONFIG_FRAGMENTS=deconfig/compile_base.config,deconfig/proxy.config
RECIPES=fix_kernel_magic,awg,tailscale_awg,ohmyzsh
DISABLE_RECIPES=
TARGET_TAGS=x86_64,immortalwrt,master
KERNEL_VERMAGIC=
KERNEL_MODULES=
```

启用判定顺序：

1. 扫描所有 `recipe.json`，把 `enabled: true` 的 recipe 放入默认候选集
2. 读取目标 ini 的 `RECIPES`，把其中列出的 recipe 追加到候选集
3. 读取目标 ini 的 `DISABLE_RECIPES`，把命中的 recipe 从候选集移除
4. 对候选集补齐 `depends`
5. 对候选集执行 `when.targets` / `when.repo` / `when.branch` / `when.tags` 条件过滤；不匹配时跳过而不是报错
6. 过滤后的最终集合再进入冲突检查与 phase 排序

因此：

- `enabled: true` 只表示“默认加入候选集”，不表示一定会执行
- `RECIPES=` 可以显式启用一个默认关闭的 recipe
- `DISABLE_RECIPES=` 可以显式关闭一个默认开启或被显式追加的 recipe
- 即使 recipe 已进入候选集，只要 `when.*` 不匹配，最终仍不会执行

---

## recipe.json 规范

每个 recipe 用一个 `recipe.json` 描述。格式由 `wrt_core/recipes/recipe.schema.json` 约束；runner 同时用 `jq` 校验自身消费字段。

```json
{
  "$schema": "../recipe.schema.json",
  "name": "example_argon_base",
  "description": "示例配方：演示 feed、文件覆盖、补丁、配置片段、脚本钩子的统一声明",
  "enabled": false,
  "phase": "post_feeds_update",
  "depends": [],
  "conflicts": [],
  "tags": ["ui", "example"],
  "when": {
    "targets": [],
    "repo": [],
    "branch": [],
    "tags": []
  },
  "actions": {
    "addFeeds": ["src-git luci_app_bandix https://github.com/timsaya/luci-app-bandix.git;main"],
    "removeFeeds": ["packages_ext", "small8"],
    "importPackagesRegistry": {
      "example-private-source": {
        "gitUrl": "https://github.com/example/openwrt-extra.git",
        "branch": "main",
        "sparseRoot": null
      }
    },
    "importPackages": [
      { "source": "example-private-source", "name": "luci-app-netdata" }
    ],
    "removePackageDirs": ["feeds/luci/applications/luci-app-dockerman"],
    "patches": [
      { "source": "patches/999-example.patch", "target": "feeds/packages/net/miniupnpd/patches/999-example.patch" }
    ],
    "files": [
      { "source": "files/etc/uci-defaults/990_set_argon_primary", "target": "package/base-files/files/etc/uci-defaults/990_set_argon_primary" }
    ],
    "configs": ["configs/example.config"],
    "script": "apply.sh"
  }
}
```

### 元数据字段

- `name`：recipe 名；必须与目录名一致
- `description`：面向维护者的简短说明
- `enabled`：是否作为默认 recipe
- `phase`：执行阶段；必须属于固定枚举
- `depends`：依赖的 recipe 名；runner 自动补齐依赖
- `conflicts`：冲突的 recipe 名；最终启用集中仍冲突则报错
- `tags`：recipe 自身标签，用于分类/检索
- `when.targets`：允许的 target 名；空数组表示不限
- `when.repo`：允许的仓库 URL；空数组表示不限
- `when.branch`：允许的分支；空数组表示不限
- `when.tags`：允许的目标标签；与目标 ini 的 `TARGET_TAGS` 匹配；空数组表示不限

### 动作字段

- `actions.addFeeds`：追加到 `feeds.conf(.default)` 的 feed 条目
- `actions.removeFeeds`：移除的 feed 标识
- `actions.importPackagesRegistry`：当前 recipe 独立追加的 IMPORT_PACKAGES 来源映射；键名与全局 registry 共用同一命名规则
- `actions.importPackages`：从合并后的 registry 导入外部包；每项包含 `source`、`name`，可选 `target`
- `actions.removePackageDirs`：删除构建树中的包目录
- `actions.patches`：复制补丁文件；每项包含 `source`、`target`，可选 `mode`
- `actions.files`：复制普通文件；每项包含 `source`、`target`，可选 `mode`
- `actions.configs`：追加到 `.config` 的 config fragment
- `actions.script`：兜底脚本；无脚本时为 `null`

路径约定：

- `source` 相对 recipe 目录
- `target` 相对 `BUILD_DIR`
- `mode` 缺省为 `0644`
- `script` 相对 recipe 目录

---

## 执行阶段设计

固定枚举：

- `pre_clone`：clone 前
- `post_clone`：clone / clean / reset feeds 后
- `pre_feeds`：feeds update 前
- `post_feeds_update`：feeds update 后
- `post_feeds_install`：feeds install 后
- `pre_defconfig`：主 `.config` 已复制后、`make defconfig` 前
- `post_defconfig`：`make defconfig` 后
- `finalize`：构建前最后修整

---

## runner 约定

实现位置：`wrt_core/recipe.sh`。

输入：

- `TARGET_NAME`
- `TARGET_INI`
- `BUILD_DIR`
- `REPO_URL`
- `REPO_BRANCH`
- `TARGET_TAGS`
- `wrt_core/recipes/*/recipe.json`

规划步骤：

1. 读取目标 ini
2. 扫描所有 `recipe.json`，收集 `enabled: true` 的默认 recipe
3. 合并目标 ini 的 `RECIPES`
4. 去掉 `DISABLE_RECIPES`
5. 用 `jq` 校验候选 recipe 的必需字段与类型
6. 检查 `name == 目录名`
7. 检查 `phase` 是否属于固定枚举
8. 解析并补齐 `depends`
9. 过滤 `when.targets` / `when.repo` / `when.branch` / `when.tags` 不匹配项；当前实现是不匹配即跳过，并打印 `recipe: skipping <name> because when conditions do not match target`
10. 为了保证依赖补齐后的 recipe 也经过同样过滤，当前实现会再次执行一轮 `depends` 解析 + 条件过滤
11. 检查 `conflicts`（允许通过 `DISABLE_RECIPES` 在最终集消解）
12. 检查 `files` / `patches` 目标路径冲突与 `configs` 重复项
13. 按 `phase` 排序并生成执行计划

执行规则：

1. 应用 `actions.addFeeds` / `actions.removeFeeds`
2. 应用 `actions.importPackages` / `actions.removePackageDirs`
3. 复制 `actions.patches`
4. 复制 `actions.files`
5. 合并 `actions.configs`
6. 最后执行 `actions.script`

约束：

- `jq` 是 recipe JSON 的唯一运行时解析器
- `SCRIPT` 仅作为兜底，不应承载声明式字段已能表达的动作
- `SCRIPT` 必须幂等

---

## build.sh / update.sh 接入点

`build.sh`：

- 支持 `plan` 模式，只输出 recipe 计划，不进入构建
- `apply_config` 支持 `BASE_CONFIG` / `CONFIG_FRAGMENTS`
- `pre_defconfig`：复制主 `.config` 后、`make defconfig` 前执行
- `post_defconfig`：`make defconfig` 后执行
- `finalize`：构建前最后执行

`wrt_core/update.sh`：

- `pre_clone`：clone 前
- `post_clone`：clone / clean / reset feeds 后
- `pre_feeds`：feeds update 前
- `post_feeds_update`：feeds update 后
- `post_feeds_install`：feeds install 后

---

## 冲突与依赖

最小规则：

- `depends`：启用某 recipe 时，runner 自动补齐依赖
- `conflicts`：允许通过 `DISABLE_RECIPES` 在最终启用集里消解；若最终启用集中仍同时存在冲突双方，则直接报错
- 同一路径被多个 recipe 写入时，runner 必须直接报冲突，不允许静默覆盖

路径冲突检查至少覆盖：

- `actions.patches[].target` 冲突
- `actions.files[].target` 冲突
- `actions.configs[]` 重复注入

---

## IMPORT_PACKAGES registry 设计约束

`actions.importPackages[].source` 不直接等于 Git URL，而是交给 registry 映射。registry 由全局文件与 recipe 内联声明两部分合并得到。

全局文件：`wrt_core/recipes/import_registry.json`

recipe 内联位置：`actions.importPackagesRegistry`

格式与全局 registry 的单个 `sources` value 保持一致：

```json
{
  "actions": {
    "importPackagesRegistry": {
      "awg-openwrt": {
        "gitUrl": "https://github.com/Slava-Shchipunov/awg-openwrt.git",
        "branch": "master",
        "sparseRoot": null
      }
    }
  }
}
```

设计约束：

- recipe 只声明逻辑来源标识，不内嵌到 `importPackages` 项里
- 全局 registry 继续维护共享来源；recipe 可为自身补充独立来源
- runner 先合并全局 registry 与所有启用 recipe 的 `actions.importPackagesRegistry`
- 同名 source 允许重复声明仅当内容完全一致；不同内容直接报错
- runner 解析 `actions.importPackages` 时，必须先查合并后的 registry；未命中直接报错
- 导入目标默认是 `package/<name>`；显式 `target` 可覆盖
- 稀疏检出路径默认是 `<name>`；若 registry 设置 `sparseRoot`，则为 `<sparseRoot>/<name>`

---

## 为什么采用扁平 recipe 目录

扁平目录符合当前约束。

优点：

- 定位直接：一个目录就是一个 recipe
- 目标 ini 中引用稳定：`RECIPES=example_argon_base`
- runner 实现简单：只需扫描 `wrt_core/recipes/*/recipe.json`
- 减少“分类目录”和“功能目录”双重命名负担

代价：recipe 数量多了之后目录会变大。该代价可接受，因为分类可以放在 `tags` 字段里，plan 输出也比人工翻目录更常用。

---

## 已落地 recipe

当前首批可插拔 recipe：

- `fix_kernel_magic`
  - `post_clone`
  - 读取 target ini 的 `KERNEL_VERMAGIC` / `KERNEL_MODULES`
  - 修改内核 vermagic 与可选 kmod distfeed
- `awg`
  - `pre_defconfig`
  - 通过 `awg-openwrt` registry source 导入 AmneziaWG 三个包目录
  - 追加 AWG config fragment
- `upx`
  - `pre_defconfig`
  - 优先复用系统 `upx`，否则下载官方预编译包到构建树 `upx/upx`
- `tailscale_awg`
  - `pre_defconfig`
  - `depends: ["upx"]`
  - 删除官方 `tailscale` 包目录以避免同名冲突
  - 导入 `openwrt-tailscale-awg` 的 `package/tailscale`
  - 导入 `luci-app-tailscale-community` 并追加对应 config fragment
  - 不使用额外脚本；直接保留上游 Makefile 的非关键附加导出行为
  - 通过脚本清理第三方 `tailscale` Makefile 中仅用于仓库导出二进制的逻辑
- `ohmyzsh`
  - `pre_defconfig`
  - 预置 zsh config、oh-my-zsh 与插件

---

## 示例 recipe：example_argon_base

示例目录：

```text
wrt_core/recipes/example_argon_base/
  recipe.json
  apply.sh
  files/
    etc/
      uci-defaults/
        990_set_argon_primary
  patches/
    999-example.patch
  configs/
    example.config
```

这个 recipe 只用于演示架构。它同时展示了声明 feed 增删、导入外部包、删除构建树目录、补丁投放、文件覆盖、config fragment、脚本钩子。
