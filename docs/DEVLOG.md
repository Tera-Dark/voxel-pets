# 开发推进日志（DEVLOG）

> 按日期倒序记录每次推进：做了什么、产出物、遇到的问题、下一步。每条尽量可追溯到具体文件 / commit。

---

## 2026-09-26 · Day 4 · HUD 重做（底部功能坞 + 渐进解锁）· 新手教程 · "No active pet" 修复 · QoL

**阶段**：P0 收口　**状态**：v0.2.0，全部门禁绿：单元 13,149 · 服务端冒烟 169 · 启动鲁棒性 43 · 客户端端到端 165 · API 校验 0 问题（1,742 个属性键）· Selene 0 警告。

### 项目所有者反馈（实机截图）
菜单不够简洁（左侧 10 个按钮一长列，看一眼就累）；排版要精炼、可伸缩展开收回；先做新手教程让玩家快速上手；内容一目了然、按游戏进度逐步解锁；修完一系列 QoL。截图还暴露了左下角 **"No active pet"**、FIGHT 置灰——新玩家根本没法玩。

### 根因：No active pet（严重）
- PetService 在 `PlayerLoaded` 处理函数里发放初始宠，但不同步。Roblox 默认 **Deferred** 信号：首个存档快照先发出、处理函数后执行 → 客户端永远收不到初始宠。Mock 是 Immediate 语义，测试全绿却没发现。同类问题：每日任务刷新、通行证、营地离线结算（都改了数据不同步）。
- 修复：DataService **同步加载钩子**（`OnLoad`，首个快照之前按序执行）；钩子执行期间**暂停增量同步**（`Grant` 的局部同步曾可能被客户端当成完整存档）；首个快照后再**延迟补发一次**完整快照兜底。Mock 改为 Deferred 语义——CI 中先复现同样症状，再验证修复。

### HUD 重做（D-23）
- 布局（按 1280×720 设计，UIScale 0.75–1.3 适配）：左上 金币 / 钻石（"+" 展开其它货币，只列已解锁功能相关的）+ **目标栏**（教程步骤 / 下一个解锁 / 每日任务，点击直达）；右上 齿轮设置；底部 **出战宠物卡 | 功能坞 | BATTLE（显示下一关）**。
- **功能坞**：只显示已解锁功能（新玩家只有 Pets 一个图标），像素图标 + 名称，4 组（冒险 / 宠物 / 基地 / 更多）；NEW 标签与红点；可收起为 MENU 标签；打开任何界面时自动让位；窄屏（手机）放不下时自动上移一行，名称不丢。
- **渐进解锁**（`Config/Features`）：Hatch 1-1 · Codex 首次孵蛋 · Quests / Shop 1-2 · Camp 1-3 · Expedition 1-5 · Arena 1-10 · Prestige 2-10。解锁瞬间顶部横幅 + OPEN；世界里的站点未解锁时显示解锁条件。
- 14 个像素图标（Frame 绘制，零外部资源，同色横向合并）。

### 新手教程（D-24，4 步约 2-3 分钟）
选伙伴（3 张卡：3D 预览 + 元素 / 定位 / 技能 + 属性条）→ 箭头指引 BATTLE → FIGHT → 首胜解锁孵蛋 → **免费第一颗蛋（必出不同元素）** → 打赢 1-2 → 完成庆祝 +50 钻石；可跳过（无奖励）。服务端 `TutorialService` 从存档状态推导进度并发奖励（客户端无法伪造）。
- 设计修正：原计划的"用金币升级"步骤在测试中被发现——首胜的战斗经验已自动升到 2 级，且下一级 96 金币远超首战收入——改为情境提示（能升级时 Pets 图标出红点）。
- 模拟验证：3 个初始宠打 1-1 各 200/200 胜，教程第一战不会失败。

### QoL
禁用按钮一律说明原因（FIGHT：先选出战宠物 / 先通过上一关）· 关卡格子 NEW 代替 "---" · 区域页签锁图标（原文字溢出重叠）· Esc 先关最上层弹窗再关界面 · 界面窗口自动缩放适配小屏 · 世界站点标签改像素尺寸（远处也清晰）· 每日奖励改为 Quests 红点（不再进游戏就弹提示）· 离线模式提示改为普通日志（不再触发 WARN）· 测试标签 / 版本号 / 开发日志徽章重新安置（不遮挡货币与界面标题）· 吐司移到底部菜单上方 · 经验条改中性底色 · 站点等待改后台线程（世界晚到不再卡住 UI 接线）。

