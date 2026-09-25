# 开发推进日志（DEVLOG）

> 按日期倒序记录每次推进：做了什么、产出物、遇到的问题、下一步。每条尽量可追溯到具体文件 / commit。

---

## 2026-09-26 · Day 2 · MVP 代码全量落地（共享层 / 服务端 / 客户端）

**阶段**：P2 MVP（代码完成，等待 Studio 实机验证）　**状态**：PRD §13.1 MVP 范围的全部系统已实现并通过本地门禁；**Roblox 运行时尚未实机跑过**（仅通过 Lune + Roblox API Mock 冒烟）。

### 完成
- **共享层**（`src/shared`，约 3.7k 行，纯 Luau、Lune 可跑）：34 只灵宠 / 16 技能 / 15 遗物 / 15 元天赋 / 6 远征事件 / 3 区 × 10 关 / 4 种蛋（含全部数值概率表）/ 营地三建筑 / 6 日常任务 / 轮回；远征地图生成（10 列 × 3 道分支）与 `Run` 状态机（移动 / 战斗 / 遗物三选一 / 事件 / 商店 / 篝火 / 弃局 / 结算）；养成规则 `PetInstance`（升级 / 进化 / 升星 / 融合 / 分解）；图鉴加成；数据模板。
- **服务端**（`src/server`，约 2.7k 行）：13 个服务（Data / Economy / Pet / Hatch / Battle / Stage / Expedition / Camp / Quest / Prestige / Announcement / Monetization / Arena）+ `WorldBuilder` 灰盒枢纽（9 个站点 ProximityPrompt）；ProfileStore 存档（vendored）；39 个远程接口统一 `ok, err, payload` 约定 + 类型校验 + 限流；货币只经 EconomyService；异步竞技场用 MemoryStore（按战力 / 按评分两张表，机器人补位，Elo K=32）；全服公告走 MessagingService；商业化：3 通行证 / 3 钻石包 / 4 钻石商品 / 7 日签到 / PolicyService 分流 / 幂等 ProcessReceipt。
- **客户端**（`src/client`，约 5.0k 行）：像素风组件库（`PixelTheme` + `Components`：面板 / 按钮 / 进度条 / 模态 / Toast / 确认框）；12 个界面（HUD、Battle 回放 1×/2×/3× + Skip + 结算、Pets、Hatch 含完整概率披露弹窗、Stages、Camp、Expedition、Arena、Codex、Quests + 签到、Shop、Prestige）；程序化体素灵宠模型（`PetModelFactory`，按 petId 哈希配色 + 稀有度形态变化）；战斗舞台事件回放（`BattleStage`，(0,300,0) 独立舞台 + 镜头接管）；跟随宠物 `Companion`。
- **测试 / 工具**：`lune run tools/test` 13,075 项通过；新增 `tools/roblox_mock.luau`（game/Players/DataStore/MemoryStore/MessagingService/PolicyService 的最小 Mock）与 `tools/server_smoke.luau`（151 项：加入 → 领取起始宠 → 推图 → 孵蛋 → 营地 → 远征整局 → 竞技场 → 任务 → 轮回 → 离线结算 → 限流 / 非法参数），种子固定、结果确定；`tools/pve_curve`（每关最低可过等级）、`tools/economy_model`（每区所需金币 / 活跃时长 / 挂机时长）。CI 增加冒烟步骤。
- **经济调参**（见 BALANCE.md「经济模型」）：关卡金币 35×2.5^(区−1)×1.12^(关−1)、经验 40×2^(区−1)×1.1^(关−1)；升级费 20·L^1.6·√稀有度；矿场 0.05×战力^0.6 币/s；蛋价 500 / 2,500 / 25,000 币 + 250 钻。结果：1 区约 1.2 h 活跃或 2.5 h 挂机，2 区 1.6 / 2.3 h，3 区 1.9 / 2.4 h。
- 决策：D-07 轮回采用**软重置**（保留灵宠 / 钻石 / 天赋 / 图鉴；重置关卡 / 金币 / 营地），已记入 DECISIONS。

