# 方块灵宠：无尽远征 · Voxel Pets: Endless Expedition

> Roblox 3D 体素风宠物收集对战游戏 —— 全自动战斗 · PvE 推图 · Rogue 远征 · PvP 竞技 · 放置增量 · 全维收集
>
> 核心原则：**决策在战前，爽感在战中** —— 玩家只通过「局外养成」与「局内 Rogue 加成」影响胜负。

| 项目 | 状态 |
|---|---|
| 当前阶段 | **MVP 代码完成，Studio 实机验证中**（首次实机卡加载已修复；单元 13,092 · 服务端冒烟 152 · 启动鲁棒性 43 · 客户端端到端 108 全部通过） |
| 下一里程碑 | Studio 实机跑通验证清单 → 内部试玩（10 人）→ 表现层补齐 |
| CI | ![CI](https://github.com/Tera-Dark/voxel-pets/actions/workflows/ci.yml/badge.svg) |
| 引擎 / 语言 | Roblox Studio · Luau · Rojo |
| 目标平台 | Roblox 全平台，移动端优先 |

## 文档索引

| 文档 | 说明 |
|---|---|
| [docs/PRD/PRD.md](docs/PRD/PRD.md) | 产品需求文档（living doc，当前 v0.3） |
| [docs/BALANCE.md](docs/BALANCE.md) | 数值平衡记录（方法、调参日志、最新快照） |
| [docs/DEVLOG.md](docs/DEVLOG.md) | **开发推进日志**（按日期记录每一步进展） |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 里程碑与任务清单（P0 → P4） |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 设计 / 技术决策记录 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 架构说明（分层 / require 约定 / 规模红线 / 鲁棒性约定 / 体检报告） |
| [docs/concept-art/](docs/concept-art/) | 概念图与美术方向审核记录 |

## 仓库结构

```
voxel-pets/
├── default.project.json   # Rojo 工程定义（src → Roblox DataModel 映射）
├── src/
│   ├── server/            # ServerScriptService（服务端权威：战斗结算、经济、存档）
│   ├── client/            # StarterPlayerScripts（输入、UI、表现）
│   └── shared/            # ReplicatedStorage（配置表、公式、类型定义）
├── assets/
│   ├── models/            # 体素模型源文件（.vox / .obj / .fbx）
│   └── textures/
├── docs/                  # PRD、日志、路线图、决策、概念图
└── scripts/               # 辅助脚本
```

## 本地开发

```bash
# 工具链（Windows/macOS 用 rokit: `rokit install`；Linux/CI 用脚本）
./scripts/install_tools.sh ~/bin && export PATH=~/bin:$PATH

lune run tools/test                     # 13,092 项单元测试（tools/tests/ 五套件）
lune run tools/server_smoke             # 152 项服务端冒烟（Roblox API Mock，完整玩家旅程）
lune run tools/boot_smoke               # 43 项启动鲁棒性（虚拟时间调度：挂起 / 崩溃 / 回退场景）
lune run tools/client_smoke             # 108 项客户端端到端（真实客户端脚本 × 真实服务端，全部界面 + 主流程）
python3 scripts/check_roblox_api.py     # 属性 / 枚举 / 服务名对照 Roblox API Dump 校验
lune run tools/sim_replay -- Emberfox ThornbackBoar 42 InsightLens   # 单场逐事件日志
lune run tools/sim_batch -- --quick     # 平衡快照（胜率 / 时长矩阵；去掉 --quick 跑 N=1000）
lune run tools/tune_roles               # 职业模板网格搜索
lune run tools/pve_curve                # 每关最低可过等级（PvE 曲线）
lune run tools/economy_model            # 每区所需金币 / 活跃时长 / 挂机时长
stylua src tools && selene src tools    # 格式化 + lint
rojo build default.project.json -o VoxelPets.rbxl   # 产出可直接在 Studio 打开的 place
rojo serve default.project.json         # 或：在 Roblox Studio 中用 Rojo 插件连接
```

代码约定：游戏内文本与代码标识符全英文；`src/shared` 不得依赖 Roblox API（保证 Lune 可运行）；模块间使用字符串相对 `require`；文件规模与鲁棒性约定见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 系统总览（MVP）

| 层 | 内容 |
|---|---|
| `src/shared` | 配表（34 灵宠 / 16 技能 / 15 遗物 / 15 天赋 / 3 区 30 关 / 4 蛋 / 营地 / 任务 / 轮回 / 签到）、确定性战斗模拟器、远征地图与 Run 状态机、养成规则、图鉴、数据模板、远程接口清单 |
| `src/server` | 13 个服务（存档 / 经济 / 灵宠 / 孵蛋 / 战斗 / 关卡 / 远征 / 营地 / 任务 / 轮回 / 公告 / 商业化 / 竞技场）+ 灰盒枢纽世界生成 |
| `src/client` | 像素风组件库、12 个界面、战斗舞台回放、程序化体素宠物模型、跟随宠物 |

## 实机测试指南（给项目所有者：不需要任何开发知识）

**每次测试只需 3 步：**
1. 在工作区下载最新的 `VoxelPets.rbxl`，双击用 Roblox Studio 打开。
2. 点顶部的 **Play（▶）**。
3. 按下面的"应该看到"逐条体验；**任何不对劲就截图发给开发者**（截整个画面即可）。

**应该看到：**
- 几秒内加载界面的三行变成 `[OK]` 并进入游戏；屏幕顶部有红色小条 **TEST MODE - progress is not saved**（本地测试不存档，属正常）。
- 身后跟着一只方块宠物；左侧是菜单（Pets / Battle / Hatch / Camp / ...），出生点周围有 9 个发光柱子，走近按 **E** 打开对应界面。
- **Battle**：选关卡点 FIGHT → 镜头切到战斗舞台自动开打；可用 1×/2×/3× 和 SKIP；赢了点 Next 继续。
- **Hatch**：先点 `Details (odds)` 看概率（每只宠物都有百分比，合计 100%），再孵一颗蛋。
- **Camp**：点 `+ assign pet` 派一只宠物打工，等一会儿点 COLLECT。
- 通关 1-5 后 **Expedition** 解锁：走一整层（战斗 / 选遗物 / 事件 / 商店 / 篝火 / Boss）。
- **Arena / Quests / Shop / Codex / Prestige** 都能打开；在 Shop 点 Robux 商品会提示 "Coming soon" 属正常（还没上架）。

**出问题时怎么截图：**
- 卡在加载界面 → 等 20 秒，界面会显示诊断信息，直接截图。
- 游戏里左下角出现红色 **ERR** 按钮 → 点一下打开开发者日志，截图。
- 某个界面显示 "could not open" → 截图。

<details><summary>开发者附注（Studio 高级设置）</summary>

- 想测试存档：File → Publish to Roblox 发布，然后 Game Settings → Security 开启 **Enable Studio Access to API Services**；此时 Studio 使用独立存档 `PlayerData_studio_v1`（不影响线上），TEST MODE 标识消失。
- 若 `src/shared` 的字符串 `require("./X")` 在某 Studio 版本不支持，客户端加载界面会显示 "game scripts failed to load"。
- 通行证 / 开发者商品 ID 为 0 占位，发布后填入 `MonetizationService.Passes/Products`。
- 像素字体 Press Start 2P 不可用时 `PixelTheme.font()` 回退到 Arcade，属预期。
</details>

## 版权

© 2026 项目所有者，保留所有权利。仓库内容仅用于本项目开发。
