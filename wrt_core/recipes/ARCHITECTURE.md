# Recipe 系统说明

## 用途

本文档同时面向两类读者：

- 人类维护者：快速理解 recipe 系统的边界、字段、执行顺序和限制
- AI 助手：结合本文档与现有代码，直接新增、修改或排查 recipe

本文档描述的是当前实现，不是历史设计稿。若文档与代码冲突，以 `wrt_core/recipe.sh`、`wrt_core/recipes/recipe.schema.json` 和现有 recipe 为准，并应优先修正文档。

---

## 系统边界

recipe 系统的目标是把一部分构建定制逻辑从 `wrt_core/update.sh` 的固定函数流程中拆出来，改为由 `recipe.json` 声明并由 `wrt_core/recipe.sh` 统一执行。

recipe 系统负责：

- 选择当前目标启用哪些 recipe
- 校验 recipe 元数据与动作字段
- 按阶段和依赖顺序执行 recipe
- 导入外部包、复制文件、追加 config、应用补丁、执行脚本

recipe 系统不负责：

- 替代 `wrt_core/compilecfg/*.ini` 作为目标入口配置
- 替代 `wrt_core/deconfig/*.config` 作为主目标配置来源
- 接管 `update.sh` 中所有历史静态修正逻辑

当前目标配置入口仍然是 `wrt_core/compilecfg/*.ini`。

---

## 目录结构

`wrt_core/recipes/` 采用扁平目录。每个一级子目录就是一个 recipe。

```text
wrt_core/
  recipe.sh
  recipes/
    import_registry.json
    recipe.schema.json
    import-registry.schema.json
    <recipe-name>/
      recipe.json
      apply.sh
      files/
      patches/
      configs/
```

约定：

- recipe 名必须等于目录名
- recipe 名必须全局唯一
- 每个 recipe 目录都必须包含 `recipe.json`
- `apply.sh`、`files/`、`patches/`、`configs/` 都是可选的
- recipe 元数据只使用 JSON，并通过 `jq` 读取
- 不引入 `recipes/core/`、`recipes/ui/` 之类二级分类目录

---

## 目标 ini 字段

recipe 系统会从 `wrt_core/compilecfg/<target>.ini` 读取目标级控制字段。

当前相关字段如下：

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

字段说明：

- `BASE_CONFIG`：主 `.config` 路径；未设置时回退到 `deconfig/<target>.config`
- `CONFIG_FRAGMENTS`：额外 config 片段列表，逗号分隔
- `RECIPES`：显式启用的 recipe 名列表，逗号分隔
- `DISABLE_RECIPES`：显式禁用的 recipe 名列表，逗号分隔
- `TARGET_TAGS`：目标标签列表，逗号分隔，供 `when.tags` 过滤使用
- `KERNEL_VERMAGIC` / `KERNEL_MODULES`：由 `fix_kernel_magic` 等 recipe 消费的目标参数

最小示例：

```ini
REPO_URL=https://github.com/immortalwrt/immortalwrt.git
REPO_BRANCH=master
BUILD_DIR=immortalwrt

BASE_CONFIG=deconfig/x64_immwrt.config
CONFIG_FRAGMENTS=deconfig/compile_base.config,deconfig/proxy.config

RECIPES=fix_kernel_magic,awg,tailscale_awg
DISABLE_RECIPES=
TARGET_TAGS=x86_64,immortalwrt,master
```

启用语义：

- `enabled: true` 只表示默认进入候选集，不表示一定会执行
- `RECIPES` 可以显式启用默认关闭的 recipe
- `DISABLE_RECIPES` 可以显式移除默认启用或显式追加的 recipe
- 即使 recipe 已进入候选集，只要 `when.*` 不匹配，最终仍会被跳过

---

## recipe.json 最小模板

新增 recipe 时，优先从下面这个最小模板开始，而不是复制一个复杂 recipe 再删减。

```json
{
  "$schema": "../recipe.schema.json",
  "name": "example_recipe",
  "description": "一句话说明这个 recipe 做什么",
  "enabled": false,
  "priority": 0,
  "phase": "pre_defconfig",
  "depends": [],
  "conflicts": [],
  "tags": [],
  "when": {
    "targets": [],
    "repo": [],
    "branch": [],
    "tags": []
  },
  "actions": {
    "addFeeds": [],
    "removeFeeds": [],
    "importPackagesRegistry": {},
    "importPackages": [],
    "removePackageDirs": [],
    "patches": [],
    "files": [],
    "configs": [],
    "script": null
  }
}
```

