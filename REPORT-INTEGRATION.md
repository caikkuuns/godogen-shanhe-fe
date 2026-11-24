# REPORT-INTEGRATION · 第八轮：Grok Bot 导入整合（2026-11-23）

执行者：Claude/GLM（DSH 班次）。输入：`incoming/grokbot/`（963MB / 2358 文件，fe@04e2275）。

## 一句话结论

代码保留我们主线、按「成套约束」吸收了 6 套它独有且明确更优的实现（foot_lock IK 锁步 / 流苏+剑轴 /
跪姿拔剑手感 / 战斗机位 / UI 小修 / shader 补洞肤色），美术吸收 24 个画稿素材并**接入运行时**；
测试 145/145、UI **4/4**（新增 1 例）、WORLD 10/10、BREATH ok、FOOT_LOCK ok（1→5 角色）；
顺带修复了一个让村口山门整块内容从未生成过的数据 bug（`regions.json` feature 死值）。

## 测试输出（最终）

```
PASSED 145 / 145 cases        （基线同）
UI PASSED 4 / 4 cases         （基线 3/3，新增 FE-UI-004 战报金框验收）
WORLD PASSED 10 / 10 cases
BREATH_TEST ok
FOOT_LOCK_TEST ok subjects=5  （基线 1 个角色、脚踝级；现 5 角色、鞋底级滑移 ≤1mm）
```

ERROR 行数 103（stash 基线 101）：+1 来自吸收来的 test_foot_lock 挂载时序噪音（5 角色强测试），
+1 来自 FE-UI-004 在 dummy 渲染器下的一次无害材质查询；无新增错误类别，无失败用例。

## 吸收清单（代码，全部按 conflict-decisions.md 的成套约束执行）

| 套 | 文件 | 内容 | 验证 |
|---|---|---|---|
| 锁步 | `scripts/world/foot_lock.gd` + `tests/test_foot_lock.gd`（整体吸收） | 鞋底接触点锁定 + 大小腿两骨 IK，每帧从 rest 原点重建防「滑雪板」 | FOOT_LOCK 5 角色滑移 ≤1mm；145/145 |
| 流苏/剑 | `scripts/world/tassel_hang.gd`（整体）+ `character_anim.gd`（整文件，6 处手感项）+ `sheath_follow.gd`（整体） | 三段锥形流苏带惯性滞后 J 形下垂；拔剑过肩弧线+四元数 slerp 不穿腰；入鞘手引导；实测 HILT/TIP 剑轴映射 | `tools/dump_sword.gd` 实测我们的 opt 模型：AABB `(-0.203,-0.681,-0.076)~(0.061,0.185,0.257)` 与吸收常量毫米级吻合 |
| 跪姿 | `idle_breath.gd`（混合） | 真跪姿（髋 0.74→0.44）/伸手真正够到剑柄/down 写入移到 `_process(40)`；**呼吸幅度保留我们校准**（0.012/0.030） | BREATH_TEST ok |
| 机位 | `battle_stage.gd`（仅 `_position_battle_camera`） | 3/4 后方 (2.18,1.46,2.68) fov46，角色填满画面、倒地不贴 HUD | 截图验收 |
| UI | `dialogue_panel.gd`（只换 PORTRAIT_FALLBACKS 五条 v3 路径）+ `battle_panel.gd`（`_fit_log_min_height`+空结果行隐藏+紧凑排字，**保留 UPDATE_DISABLED**）+ `tests/ui_tests.gd`（FE-UI-004） | 战报末行与「收剑」按钮不再被金框裁切 | UI 4/4 |
| shader | `toon_char.gdshader`（hole_grow+肤色细化+trim 保护）+ `toon_char_front.gdshader`（仅肤色护栏）+ `toon_model.gd`（`hole_grow_for`：shenyan=0 + BackPatch 染色） | 修额头/脸颊白带、补 TripoSR 网格洞；**保留 albedo_gain 与雾**（两处旧决策） | 145/145 + 截图 |

丢弃清单与逐文件理由见 `docs/reports/conflict-decisions.md`（27+3 个冲突文件全部裁决）。

## 吸收清单（资产，`assets/imported/` 24 文件 + INDEX.md）

- **石灯幢 r4b**（中式亭顶替换日式旧顶）：运行时 `BuildingFactory.stone_lantern` 全量换装
  （含配套投影），竖切 world_builder 的 PROPS 也同步。
