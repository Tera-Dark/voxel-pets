# 数值平衡记录（BALANCE）

> 工具：`lune run tools/sim_batch`（快照）、`lune run tools/sim_replay -- <A> <B> <seed> [relics]`（单场日志）、`lune run tools/tune_roles`（职业模板网格搜索）、`lune run tools/pve_curve`（每关最低可过等级）、`lune run tools/economy_model`（经济模型）。
> 所有战斗由 `src/shared/Combat/Simulator.luau` 确定性模拟，同一 seed 结果完全一致，因此下面的数字可复现。

## 方法

- **镜像胜率**是最敏感的量尺：在低方差的自动战斗里，任何稳定的 +10% 优势都会被放大成 80%+ 的胜率。因此不要追求"每个遗物都 55%"，而是看**相对排序**与**情境价值**。
- **职业平衡在"元素中和"下测**（`elementOverride = "Neutral"`），否则元素三角会掩盖职业强弱。
- 设计目标（P0）：
  - 元素中和下三职业互相胜率落在 **38–62%** 区间（温和三角：坦克 ≥ 攻击 ≥ 辅助 ≥ 坦克）。
  - 单场时长：普通 15–30 s；任何对局在 **25 s 后进入"狂暴"**（每 5 s 全场伤害 +25%），杜绝拖到超时。
  - 第一区：Lv = 关卡数 的初始灵宠在第 10 关胜率 ~50–65%（需要多练 1–2 级或靠遗物）。
  - 精英（Thornback Boar）：克制方同级可打；中立方需 +3~4 级或 2 个普通遗物；被克方应绕路。

## 2026-09-25 调参日志

| # | 现象 | 调整 | 结果 |
|---|---|---|---|
| 1 | 元素 1.5 / 0.67 + ±5% 方差 → 所有对位 100%/0%，遗物无法体现 | 元素改为 **1.3 / 0.77**，伤害方差 ±15%，暴击 1.75× | 被克对局仍 ~0%，但 Element Ward 可拉到 30%，Inversion Prism 反转 |
| 2 | 坦克镜像 104 s 超时 | 加入 **狂暴**（25 s 起每 5 s +25%）；下调护盾 20%→15%、回血 15%→10%、Regen 3%→2%/s | 坦克镜像 ~50 s，其余 ≤ 45 s |
| 3 | 打断后精英立刻再蓄力 | 被打断技能进入完整冷却 | Insight Lens 对精英从无效变为决定性 |
| 4 | 野怪太弱（第 10 关仍 100%） | `WILD_STAT_MULT = 1.4` | 第 10 关同级胜率 52–63% |
| 5 | `SturdyBlock`(+15% HP) 无效 | Builder 中 hp 乘区应作用于 maxHp（bug） | 修复后 90% |
| 6 | DEF 几乎无价值（+20% DEF 仅 60%） | 减伤公式 `DEF/(DEF + K×攻方ATK)` 的 K 由 2.5 → **1.5**；Iron Hide +25% | 67.5% |
| 7 | **元素中和下 攻击 > 坦克 > 辅助 均 100%**（被元素三角掩盖的真问题） | `tools/tune_roles` 网格搜索 216 组模板 | 攻击 320/20/8，坦克 440/16/12，辅助 380/18/11 → 51% / 58% / 38.5% |
| 8 | 狂暴提前到 20 s 后攻击 vs 坦克跳到 76% | 回退到 25 s | 说明狂暴时间是强敏感参数，改动需重跑快照 |
| 9 | 精英对中立方 0%，+4 级也 0% | `ELITE_STAT_MULT` 1.2 → 1.0，精英改用 HP 覆盖（380） | 中立方 Lv14 90%、两件普通遗物 55%；被克方仍 0%（设计上应绕路） |

## 2026-09-26 · PvE 曲线与经济模型

### 公式（当前实现，`src/shared/Config/{Formulas,Stages,Eggs,Camp}.luau`、`Progression/PetInstance.luau`）

| 项 | 公式 |
|---|---|
| 最终属性 | 基础 × 稀有度乘数（C1 / U1.5 / R2.5 / E4.5 / L8 / M15 / S30）× (1 + 0.05(L−1)) × 进化{1, 1.6, 2.5} × (1 + 0.2(星−1)) × 形态（金 1.5 / 彩虹 2.5 / 暗物质 5） |
| 战力 | HP/10 + 2·ATK + 1.5·DEF + 0.5·SPD |
| 敌人缩放 | 1.4 × 2.0^(区−1) × 1.10^(关−1)，Boss 再 ×1.15；敌人等级 = (区−1)×10 + 关 |
| 关卡奖励 | 金币 35 × 2.5^(区−1) × 1.12^(关−1)；经验 40 × 2^(区−1) × 1.1^(关−1)；首通 +钻石 |
| 升级费 | 20 · L^1.6 · √稀有度乘数（金币）；升级经验 30 · L^1.7 |
| 营地 | 矿场 0.05 × 战力^0.6 币/s（亲和元素 ×1.25，建筑等级每级 +15%）；果园 0.03 × 战力^0.6 经验/s；哨站 0.25 门票/工人/h（上限 5）；离线上限 8 h（VIP 12 h） |
| 蛋价 | Meadow 500 币 / Forest 2,500 币 / Volcano 25,000 币 / Premium 250 钻 |