规则：

- `name` 必须等于目录名
- `description` 应描述结果，不要只写实现手段
- `enabled` 决定是否默认进入候选集
- `priority` 仅影响同一阶段、且依赖关系不冲突时的排序；数值越大越靠前
- `phase` 必须属于固定枚举
- `depends` 由 planner 自动补齐到构建计划中
- `conflicts` 若在最终计划中同时出现会直接报错
- `tags` 用于分类和目标条件匹配之外的辅助理解，不参与默认启用逻辑

---

## 条件过滤

`when` 用于限制 recipe 只在特定目标下生效。

```json
"when": {
  "targets": [],
  "repo": [],
  "branch": [],
  "tags": []
}
```

含义：

- `when.targets`：只允许这些 `TARGET_NAME`
- `when.repo`：只允许这些 `REPO_URL`
- `when.branch`：只允许这些 `REPO_BRANCH`
- `when.tags`：只要命中当前目标任意一个 `TARGET_TAGS` 即视为匹配

匹配规则：

- 空数组表示不限
- 任一条件不匹配时，recipe 会被跳过，而不是报错
- 当前实现会打印 `recipe: skipping <name> because when conditions do not match target`
- 依赖补齐后会再次执行一轮条件过滤，防止补进来的依赖绕过条件检查

---

## 动作字段

`actions` 描述 recipe 具体要做什么。

### `addFeeds`

- 作用：向 `feeds.conf` 或 `feeds.conf.default` 追加 feed 条目
- 类型：字符串数组

### `removeFeeds`

- 作用：删除指定 feed 标识
- 类型：字符串数组

### `importPackagesRegistry`

- 作用：为当前 recipe 提供额外的导入源定义
- 类型：对象
- 键名：逻辑 source 名
- 值：`gitUrl`、可选 `branch`、可选 `sparseRoot`

示例：

```json
"importPackagesRegistry": {
  "awg-openwrt": {
    "gitUrl": "https://github.com/Slava-Shchipunov/awg-openwrt.git",
    "branch": "master",
    "sparseRoot": null
  }
}
```

### `importPackages`

- 作用：从 source 对应仓库导入目录到构建树，并将其以包名形式注册到本地 `custom_feed` 中，以防止编译到 `base` 目录。
- 类型：对象数组
- 必填字段：`source`、`path`
- 可选字段：`packageName`

示例：

```json
"importPackages": [
  {
    "source": "awg-openwrt",
    "path": "kmod-amneziawg"
  },
  {
    "source": "luci-theme-argon-custom",
    "path": ".",
    "packageName": "luci-theme-argon"
  }
]
```

导入规则：

- `source` 必须能在当前 recipe 的 `importPackagesRegistry` 或全局 `import_registry.json` 中找到
- `path` 表示仓库内要导入的目录路径，不是包名字段
- **`packageName` 推导与注册逻辑**：
  * **显式指定**：如果设置了 `packageName`，则提取其 `basename` 作为最终的注册包名（如 `"packageName": "luci-theme-argon"` $\rightarrow$ 包名即为 `luci-theme-argon`）。
  * **隐式推导**：未配置 `packageName` 时，系统会自动提取 `path` 的最后一部分名称（`basename`）作为最终的注册包名（如 `"path": "kmod-amneziawg"` $\rightarrow$ 包名为 `kmod-amneziawg`；`"path": "package/tailscale"` $\rightarrow$ 包名为 `tailscale`）。
  * **强制限制**：若 `path` 为 `"."`（导入仓库根目录），默认推导出的包名为 `.` 导致校验失败。因此，当 `path` 设定为 `"."` 时，**必须显式提供 `packageName`**，否则 Recipe 前置校验阶段会直接报错退出。
- 导入的目标路径固定为 `custom_feed/<包名>`，且导入后会自动执行本地 `custom_feed` 的 update 和 install 动作
- 若 source 定义了 `sparseRoot`，实际导入源路径会解析为 `<sparseRoot>/<path>`

### `removePackageDirs`

- 作用：删除构建树中的已有目录，常用于移除同名官方包或旧包
- 类型：字符串数组

### `patches`

- 作用：对构建树应用补丁
- 类型：对象数组
- 必填字段：`source`、`target`
- 可选字段：`strip`、`binary`、`ignoreWhitespace`、`forward`、`backup`、`rejectFile`、`fuzz`

说明：

- `source` 相对 recipe 目录
- `target` 相对 `BUILD_DIR`
- 补丁应用逻辑由 `recipe.sh` 按当前字段执行