### 问题 / 风险
- **未在 Roblox Studio 实机运行**：客户端代码只能过 StyLua / Selene / luau-analyze 静态检查，UI 布局、镜头、ProximityPrompt、ProfileStore 真实行为都需实机验证（清单见 README「Studio 验证清单」）。
- `src/shared` 使用字符串相对 `require("./X")`，依赖 Roblox 的字符串 require 支持；若 Studio 版本不支持需回退为实例路径。
- 通行证 / 开发者商品 ID 均为 0 占位，商店按钮显示 "Coming soon"；发布后填入真实 ID。
- MemoryStore / MessagingService / PolicyService 在 Studio 需开启 API 访问，否则竞技场只会看到机器人、公告仅本服。
- 像素字体 Press Start 2P 的 Font 资源可能不可用，`PixelTheme.font()` 会回退到 Arcade。

### 下一步
1. Studio 实机：`rojo serve` → 逐项过验证清单，修 UI / 运行时问题（预计一轮 1–2 天）。
2. 表现层补齐：伤害数字 / 状态图标 / 蓄力条、音效、站点模型替换灰盒。
3. 第二轮平衡：用真实玩家数据校准 PvE 曲线（当前 2 区 5–10 关、3 区 6–10 关对 Lv 需求跳变偏陡）。
4. 埋点 / 反作弊 / 远程配置（P2 剩余项）。

---

## 2026-09-25 · Day 1 · P0 开工：工程化 + 确定性战斗模拟器

**阶段**：P0 概念验证　**状态**：进行中（模拟器与配表完成，Roblox 端播放/UI 未开始）

### 项目所有者新增决定
- 游戏内文本 **全英文**；UI **像素风**（与体素世界统一）。

### 完成
- [x] GitHub 远端接入并推送（`Tera-Dark/voxel-pets`），后续每次推进自动 push。
- [x] 工程化：`rokit.toml`（工具版本锁定）、`stylua.toml`、`selene.toml`、`.luaurc`、`scripts/install_tools.sh`（本地 / CI 共用）、GitHub Actions CI（格式 → lint → 测试 → Rojo 构建 → 平衡快照）。
- [x] 共享配表 `src/shared/Config/`：Constants / Elements / Rarities（含蛋概率与校验）/ StatusEffects（8 种）/ Skills（9 个，带自动触发条件）/ Pets（3 初始 + 4 图鉴 + 6 野怪）/ Relics（15 个）/ Formulas。
- [x] 战斗核心 `src/shared/Combat/`：`Rng`（xorshift32，跨平台确定性）、`Builder`（养成 + 遗物 → 战斗单位，支持 `team[1..5]`）、`Simulator`（0.1 s tick、自动施法 AI 四类触发、蓄力/打断、8 状态、护盾、复活、狂暴、事件序列输出）。
- [x] 工具 `tools/`：`test.luau`（108 项断言：配表校验 / 元素 / 公式 / RNG / 确定性 / 500 场随机不变量 / 机制）、`sim_replay`、`sim_batch`、`tune_roles`。
- [x] 三轮数值调参（详见 `docs/BALANCE.md`）：修复 +HP 遗物无效 bug；发现并修复"攻击 > 坦克 > 辅助 100%"的职业失衡；元素 1.3/0.77；减伤公式改为攻方 ATK 相对制；加入狂暴机制。

### 关键设计结论（写回 PRD v0.3）
- 减伤公式改为 `DEF / (DEF + 1.5 × 攻方ATK)`：尺度无关，双方同倍放大不改变战斗形态（原按等级的公式在高稀有度下会让 DEF 溢出）。
- 自动战斗方差低，稳定的小优势会被放大成大胜率 → 元素倍率必须温和（1.3/0.77），"被克必败"只能靠**节点预告 + 遗物**缓解，D-12 保留观察。
- 狂暴开始时间是强敏感参数（25 s → 20 s 让攻击 vs 坦克从 50% 跳到 76%）。

### 问题 / 风险
- 代码使用 Luau **字符串相对 require**（`require("./Rng")`）以便 Roblox 与 Lune 共用；需在 Studio 里验证当前 Roblox 版本对字符串 require 的支持（若不支持，改为 `script.Parent` 并给 Lune 写一层适配）。
- 仍未在 Roblox Studio 中运行过——P0 下一步就是把模拟器接进服务端并做客户端播放。

### 下一步（P0 剩余）
1. Roblox 端：服务端 `BattleService`（调用 Simulator → 下发事件序列）、客户端 `BattlePlayback`（伤害数字、状态图标、蓄力条、1×/2×、跳过）、灰盒 32 格灵宠占位模型。
2. 灰盒 Rogue：1 层 10 节点、三选一、节点元素预告。
3. 孵蛋（含概率展示）、矿场产币、ProfileStore 存档。

