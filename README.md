# 方块灵宠：无尽远征 · Voxel Pets: Endless Expedition

> Roblox 3D 体素风宠物收集对战游戏 —— 全自动战斗 · PvE 推图 · Rogue 远征 · PvP 竞技 · 放置增量 · 全维收集
>
> 核心原则：**决策在战前，爽感在战中** —— 玩家只通过「局外养成」与「局内 Rogue 加成」影响胜负。

| 项目 | 状态 |
|---|---|
| 当前阶段 | **MVP 代码完成，待 Studio 实机验证**（共享层 / 服务端 / 客户端全部落地；13,091 项单元测试 + 151 项服务端冒烟通过） |
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

lune run tools/test                     # 13,091 项单元测试（tools/tests/ 五套件）
lune run tools/server_smoke             # 151 项服务端冒烟（Roblox API Mock，完整玩家旅程）
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

## Studio 验证清单（首次实机）

1. `rojo build default.project.json -o VoxelPets.rbxl` → Studio 直接打开即可测大部分条目（未开 API 访问时 ProfileStore 自动切内存模式：能玩但不存档；竞技场只有机器人、公告仅本服）。要测存档（第 10 条）与真实竞技场榜：先 **File → Publish to Roblox**（未发布的 place 无法改安全设置），再到 Game Settings → Security 开启 **Enable Studio Access to API Services**。
2. 输出窗口应看到 `[VoxelPets] server ready` 与 `[VoxelPets] client ready`；若 `src/shared` 的字符串相对 `require("./X")` 报错，说明当前 Studio 不支持字符串 require，需要改回实例路径。
3. 出生点周围 9 个发光柱子 = 站点，靠近按 E 打开对应界面；左侧菜单也能打开全部界面。
4. Stages → 1-1 → 观察镜头切到 (0,300,0) 的战斗舞台、HP 条 / 日志 / 结算，1×/2×/3× 与 Skip 可用；胜利后 Next 连续推图。
5. Hatch → `Details (odds)` 弹窗应列出每只灵宠的精确百分比且合计 100%；买一颗 Meadow Egg。
6. Camp 分配一只非出战宠 → 等 5 s 看 Pending 增长 → Collect。
7. 通关 1-5 后 Expedition 可开：走一整层（战斗 / 遗物三选一 / 事件 / 商店 / 篝火 / Boss）。
8. Arena：无其他玩家时应看到 3 个 `[BOT]`；打一场看评分变化。
9. Quests / Shop / Codex / Prestige 打开无报错；Shop 里通行证与钻石包按钮显示 "Coming soon"（ID 为 0 占位，发布后填入 `MonetizationService.Passes/Products`）。
10. 退出再进：存档保留；离开 ≥ 1 分钟再进应弹 "Welcome back!" 离线报告。
11. 像素字体：若 Press Start 2P 不可用，`PixelTheme.font()` 回退到 Arcade，属预期。

## 版权

© 2026 项目所有者，保留所有权利。仓库内容仅用于本项目开发。