### `files`

- 作用：复制普通文件到构建树
- 类型：对象数组
- 必填字段：`source`、`target`
- 可选字段：`mode`

说明：

- `source` 相对 recipe 目录
- `target` 相对 `BUILD_DIR`
- `mode` 缺省为 `0644`

### `configs`

- 作用：将 config fragment 追加到目标 `.config`
- 类型：字符串数组
- 每项都相对 recipe 目录

### `script`

- 作用：执行无法用声明式字段表达的补充逻辑
- 类型：字符串或 `null`
- 路径相对 recipe 目录

使用原则：

- 能用声明式字段表达时，不要退回 `script`
- `script` 必须幂等
- `script` 只做该 recipe 自身职责，不要在其中塞通用框架逻辑

---

## 执行阶段

当前固定阶段如下：

- `pre_clone`
- `post_clone`
- `pre_feeds`
- `post_feeds_update`
- `post_feeds_install`
- `pre_defconfig`
- `post_defconfig`
- `finalize`

阶段含义：

- `pre_clone`：clone 前
- `post_clone`：clone / clean / reset feeds 后
- `pre_feeds`：feeds update 前
- `post_feeds_update`：feeds update 后
- `post_feeds_install`：feeds install 后
- `pre_defconfig`：主 `.config` 已写入构建树、`make defconfig` 前
- `post_defconfig`：`make defconfig` 后
- `finalize`：正式编译前最后一步

接入位置：

- `wrt_core/update.sh` 负责 `pre_clone` 到 `post_feeds_install`
- `build.sh` 负责 `pre_defconfig`、`post_defconfig`、`finalize`

选阶段建议：

- 修改源码树、feed 源、包目录：优先放在 `post_clone`、`post_feeds_update` 或 `post_feeds_install`
- 导入第三方包、追加 package config：通常放在 `pre_defconfig`
- 依赖 `.config` 已经 defconfig 展开后的处理：放在 `post_defconfig`
- 编译前最终修整：放在 `finalize`

---

## 计划生成流程

当前 planner 实现在 `recipe_build_plan()`，顺序如下：

1. 校验全局 `import_registry.json`
2. 扫描全部 `recipe.json`，收集 `enabled: true` 的 recipe
3. 读取目标 ini 的 `RECIPES` 并追加到候选集
4. 读取目标 ini 的 `DISABLE_RECIPES` 并从候选集中移除
5. 解析 `depends`，补齐依赖
6. 按 `when.targets` / `when.repo` / `when.branch` / `when.tags` 过滤不匹配项
7. 再做一轮依赖补齐和条件过滤
8. 检查依赖完整性，防止某个已启用 recipe 的依赖在过滤后缺失
9. 检查 `conflicts`
10. 校验动作路径是否安全
11. 校验会写入的目标路径与 config 片段是否冲突
12. 加载全局 import registry
13. 校验 `importPackages[].source` 是否都能解析到 source 定义
14. 按阶段、依赖和 `priority` 排序

补充说明：

- 同一阶段内部采用依赖拓扑排序
- 若同一阶段内没有依赖关系，则按 `priority` 从高到低排序
- 如果同一阶段出现循环依赖，会直接报错

---

## 执行顺序

单个 recipe 在其所属阶段内按下面顺序执行：

1. `actions.addFeeds`
2. `actions.removeFeeds`
3. `actions.importPackages`
4. `actions.removePackageDirs`
5. `actions.patches`
6. `actions.files`
7. `actions.configs`
8. `actions.script`

这意味着：

- 若某个补丁要打在刚导入的包上，放在同一个 recipe 中是可行的
- 若某个脚本依赖前面复制的文件或追加的 config，应放在同一 recipe 的 `script`
- 若两个 recipe 对顺序有要求，优先通过 `depends` 表达，而不是赌当前目录扫描顺序

---

## 当前校验与限制

当前实现会做以下校验：

- `recipe.json` 基本结构和字段类型校验
- `name == 目录名`
- `phase` 属于固定枚举
- `when.*` 条件匹配校验
- 依赖完整性校验
- 冲突校验
- 路径安全校验
- import source 存在性校验

当前实现的路径相关限制：

- `actions.files[].target` 不能与其他 recipe 重复
- `actions.configs[]` 不能重复引用同一个已解析 config 源路径
- `actions.files[].source` / `.target`、`actions.patches[].source` / `.target`、`actions.removePackageDirs[]`、`actions.importPackages[].target`、`actions.configs[]` 都必须是安全相对路径