### 新工具：UI 预览渲染
`tools/ui_snapshot.luau` 跑完整新手流程导出界面树 → `scripts/render_ui.py` 按 Roblox 规则算布局（UDim2 / 锚点 / 列表 / 网格 / 内边距 / 嵌套 UIScale / 自动尺寸 / 裁剪 / ZIndex）并用像素字体出图（`docs/ui-preview/`）。本轮靠它发现并修复：后期左侧菜单过高遮挡宠物卡、区域页签溢出、指引气泡盖住关闭按钮、测试标签压住界面标题、手机端窗口超出屏幕、解锁横幅与庆祝弹窗重复等。模拟器同步补齐：Deferred 信号、Roblox 真实枚举默认值、扣除顶栏的 AbsoluteSize、可调视口。

### 下一步
1. 实机测试 v0.2.0（按 README 指南：新玩家流程 + 新菜单）。
2. 战斗表现层（伤害数字 / 状态图标 / 蓄力条）+ 基础音效。
3. 内容：遗物补到 35、成就、2× 金币通行证、世界 Boss。

---

## 2026-09-26 · Day 3.1 · 实机复测：加载通过 + 版本戳防"旧文件"误测

**状态**：项目所有者（借助本地另一 AI）拉取 `f6220d8` 重新构建后复测：**Studio 实机加载成功**。GitHub 与工作区一致（该次协助无代码改动）。

### 复盘
- 修复后第二次仍看到卡加载，原因不是代码：Studio 仍开着旧 place，退出时保存把旧版本写回了 `VoxelPets.rbxl`，实际测到的是修复前的构建。而新旧构建在截图里无法区分（当时没有版本标识）。

### 预防
- `src/shared/BuildInfo.luau` + `scripts/build.sh`：构建时自动写入 git 短哈希 + 日期；加载界面与游戏右下角显示 `v0.1.1 (哈希 日期)`，服务端启动日志与加载诊断同时给出客户端 / 服务端构建号；CI 改用该脚本构建。
- 实机测试指南新增"第 0 步"：先完全关闭 Studio，关闭时选择不保存。
- 客户端模拟器补齐 Folder / ModuleScript 的 FindFirstChild / WaitForChild（写版本戳测试时发现的模拟缺口）；客户端端到端 110 项。

### 下一步
1. 按 README 清单逐项体验（战斗 / 孵蛋 / 营地 / 远征 / 竞技场 …），反馈画面与手感问题。
2. P0 收口：战斗表现层（伤害数字 / 状态图标 / 蓄力条）→ 新手引导 → 基础音效。

---

## 2026-09-26 · Day 3 · 首次实机：卡在 "Loading your pets..." → 启动链路加固 + 客户端端到端模拟

**阶段**：P0 收口（Studio 实机验证）　**状态**：已修复并加固，待项目所有者再次实机确认。全部门禁绿：单元 13,092 · 服务端冒烟 152 · 启动鲁棒性 43 · 客户端端到端 108 · API 校验 0 问题 · Selene 0 警告。

### 现象
项目所有者首次在 Studio 打开 `VoxelPets.rbxl` 运行：画面一直停在 "Loading your pets..."，无任何提示。

### 根因分析（无法看到 Output 窗口，靠代码审计 + 复现）
1. **服务端 Mock 替换了 ProfileStore**：真实存档路径从未被执行过。真实 ProfileStore 在 Studio 里用"错误信息字符串匹配"判断有无 DataStore 权限；一旦匹配不上（未发布 place 的报错文案变化），store 永远不会 ready，`StartSessionAsync` 永久阻塞 → 客户端永远等不到存档。我们的代码对此**没有任何超时**。
2. **服务端启动无隔离**：任一服务模块加载时抛错会中断整个启动脚本，远程处理器全部注册不上，客户端 `InvokeServer` 永久挂起。竞技场在模块顶层调用 `MemoryStoreService:GetSortedMap`，在未发布的 place 中有此风险。
3. **客户端静默等待**：加载循环只有 `while not loaded do wait end`，失败原因对测试者完全不可见。
4. **Mock 调度器是同步的**：`task.delay` 立即执行、`task.wait` 直接报错，所有与时序相关的问题（超时、竞态、挂起）在 CI 中不可能暴露。