### PvE 曲线（`pve_curve --n=20`，稀有 Rare 起始宠、无遗物、元素中立方 vs 最优方）

每关达到 ≥ 50% 胜率所需的最低等级；`neutral` = 元素中立的起始宠，`best` = 三只起始宠中最优的一只。工具假设：星级 = 区号（1 / 2 / 3 星），进化随等级上限自动发生（Lv>30 二阶 ×1.6，Lv>60 三阶 ×2.5）。

| 关 | 敌人 | neutral | best |  | 关 | 敌人 | neutral | best |  | 关 | 敌人 | neutral | best |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1-1..1-6 | 野怪 / 精英 | 1 | 1 |  | 2-1 | ThornvineWolf | 9 | 4 |  | 3-1..3-3 | 野怪 | 31 | 31 |
| 1-7 | Hopcube | 4 | 4 |  | 2-2 | Gloomcap | 12 | 11 |  | 3-4 | MagmaSlug | 37 | 31 |
| 1-8 | EmberBeetle | 7 | 2 |  | 2-3 | BrambleBeetle | 17 | 10 |  | 3-5 | BlazeBoar（精英） | 43 | 31 |
| 1-9 | PuddleSnail | 11 | 5 |  | 2-4 | Nightmoth | 19 | 18 |  | 3-6 | SlagTortoise | 53 | 41 |
| 1-10 | OakheartGolem（Boss） | **16** | 10 |  | 2-5 | ShadowStag（精英） | 28 | 27 |  | 3-7 | Ashwing | 58 | 44 |
|  |  |  |  |  | 2-6..2-10 | 野怪 / Boss | **31** | 31 |  | 3-8 | MagmaSlug | 61 | 56 |
|  |  |  |  |  |  |  |  |  |  | 3-9 / 3-10 | CinderPup / FurnaceTitan（Boss） | **61**（二次进化） | 61 |

读法与结论：
- 1 区曲线平滑（1 → 16 级），Boss 需要在 1-9 基础上再练 5 级或换克制宠，符合"首个卡点"设计。
- 2 区从 2-5 精英起需求跳到 28 → 31 后**平台化**（2-6 到 2-10 都是 31），对应 Lv30 等级上限后的第一次进化（×1.6）把整段拉平——这是养成的"台阶感"，可接受。
- 3 区前三关同样被进化台阶压平在 31，但 3-6 起每关 +5~10 级，**偏陡**；候选调整：3 区 `1.10^(关−1)` → `1.08`，或把第二次进化门槛前移。留给实机数据决定。
- `best` 列比 `neutral` 低 5~15 级 → 元素克制仍是最便宜的解，配合图鉴多养几只是设计意图（1v1 下的"换宠"决策发生在战前）。

### 经济模型（`economy_model`）

假设：单宠通关该区所需总金币 = 升级到该区 Boss 所需等级的累计升级费 + 1 次进化费；活跃收入 = 反复打该区最高已通关卡（含 3 星）；挂机收入 = 矿场满工人（1 / 2 / 3 个）以对应战力挂机。

| 区 | 所需金币 | 战斗收入 /h | 矿场收入 /h（工人数） | 活跃时长 | 挂机时长（8 h 上限 → 一晚） |
|---|---|---|---|---|---|
| 1 | 17.8 K | 7.2 K | 7.1 K (1) | **1.2 h** | 2.5 h |
| 2 | 86.4 K | 18.1 K | 36.9 K (2) | **1.6 h** | 2.3 h |
| 3 | 420 K | 45.3 K | 173.5 K (3) | **1.9 h** | 2.4 h |

目标是"每区 1.5–2 h 活跃或一晚挂机"，当前基本达标；2、3 区矿场收入超过战斗收入，是刻意的（放置玩法要有存在感），但上线后要盯 3 区是否变成"只挂不打"。蛋价按 0.03 × 该区所需金币定（500 / 2,500 / 25,000），即"每 30 关金币买 1 颗蛋"的节奏。

### 本轮调整记录