注意：

- 目前实现没有单独对 `actions.patches[].target` 做跨 recipe 目标冲突检查
- 需要这类校验时，应先更新实现，再更新文档

---

## 如何新增一个 recipe

推荐步骤：

1. 先判断需求是否适合做成 recipe
2. 选择最小必要阶段
3. 创建目录 `wrt_core/recipes/<recipe-name>/`
4. 写 `recipe.json`
5. 如有需要，再补 `configs/`、`files/`、`patches/`、`apply.sh`
6. 在某个目标 ini 的 `RECIPES` 中显式启用，或把 `enabled` 设为 `true`
7. 运行 `./build.sh <target> recipe_preview` 检查最终计划
8. 如需要交互调整目标开关，运行 `./build.sh <target> recipe_config`

判断标准：

- 适合 recipe：导入包、补丁、文件覆盖、config fragment、有限的目标定制脚本
- 不适合 recipe：与 recipe 无关的全局框架逻辑、复杂流程控制、一次性迁移脚本

---

## 新增 recipe 编写规则

新增或修改 recipe 时，遵循以下规则：

- 优先复用声明式字段，不要一上来写 `apply.sh`
- `description` 写清结果，不写模糊描述
- `depends` 只表达真实依赖，不要拿它当排序开关
- `conflicts` 只用于互斥关系，不用于默认关闭
- `priority` 只在同阶段且无直接依赖约束时使用
- `TARGET_TAGS` 和 `when.tags` 适合表达目标族、发行版、分支等条件
- 若导入第三方仓库目录，先确认仓库布局，再决定 `path` 和 `target`
- 若导入仓库根目录，优先显式写 `target`
- 若删除已有目录，确认删除路径是构建树内路径，而不是 recipe 自身路径
- 若写 `apply.sh`，要保证重复执行结果稳定

---

## 调试与验证

常用方式：

- `./build.sh <target> recipe_preview`
  - 只输出当前目标的 recipe 计划
- `./build.sh <target> recipe_config`
  - 交互式切换目标级 `RECIPES` / `DISABLE_RECIPES`
- `./build.sh <target> debug`
  - 跑到 `make defconfig` 后停止，适合检查 config 合并结果

排查方向：

- recipe 没进入计划：检查 `enabled`、`RECIPES`、`DISABLE_RECIPES`、`when.*`
- recipe 被跳过：检查 `TARGET_NAME`、`REPO_URL`、`REPO_BRANCH`、`TARGET_TAGS`
- source 找不到：检查 `importPackages[].source` 是否在本 recipe 或全局 registry 中定义
- 导入路径不对：检查 `path`、`target`、`sparseRoot`
- 顺序不对：先检查 `depends`，再检查 `priority` 和阶段
- 冲突报错：检查 `conflicts`、重复 `files[].target`、不安全路径

---

## 当前已落地 recipe

当前仓库中已有这些 recipe：

- `fix_kernel_magic`
- `awg`
- `upx`
- `tailscale_awg`
- `ohmyzsh`
- `luci_app_daed`
- `luci_theme_argon`
- `default_theme_argon`
- `luci_theme_fluent`
- `default_theme_fluent`

其中当前默认启用的是：

- `luci_theme_argon`
- `default_theme_argon`

阅读现有 recipe 时，建议优先参考：

- `awg`：最简单的第三方包导入 + config fragment
- `luci_theme_argon`：仓库根目录导入 + 文件覆盖
- `default_theme_argon`：依赖 + 冲突 + `apply.sh`
- `tailscale_awg`：多 source、删除旧目录、打补丁、追加 config

---

## 给 AI 的直接规则

如果你是 AI 助手，并准备直接修改或新增 recipe，请先遵守下面的规则：

1. 先读本文档，再读 `wrt_core/recipe.sh`、`wrt_core/recipes/recipe.schema.json` 和相近 recipe
2. 不要发明文档里不存在的新字段
3. 若必须新增字段，必须同步更新 schema、实现和文档
4. 不要把 recipe 放到二级分类目录
5. 不要再引入任何 `recipe.ini` 或其他旧式 recipe 元数据格式
6. 不要把一次性或全局框架逻辑塞进某个 recipe
7. 能用声明式动作表达时，不要改成脚本
8. 修改后至少用 `recipe_preview` 验证计划是否符合预期
9. 若文档与实现不一致，先以实现为准，再修正文档

这份文档的目标不是解释所有历史背景，而是帮助你用最少上下文完成正确修改。