### 修复与加固
- **服务端启动 `Boot.luau`**：远程 → 世界 → 各服务 require → Start → Ready 每一步 xpcall 隔离；启动状态 / 当前阶段 / 错误列表写入 ReplicatedStorage 属性（`VP_ServerState / VP_BootStage / VP_BootErrors`）供客户端显示；服务缺失导致的无处理器远程统一回 "Unavailable right now"（不再让客户端挂起）。`Main.server.luau` 缩为一行，Lune 冒烟与真实服务器走同一启动路径。
- **存档 `DataService`**：三种存档模式——线上 ProfileStore；Studio 有权限时用独立的 `PlayerData_studio_v1`（不碰线上存档）；Studio 无权限 / 未发布时用**内存离线存档**（能完整游玩、不保存，HUD 顶部显示 TEST MODE）。DataStore 探测 10 s 超时、会话打开 20 s 看门狗（Studio 回退离线、线上提示"等待中"）、迟到会话自动释放（不泄漏会话锁）、同一玩家防重复加载、所有服务 Start 完成后才开始加载玩家（避免错过 PlayerLoaded）。每个玩家的加载进度写入 `VP_LoadState`。
- **竞技场**：MemoryStore 句柄惰性 + pcall 创建，不可用时回退机器人。
- **客户端**：新的加载界面 `BootScreen`（连接 → 服务端 → 存档 三步清单 + 计时 + 12 s 后显示诊断信息 + 20 s 后提示截图）；`Net.invoke` 20 s 超时永不挂死；模块加载 / 每个界面构建 / 每段 UI 接线都有隔离，坏掉的界面显示错误面板而不是整体崩溃；`Components` 属性赋值失败只告警不抛错；战斗回放与跟随宠物的每帧循环出错不再每帧刷屏。
- **屏幕开发者日志 `DevConsole`**（仅 Studio / 游戏所有者可见）：左下角 ERR/WARN 徽章，点开可看客户端错误 + 服务端转发的警告（`DevLog` 远程），**测试者一张截图就能报告问题**。

### 新的测试层（全部进 CI）
- `scripts/check_roblox_api.py` + `tools/data/roblox_api.json`：用 Roblox 官方 API Dump（0.740）校验所有属性表键名 / 枚举 / 服务名 / 可创建类（覆盖 1,391 个属性键；植入 10 类错误全部检出）。
- `tools/boot_smoke.luau`：Mock 新增**虚拟时间协程调度器**，9 个场景复现"卡加载"的各种成因（玩家早于启动加入、未发布 place、探测永不返回、会话挂起、线上慢加载、服务崩溃、MemoryStore 不可用、重复 PlayerAdded、DevLog 转发）。
- `tools/client_mock.luau` + `tools/client_smoke.luau`：**客户端运行时模拟器**——真实客户端脚本在 Lune 中运行，连到真实服务端代码；假 Instance 按 API Dump 校验成员与赋值类型，远程负载按 Roblox 序列化规则检查（混合表 / 稀疏数组 / 函数值）。覆盖启动、11 个界面、关卡战斗（跳过 + 实时回放）、孵蛋 + 概率弹窗、升级、营地、每日奖励、竞技场、商店、设置、**通过 UI 走完整局远征**、8 个界面全按钮点击模糊测试，以及"存档挂起""服务崩溃"两个失败场景下测试者看到的画面。
- 另用 luau-lsp（真实 Roblox 类型定义）做了一次全量类型扫描：新代码 0 问题。

### 下一步
1. 项目所有者重新下载 `VoxelPets.rbxl` 实机运行：应在数秒内进入游戏并看到 TEST MODE 标识；有任何问题截图（加载界面或左下角 ERR 面板）。
2. 实机通过后进入 P0 收口：战斗表现层（伤害数字 / 状态图标 / 蓄力条）、基础音效、新手引导。
3. 并行：遗物补到 35、成就、2× 金币通行证、世界 Boss（均可在新的端到端模拟中自动验证）。