---

## 2026-09-25 · Day 0（下午）· 项目所有者反馈落地

**阶段**：立项评估　**状态**：文档更新完成，等待推送凭证

### 项目所有者决定
1. 美术：灵宠体素精度 **32 格起始**（原 PRD 为 16/24/32）。
2. 战斗：**全自动**，玩家只能通过「局内 Rogue 加成」和「局外养成」影响胜负。
3. 队伍：**1v1 起步**，后续视情况解锁 3 格，上限 5 格。
4. 远端仓库：github.com/Tera-Dark/voxel-pets（已创建，空仓库）。

### 完成
- [x] PRD 升级至 **v0.2**（`docs/PRD/PRD.md`，改为 living doc）：第 5 章战斗系统整体重写（全自动 / 确定性模拟 / 自动施法 AI / 1v1 被克缓解 / 格数路线）；FTUE、Rogue 结构、PvP、美术规范、MVP、P0 目标、技术方案、风险、决策表同步更新。
- [x] `DECISIONS.md`：D-01 / D-02 / D-09 已定，新增 D-11（格数）已定、D-12（后备换人）待定。
- [x] `ROADMAP.md`：P0 任务改为"确定性模拟器 + 自动施法 AI + 平衡工具 + 灰盒 Rogue"。
- [x] 概念图：新增 CA-04（32 格精度基准），CA-01 标记为"方向通过、精度升级"。

### 问题 / 风险
- 沙盒内没有可用的 GitHub 推送凭证（环境变量 / credential helper 均为空），`git ls-remote` 可读但 push 需要 token → 已配置 `origin`，等待项目所有者提供 fine-grained PAT 后推送。

### 下一步
- 拿到凭证 → push 全部提交。
- 项目所有者确认 CA-04 精度观感 → 进入 **P0**（见 ROADMAP）。

---

## 2026-09-25 · Day 0 · 立项评估

**阶段**：立项评估　**状态**：进行中

### 完成
- [x] 完成 PRD v0.1（`docs/PRD/PRD_v0.1.md`）：核心循环、宠物 / 战斗 / PvE / Rogue / 放置 / 成长 / 收集 / 商业化 / 技术 / MVP 范围 / 开发计划。
- [x] 创建项目仓库骨架（Rojo 工程结构、文档目录、.gitignore、辅助脚本）。
- [x] 生成首批概念图 3 张，提交审核（`docs/concept-art/`）：
  1. 三只初始灵宠（焰尾狐 / 潮汐蛙 / 苔藓龟）—— 验证灵宠造型与体素风格
  2. 新芽草原 · 灵宠营地 —— 验证主城 / 放置场景风格
  3. 迷雾远征 · 深渊 Boss 战 —— 验证 Rogue 场景氛围与 Boss 体量
- [x] 概念图自检：CA-01 / CA-02 通过；CA-03 v1 前景角色非体素风 → 重绘 v2（全体素化）通过自检。
- [x] 仓库工程化：图片压缩脚本（`scripts/optimize_images.py`，概念图入库前压至 ≤1600px JPG）；全局 git 身份。

### 问题 / 风险
- 沙盒快照不保存 `.git/config`，远端与本地身份需用 `scripts/git_remote_setup.sh` 重建（已验证全局 `~/.gitconfig` 可持久化）。
- 概念图为 AI 生成，同一灵宠在不同图中比例略有差异；正式资产以 CA-01 的 24 格比例为准。

### 待决策（阻塞项）
- [ ] GitHub 远端仓库（需要仓库地址 + 推送权限）
- [ ] 概念图审核：通过 / 调整方向
- [ ] PRD 第 16 章 8 项设计决策（见 `docs/DECISIONS.md`）

### 下一步
- 概念图通过后进入 **P0 概念验证**：
  - Rojo 工程初始化 + 代码规范配置
  - 服务端权威战斗原型（元素克制、技能冷却、伤害公式）
  - 3 只灰盒灵宠 + 1 个关卡 + 孵蛋 + 矿场产币
  - 退出标准：内部试玩"战斗好玩"≥ 4/5

---

<!-- 模板
## YYYY-MM-DD · Day N · <阶段>
**阶段**：　**状态**：
### 完成
### 问题 / 风险
### 下一步
-->
