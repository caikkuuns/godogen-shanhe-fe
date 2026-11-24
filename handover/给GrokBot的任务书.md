# 给 Grok Bot 的任务书 · 山河剑行

> 写给：Grok Bot
> 出：萧炎（团队 Lead）
> 日期：2026-11-25

---

## 一、现状

**仓库**：https://github.com/caikkuuns/godogen-shanhe-fe
**默认分支**：`master`
**内容**：428 个文件 / 107.6 MB，含全部源码、场景、着色器、6 个角色 GLB（原版 + opt 版）、字体、图标

**已排除、不要找**：`incoming/`、`captures/`、`docs/ref-characters*`、`generated/`、`backups/`

---

## 二、分支规矩

- `master` 是主线，**不要直接推 master**
- 你的改动推到 `grokbot/main` 或按主题开分支（`grokbot/fix-p0-texture` 这种）
- 推完开 PR，写清楚改了什么、为什么、怎么验证的
- 合并由萧炎这边裁决

---

## 三、这轮要你做的事（按优先级）

### P0-1 · 修白袍贴图破碎
**现象**：沈砚全身白袍出现大面积灰黑碎三角斑块，肩、袖、裙摆最重。
**怀疑**：UV 岛重叠，或贴图导出损坏。
**涉及文件**：`assets/glb/opt/shenyan_hero.glb`（当前在用的）、`assets/glb/shenyan.glb`（原版，**不要动**）
**要求**：改之前先备份；改完给出「三角形数 / 文件大小 / 骨骼数」改前改后对比。

### P0-2 · 修面部贴图错位
**现象**：近景脸部有一条白色横条横跨眼睛和额头，五官被切段；发髻上有白色碎块。
**怀疑**：脸部 UV 接缝穿过五官区域。
**要求**：修完必须出近景截图证明。

### P1-3 · 冷色饰边调暖（根因已定位）
GLB 里 17 个材质全是纯色、没有一张贴图。裤脚那片「蓝紫脏斑」不是脏，是冷色饰边被 toon 渲染压暗：
- `trim_ice` `#658CC2` → `#9FB6CE`（或银灰 `#B8BCC4`）
- `sash_tail0/1/2` 垂带剪短到 Y 0.8 以上
- `boot_grey` 当前 R<G<B 偏蓝 → 中性灰 `#3A3A3A`

### 硬指标 · walk 8 帧截图
**必须**产出 `captures/kimi_walk_00.png` ~ `kimi_walk_07.png`，命名一字不差。
采样方法（验收员验证过的，直接照做）：
- 不要通过 `CharacterAnim` / `AnimationTree` / `FootLock` 驱动（会把脚钉死）
- 直接用 `AnimationPlayer.play("walk")` + `advance(t)` + **等 2 帧渲染刷新**再截图
- walk 动画时长 1.375s，8 帧间隔约 0.172s

### 硬约束（不能破）
- 骨骼 17~21 根（当前 19）
- 保留 `idle` 和 `walk` 动画
- 身高 1.70 m
- 脚底 y ≈ 0
- 不删 `assets/glb/shenyan.glb` 原版
- 现有 `scripts/world/character_model.gd` 结构：近景走 `opt/shenyan_hero.glb`、战斗走旧 `shenyan.glb`，保持不变

---

## 四、交班怎么交（硬要求）

**每次改完，在 `handover/` 目录写一篇** `交接-YYYYMMDD-grokbot-主题.md`，必须包含：

1. **改了什么** — 文件路径 + 行号 + 具体改动（`旧值` → `新值`）
2. **为什么改** — 对应上面哪条 P0/P1
3. **怎么验证的** — 跑了什么、数字是多少、截图路径
4. **模型数据对比** — 三角形数 / 文件大小 / 骨骼数，改前 vs 改后
5. **下一步** — 还有什么没做、有什么风险、回滚点在哪

模板见 `handover/交接说明模板.md`。同时在 PR 描述里写同样的内容。

---

## 五、不要碰的东西

- `assets/glb/shenyan.glb` 原版（要备份，不要覆盖）
- 服务器密码、令牌、内网 IP
- `master` 分支（走 PR）

---

## 六、背景数据（已查实，不用重查）

| 项 | 值 |
|---|---|
| `assets/glb/shenyan.glb` | 19,681 面 / 19 骨 / 3 网格 / 5 贴图 / 动画 attack·down·hit·idle·walk |
| `assets/glb/opt/shenyan.glb` | 8,795 面 / 19 骨 / 3 网格 / 5 贴图 / 同 5 动画 |
| `assets/glb/shenyan_script.glb` | 14,928 面 / 17 骨 / 84 网格 / **0 贴图**（17 个纯色材质）/ 仅 idle·walk |
| HTML 参考 | 角色约 7 头身，袍子实际 `#E8DFCB` 暖白（不是蓝，蓝的是腰带 `#1A2F61`） |
| 出包环境 | Godot 导出模板 android_debug/android_release、Android SDK 35/36、JDK 17、debug.keystore 都在 |

---

## 七、有疑问

在 `handover/` 写一篇 `问题-YYYYMMDD-主题.md`，卡在哪写清楚，萧炎回你。
