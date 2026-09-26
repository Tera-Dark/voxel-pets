# 架构说明（ARCHITECTURE）

> 模块边界、require 约定、代码规模红线、鲁棒性约定与架构体检记录。数值设计见 `BALANCE.md`，时间线见 `DEVLOG.md`。

## 分层与依赖方向

| 层 | 职责 | 约束 |
|---|---|---|
| `src/shared` | 配表、公式、确定性模拟器、远征 Run 状态机、养成规则、图鉴、数据模板、入参校验 `Validate` | **纯 Luau**（禁止 `game` / `Instance` 等 Roblox API），Lune 直接可跑可测 |
| `src/server` | 13 个服务 + 灰盒世界 + 远程包装层 | 服务端权威；服务间只经 `Registry`；货币只经 `EconomyService`；入参只经 `Remotes`；外部 API 一律 pcall |
| `src/client` | 像素组件库、12 界面、战斗回放、体素模型 | 界面模块统一 `build(host, ctx) -> frame` / `onOpen` / `onClose` 契约（`ScreenManager`）；状态经 `State` 订阅；网络经 `Net`，绝不直接摸 Remote |
| `tools/` | 测试套件、模拟/平衡工具、Roblox API Mock、服务端冒烟 | Lune 运行；`tools/tests/` 按领域分套件 |

依赖方向：`client / server → shared`。禁止 `shared → server/client`、`server ↔ client` 直连；一切经 `Network.luau` 契约（39 个远程）。

## require 约定

1. `src/shared` 内部：字符串相对路径 `require("./X")` / `require("../Y")`（Lune 兼容；依赖 Studio 字符串 require 支持 —— Studio 验证清单第 2 条）。
2. client / server 引 shared：文件顶部 `local Shared = ReplicatedStorage.Shared`，然后 `require(Shared.…)`（禁止在函数体内懒 require）。
3. 同树兄弟 / 叔伯模块：`require(script.Parent.…)`。
4. `tools/` 引 shared：`require("../../src/shared/…")`。

## 代码规模红线（D-19）

- **单文件 ≤ 500 行**（超线即警告），**700 行强制拆分**；**单一函数 ≤ 80 行**。
- 拆分优先按职责缝：渲染 ↔ 状态 ↔ 协议；测试按领域套件。
- 豁免（有意保留，评审需说明理由）：
  - `src/server/Vendor/ProfileStore.luau`（第三方 vendored，不格式化不 lint）；
  - `src/shared/Combat/Simulator.luau` 540 行 / 24 函数 —— 单一职责的战斗内核，函数粒度小、内聚高，强行拆分只会增加跨模块跳转。

### 2026-09-26 架构体检结果

| 文件 | 原行数 | 问题 | 处置 |
|---|---|---|---|
| `tools/test.luau` | 746 | 17 个领域混在单个测试巨石里 | 拆为 `tools/tests/` 五个套件（config / combat / progression / expedition / data）+ 34 行 runner；检查项逐条原样保留 |
| `client/UI/Screens/Expedition.luau` | 561 | 5 个渲染面板 + 网络 + 模块状态耦合 | 渲染全部拆至 `client/UI/ExpeditionView.luau`（429，纯渲染 + act 回调），屏幕只剩编排（143） |
| `client/UI/Screens/Pets.luau` | 470 | `refreshDetail` 单函数 260 行 | 详情列拆至 `Screens/PetsDetail.luau`（319，5 个 section 函数 + 重命名弹窗），列表屏 188 |
| `client` 6 处 require | — | `require(ReplicatedStorage.Shared.X)` 内联与 `Shared` 局部变量两种写法混用；HUD 还有函数内懒 require | 统一为约定 2 |
| `tools/roblox_mock.luau` 430、`Expedition/Run.luau` 425、`PetService.luau` 392 | — | 接近警告线 | 暂不动（函数粒度健康），复审时优先关注 |

拆分后最大非 Vendor 文件 540 行（Simulator，豁免），其余全部 < 430 行。

## 鲁棒性约定

1. **入参三防线**（`Network/Remotes.luau`）：限流（每远程 10 s 窗口）→ `pcall` 错误隔离（统一回 `Server error`）→ `Validate.int / str / strList`：
   - `int` 拒绝 NaN / ±inf / 非整数 / 越界；
   - `str` 拒绝空串 / 超长 / 控制字符（含 NUL）；
   - `strList` 拒绝非稠密数组 / 超量 / 非法元素。
   校验是纯逻辑（`src/shared/Validate.luau`），Lune 单测 16 项；服务层继续调用 `Remotes.int/str/strList` 别名。
2. **错误语义**：handler 统一 `ok, err, payload`；已知错误用固定短语（`Bad request` / `Slow down` / `Loading`），客户端只 toast 不抛错。
3. **外部 API 降级**：MemoryStore（竞技场榜）/ MessagingService（公告）/ PolicyService（付费随机项分流）一律 pcall，失败降级为机器人榜 / 本服公告 / 保守模式。
4. **存档**：ProfileStore 会话锁 + `schemaVersion` 字段（语义变更时在 `DataService` 写迁移）；`DataTemplate` 与实际写出字段保持 DataStore-safe（值仅 string/number/bool/table、键正整数或 string），由 jsonSafe 测试兜底；`expedition.lastSummary` 为 nil 语义字段（见模板注释）。
5. **模拟器确定性**：随机只走种子化 `Rng`；时间盒 120 s + 狂暴递增，主循环受 `maxTime` 硬界；伤害事件自带 absorbed/interrupt 元数据供回放。
6. **客户端生命周期**：屏幕只 build 一次、之后 Visible 切换（无逐屏构造泄漏）；全局连接仅 HUD Toast/公告、ScreenManager Esc 三处。