---

## 2026-09-26 · Day 2.5 · 架构体检：超级文件拆分 + 鲁棒性加固

**阶段**：P2 MVP 后整理　**状态**：全部门禁绿（StyLua ✓ · Selene 0 警告 ✓ · 单元测试 13,091/0 ✓ · 服务端冒烟 151/0 ✓ · rojo build ✓）。

### 完成
- **workspace 整理**：历史 PRD 草稿（v0.1）与未选用概念图移入 `~/artifacts/`；工作区根目录只保留 repo / bundle / 可用 place / 工具链。
- **超级文件体检与拆分**（报告见 `docs/ARCHITECTURE.md`）：
  - `tools/test.luau` 746 行测试巨石 → `tools/tests/` 五个领域套件（config / combat / progression / expedition / data）+ 34 行 runner，检查项逐条原样保留；
  - 客户端 `Expedition` 561 行 → 屏幕编排 143 行 + `UI/ExpeditionView` 429 行纯渲染（act 回调注入）；
  - 客户端 `Pets` 470 行（单函数 260 行）→ 列表屏 188 行 + `Screens/PetsDetail` 319 行（五个 section 函数）。
- **鲁棒性加固**：远程入参校验纯逻辑下沉 `src/shared/Validate.luau`（NaN/inf/非整数/越界/空串/控制字符/超长全拒），`Remotes` 委派调用、13 个服务零改动；新增 16 项单测（13,075 → 13,091）。`DataTemplate` 注明 `expedition.lastSummary` 语义字段。
- **require 约定统一**：客户端 6 处内联 `require(ReplicatedStorage.Shared.X)` 统一为 `Shared` 局部变量约定；修掉 HUD 函数内懒 require（模块顶部一次加载）。
- 新增 `docs/ARCHITECTURE.md`（分层规则 / require 约定 / 规模红线 D-19 / 鲁棒性约定 / 体检结果表）。

### 问题 / 风险
- 快照环境会丢可执行位与 `.git/config`（本轮又踩两次：`bin/*`、`install_tools.sh`）；推送改用显式 URL + 全局 credential helper 绕过。
- 其余风险同 Day 2：待 Studio 实机验证（清单见 README）。

### 下一步
1. Studio 实机：逐项过 README 验证清单，修 UI / 运行时问题。
2. 表现层补齐：伤害数字 / 状态图标 / 蓄力条、音效、站点模型替换灰盒。
3. 第二轮平衡：重点 2 区 5–10 关、3 区 6–10 关的等级跳变。
4. 埋点 / 反作弊 / 远程配置（P2 剩余项）。

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

## 2026-09-26 · Day 5 · 美术方向：像素暖木 UI + 竖屏适配 + 更大更简的主界面

**阶段**：打磨　**状态**：已交付 v0.3.0

### 完成
- **主题重制（PixelTheme）**：从冷蓝暗色换成"暖阳体素"暖色系——深棕底 `#2A1F14`、木纹面板 `#7A4E2A`、羊皮纸 `#F0DCAE`、金色描边 `#E8B95A`、强调橙金 `#F2B5A` → `#F2B544`。所有界面同 key 换色，一次性全部换肤。受星露谷物语启发但配色与结构均为原创（不复制素材）。
- **组件质感（Components）**：所有面板 / 按钮 / 进度条加 2px 像素斜面（上左亮、下右暗）；按钮按下变暗；进度条加高光与 8 段刻度；面板标题栏改为木色 + 金色饰条。
- **每扇窗口有关闭键（ScreenManager）**：偏移尺寸的窗口右上角自动加 X（手机没有 Esc 键）；开窗弹入动画（Back 缓动 0.16s）。
- **关卡选择重排（Stages）**：改为流式布局（自适应 880×560 上限）：区域标签 → 关卡格子（可滚动换行）→ 羊皮纸情报卡（敌人属性 / 技能 / 奖励 / 元素克制提示）→ 全宽 54px 大 FIGHT 键。文字直接保持原字号（不靠缩放），手机竖屏上依然清晰。
- **孵蛋屋重排（Hatch）**：蛋卡从固定一行改为网格换行（桌面 4 列 / 竖屏 2×2）+ 滚动。
- **竖屏适配（HUD）**：`rescale()` 按横竖屏选择设计画布（540×960 / 1280×720）；竖屏时目标栏拉通全宽、功能坞拆成两行居中、伙伴条 + BATTLE 并排升到坞上方；横屏手机上功能坞过宽时自动上移一行（既有逻辑保留）。所有 HUD 模块新增 `relayout()`，方向切换实时重排。
- **预览管线扩展**：ui_snapshot 增加 390×844 竖屏快照（HUD / 关卡 / 孵蛋）；新增 `scripts/make_overview.py` 一键生成带中文说明的总览图。