- **山门分层画稿** gate_L0/L1/L2 + gate_layers.json：运行时 `BuildingFactory.mountain_gate`
  重做为三层画稿（L0 铺地平铺、L1 后柱、L2 前柱+屋顶），「山河」Label 对位画中空匾，
  柱基阻挡/门洞可走/影子实体/侧石墙/幡杆齐备。
- **民居画稿** house.png：`village_house` 外观换画稿（保留碰撞 AABB、门灯与暖光），
  一个 ~30 盒子的程序化房变成 1 张画稿 + 影子实体。
- **竹林画稿** bamboo_v3b(+shadow)：`ChunkBuilder._build_bamboo` 每丛垫 1~2 张画稿竹丛，
  2 个 MultiMesh（本体+落地影）≈ 2 个 draw call。
- **地面 tile** ground_grass_tile：`ChunkBuilder._terrain_mat` 的噪声贴图换成画稿草地 tile
  （顶点色板继续承担区域色调）。
- battle_bg / waystation / rock_v2 / ch2 立绘等：已拷入待用，未接入（见 INDEX.md 未启用原因）。

## 过程中发现并修复的两个存量 bug

1. **村口山门从未生成**：`data/regions.json` 里 gate 区块的 `feature: "shanmen"`，
   而 `chunk_builder._build_region_props` 只 dispatch `"gate"`——整块门楼 POI（含基线的
   程序化山门、灯笼、布告牌）是死内容。已把 feature 改回 `"gate"`（一次性数据修正）。
   注：farmland→"fields"、mountain_road→"stairs" 同样不匹配 dispatch，本轮未动，记为遗留。
2. **本机 headless import 被阻断**：Godot 编辑器启动时「Blender path invalid」中断
   `_update_scan_actions` 落盘，新 PNG 全部没有 .import。工程只用 glb 不用 .blend，
   在 `project.godot` 加 `filesystem/import/blender/enabled=false` 绕过（带注释，可回滚）。

## 工具吸收

`tools/`：`capture_down.gd`、`dump_sword.gd`（修了两处 4.7 的类型推断解析错误后已用于剑轴实测）、
`tools/img3d/{afternoon_p0_meshes,fix_fill_uvs,polish_round2}.py`。`godot --headless --quit` 无新增报错。

## 截图

- `captures/explore.png` — 村庄标准验收图（画稿民居+石灯幢+草地 tile）
- `captures/gate.png` — 村口画稿牌坊全景
- `captures/bamboo.png` — 竹林（画稿竹丛+听竹亭）
- `captures/compare_village_r8.png`、`captures/compare_gate_r8.png` — 吸收前/后对比

## 性能（`PROJ=$(pwd) bash ~/games/perf/run-probe.sh`）

| 场景 | draw_calls | objects | primitives | 预算 |
|---|---|---|---|---|
| battle | **173** | 297 | 620,811 | draw ≤300 ✓ / objects ≤250 ✗ / prim ≤600k ✗ |
| explore | - | 292 | - | - |
| map_open | - | 312 | - | - |

objects/primitives 略超预算。本轮新增贡献：每盏石灯 2 张画稿面片（~15 盏→30）、竹林竹丛
2 个 MultiMesh/区块、流苏结+三段（每战斗者 4 节点）。**上轮 probe 无留档数字，无法精确归因**。
削减路径（下轮可做）：石灯投影面片改共享/减半（-15 objects）、`_merge_multimeshes` 把画稿竹丛
并入全局批、流苏三段合一节+锥形网格。

## 遗留 / 待办

1. 性能削减（见上）。
2. farmland/mountain_road 的 feature 死值（fields/stairs）——解锁前先确认对应 POI builder 状态。
3. shader front-pass 的 gutter 放宽（`lum<0.88` speckle）待截图 A/B。
4. 世界竖切（world_builder.gd）里也做了同款画稿门/房/地面——运行时不走它，保留作参照实现
   与 WORLD 测试目标；下轮可评估删重。
5. `.git/objects` 有 19 个 fan-out 目录属主是 `grokbot` 账号（昨晚班次写入），xiaoyan 无法写入
   新对象，**本轮 commit 由作者修复权限后完成**：`sudo chown -R xiaoyan:xiaoyan ~/games/godogen-shanhe-fe/.git`。
6. waystation/battle_bg/rock_v2/ch2 立绘已入库待接入。