| # | 现象 | 调整 | 结果 |
|---|---|---|---|
| 10 | 1 区通关需 40 K 金币、活跃 3 h+，过长 | `Stages.COIN_BASE` 25 → **35**，`XP_BASE` 30 → **40**，升级费系数 25 → **20** | 1 区 1.2 h |
| 11 | 果园经验过高导致挂机 1 晚直接跳过 2 区 | 果园系数 0.05 → **0.03** | 挂机 1 晚 ≈ 半个区 |
| 12 | 冒烟测试偶发失败（Lv20 起始宠打不过 1 区 Boss） | 非 bug：曲线显示 Boss 需 Lv16 + 方差；冒烟用 Lv24 并固定随机种子 | 三次连跑 151/151 |

## 已知待办

- 3 区 3-6 起等级需求每关 +5~10，偏陡（见上表）；候选 `1.10^(关−1)` → `1.08`。
- BALANCE 顶部"P0 设计目标"中的"第 10 关 ~50–65%"是 Lv=关卡数的旧口径；新口径见 PvE 曲线表（1-10 需 Lv16 中立 / Lv10 最优）。
- 局外成长 +25%（Lv15 vs Lv10）= 100% 胜率：低方差系统的固有特性，对 PvE 可接受；PvP 标准化模式需另行评估方差来源。
- 坦克 vs 辅助 ~45 s 仍偏长；候选：狂暴步长改为 +30%，或辅助 Regen 持续 4 s → 3 s。
- 遗物价值分层：普通属性遗物在镜像中 84–91%（Time Hourglass 95%），Rare 的 Ember Heart / Vampiric Fang 60–70%，需在 Rogue 整局层面（多场连续战斗）而非单场评估。
- 被克 1v1 仍接近必败：验证 Rogue 节点"元素预告 + 绕路"是否足够，否则考虑 D-12（战前后备换人）。

## 最新快照（N=1000，2026-09-25）

```
== Starter triangle, Lv10, no relics (row = A win% vs column, N=1000)
             Emberfox   Tidefrog   Mossback   avg duration
Emberfox        52.0%       0.0%     100.0%   13s / 23s / 15s
Tidefrog       100.0%      49.9%       0.0%   23s / 52s / 37s
Mossback         0.0%     100.0%      50.7%   15s / 37s / 39s

== Role balance, elements neutralized (all forced Neutral), Lv10
             Emberfox   Tidefrog   Mossback   avg duration
Emberfox*       52.0%      51.0%      58.0%   13s / 27s / 21s
Tidefrog*       49.0%      49.9%      38.5%   27s / 52s / 45s
Mossback*       42.0%      61.5%      50.7%   21s / 45s / 39s

== Zone 1 progression: starter at Lv=stage vs wild pool at that stage (win%, avg s)
stage:        1        3        5        7        10
Emberfox   100%/ 7s 100%/ 9s 100%/11s  99%/13s  63%/15s
Tidefrog   100%/19s 100%/22s 100%/26s  88%/30s  53%/32s
Mossback   100%/14s 100%/16s 100%/19s  98%/23s  52%/26s

== Elite check: starter Lv10 vs Thornback Boar (zone1 stage10), with/without Insight Lens
Emberfox   no relic  99.6% (14s)   +InsightLens 100.0% (12s)
Tidefrog   no relic   0.0% (22s)   +InsightLens   0.0% (27s)
Mossback   no relic   0.0% (24s)   +InsightLens   1.0% (25s)

== Relic impact: Emberfox (disadvantaged) vs Tidefrog, Lv10 mirror stats
(none)                                     0.0%  (23s)
ElementWard                                1.0%  (25s)
InversionPrism                           100.0%  (22s)
VampiricFang                               0.0%  (23s)
EchoWhistle                                0.0%  (23s)
EmberHeart                                 0.0%  (23s)
Whetstone+SturdyBlock                      0.8%  (26s)
TimeHourglass+EchoWhistle+EmberHeart       0.0%  (23s)

== Relic marginal value: Emberfox mirror Lv10, A holds one relic (baseline ~50%)
EchoWhistle       85.1%  (13s)
ElementWard       52.0%  (13s)
EmberHeart        69.6%  (13s)
FrostCharm        85.1%  (14s)
GreedyBox         32.1%  (13s)
InsightLens       52.0%  (13s)
InversionPrism    52.0%  (13s)
IronHide          67.5%  (14s)
LuckyCube         69.1%  (13s)
QuickPaws         83.9%  (13s)
SturdyBlock       90.7%  (14s)
SymbioticVine     52.0%  (13s)
TimeHourglass     94.6%  (11s)
VampiricFang      60.2%  (14s)
Whetstone         86.3%  (12s)

== Out-of-run progression: Emberfox vs Emberfox mirror, A upgraded
Lv10 vs Lv10      52.0%  (13s)
Lv15 vs Lv10     100.0%  (11s)
2 stars          100.0%  (11s)
Golden           100.0%  (8s)
Evolution 2      100.0%  (7s)

(27.0s total)
```
