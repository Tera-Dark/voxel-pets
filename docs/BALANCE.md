# 数值平衡记录（BALANCE）

> 工具：`lune run tools/sim_batch`（快照）、`lune run tools/sim_replay -- <A> <B> <seed> [relics]`（单场日志）、`lune run tools/tune_roles`（职业模板网格搜索）。
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

## 已知待办

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
