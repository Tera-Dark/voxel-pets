# 方块灵宠：无尽远征 · Voxel Pets: Endless Expedition

> Roblox 3D 体素风宠物收集对战游戏 —— 全自动战斗 · PvE 推图 · Rogue 远征 · PvP 竞技 · 放置增量 · 全维收集
>
> 核心原则：**决策在战前，爽感在战中** —— 玩家只通过「局外养成」与「局内 Rogue 加成」影响胜负。

| 项目 | 状态 |
|---|---|
| 当前阶段 | **P0 概念验证**（确定性战斗模拟器 + 配表 + 平衡工具已完成；Roblox 端播放 / UI 进行中） |
| 下一里程碑 | P0 退出：Studio 可玩的 1v1 自动战斗 + 灰盒 Rogue 1 层 + 孵蛋 + 矿场 |
| CI | 配置已就绪（`ci/`），待 token 开通 workflow 权限后启用 |
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

lune run tools/test                     # 108 项测试
lune run tools/sim_replay -- Emberfox ThornbackBoar 42 InsightLens   # 单场逐事件日志
lune run tools/sim_batch                # 平衡快照（胜率 / 时长矩阵）
lune run tools/tune_roles               # 职业模板网格搜索
stylua src tools && selene src          # 格式化 + lint
rojo serve default.project.json         # 在 Roblox Studio 中连接
```

代码约定：游戏内文本与代码标识符全英文；`src/shared` 不得依赖 Roblox API（保证 Lune 可运行）；模块间使用字符串相对 `require`。

## 版权

© 2026 项目所有者，保留所有权利。仓库内容仅用于本项目开发。
