# 方块灵宠：无尽远征 · Voxel Pets: Endless Expedition

> Roblox 3D 体素风宠物收集对战游戏 —— PvE 推图 · Rogue 远征 · PvP 竞技 · 放置增量 · 全维收集

| 项目 | 状态 |
|---|---|
| 当前阶段 | **立项评估**（PRD v0.1 已完成，概念图审核中） |
| 下一里程碑 | P0 概念验证原型（灰盒战斗 + 孵蛋 + 矿场产币，3 周） |
| 引擎 / 语言 | Roblox Studio · Luau · Rojo |
| 目标平台 | Roblox 全平台，移动端优先 |

## 文档索引

| 文档 | 说明 |
|---|---|
| [docs/PRD/PRD_v0.1.md](docs/PRD/PRD_v0.1.md) | 产品需求文档（完整设计） |
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

## 本地开发（P0 开始后生效）

1. 安装 [Rojo](https://rojo.space/)（Roblox Studio 插件 + CLI）与 [Wally](https://wally.run/)。
2. `rojo serve default.project.json`，在 Studio 中连接。
3. 代码规范：`StyLua` 格式化，`Selene` 静态检查（配置文件将在 P0 添加）。

## 版权

© 2026 项目所有者，保留所有权利。仓库内容仅用于本项目开发。