### 问题 / 风险
- 其余固定 860px 宽的界面（Pets / Quests / Shop / Camp / Expedition / Arena / Codex / Prestige）在竖屏上仍靠 FitScale 缩放（小屏字号偏小），下一批逐个改流式布局。
- 渲染器不画 3D 与图片素材，真实观感仍以 Studio 实机为准。

### 下一步
- 剩余界面流式化（优先 Pets / Quests / Shop）。
- 竖屏下战斗界面（Battle）的布局复核。
- 3D 侧美术：宠物模型从 32 体素精度起步的视觉打磨。

## 2026-09-26 · Day 6 · 战斗风格改造第一期：斗蛐蛐式"体素对撞" + 项目地图

**阶段**：打磨　**状态**：已交付 v0.4.0

### 完成
- **新战斗舞台（BattleFx + BattleStage 重写）**：横版侧面视角的"体素对撞竞技场"——沙色平台、金色中线、队伍色端区、木柱角灯、背景墙 + 金饰条，全部沿用暖木 UI 配色。入场时双方从两端滑入 + 中央 VS 演出。
- **对撞战斗**：普攻 = 冲刺贴脸 → 接触点方块迸溅 → 对方被击退滑回；技能 = 先手元素色蓄能特效 → 腾跃空翻砸落 → 冲击波环 + 大震屏 + FOV 变焦。MISS = 侧身闪避；复活 = 跃起 + 金色迸发；战斗结束 = 胜者跳跃庆祝 + 双色纸屑。
- **KO 时刻**：0.55 秒慢动作 + 镜头大震 + 败方**逐部件碎成方块**四散坠落——体素模型的天然优势。
- **头顶名牌**：每只灵宠头顶常驻 名字 + 血条 + 护盾条（与 UI 面板双保险）。
- **音效 0→1**：6 种 Roblox 内置音频（打击/重击/腾跃/落地/暴击 ping/KO），随机音高防机械感；mock 加 Sound 空实现。内置路径个别环境可能缺失 → 实机听不到再换。
- **工程**：BattleStage 803 行超 700 拆分红线 → 拆出 `World/BattleFx.luau`（舞台/特效/音效/名牌）+ `BattleStage.luau`（播放控制器 535 行）；自研逐帧移动调度器（smoothstep + 抛物线弧 + 旋转，可中断重定向），不依赖 Tween 的 CFrame 支持。
- **项目地图**：新增 `docs/PROJECT_MAP.md`（系统完成度/里程碑/行动清单 v2），此后每次交付更新。

### 问题与教训
- **ensureStage 递归栈溢出**：顶层 `slab()` 内部又调 `ensureStage()`，而舞台正在建造中找不到自己 → 无限递归。修复：slab 改为 ensureStage 内部闭包，直接父到正在建造的 folder。
- **step() 会把播放错误吞成 toast**（"replay failed to load"），冒烟测试只报"battle plays"失败不给原因 → 临时 wrapper 包装 `BattleStage.play` 打印真实错误，30 秒定位。（临时调试脚本已删。）

### 下一步
见 `docs/PROJECT_MAP.md` 行动清单 v2：P0 = 战斗二期（元素专属特效/蓄力条/遗物横幅）+ 远征肉鸽深化（遗物 35 + 周种子）+ 音频全面化。

---

<!-- 模板
## YYYY-MM-DD · Day N · <阶段>
**阶段**：　**状态**：
### 完成
### 问题 / 风险
### 下一步
-->
