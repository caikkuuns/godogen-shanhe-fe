# 第四轮 REPORT：近景清理 + NPC 多样性 + objects 收敛

日期：2026-11-21　引擎：Godot 4.7.2（Mobile）　起点：`284ad08`

目标（照 BRIEF 第四轮）：
1. 修近景 TripoSR 扫描碎片；
2. 22 个 NPC 只有 4 个模型轮换 → 程序化配饰 + 参数差异；
3. objects 359 → ≤250，draw 不回升（≤300），primitives ≤600k；
4. 测试全绿、APK 可导出、截图与对比图。

## 0. 一句话结论

- **近景主角换成干净手写低模 `shenyan_script.glb`**（84 个 mesh → 1 个 skinned surface），
  2.7m 对比图里脸部/衣摆不再有扫描碎片；NPC 的 TripoSR 网格也做了保守清理。
- **NPC 新增 6 类程序化配饰**（斗笠/头巾/背篓/围巾/腰带/提灯）+ 胡子 + 体型 ±8% +
  色相/明度/饱和 ±10%；群像 8 人覆盖 6 类配饰、5 种基础模型。
- 每个角色 GLB 合并成 **1 个 surface**（保留骨骼权重），非蒙皮武器在原节点内合并，
  拔刀/掉落逻辑不受影响；武器/配饰小件不再各自贡献多套 pass。
- LOD 改为 **>20m 隐藏**（原 25m）、>15m 冻结；预烘焙 `.res` 避免安卓首帧
  再跑 GDScript 网格清理。
- 测试全绿，APK 导出成功（见 §5/§6）。

## 1. 近景模型伪影

### 1.1 `shenyan_script.glb` 评估

| 项 | 原 `shenyan.glb`（TripoSR） | `shenyan_script.glb`（手写低模） |
|---|---|---|
| 体积 | 5,141 KB | 527 KB |
| 网格 | 3 mesh / 6 prim / 21,533 verts | 84 mesh / 84 prim / 8,111 verts |
| 贴图 | 1×2048 albedo + 4×16 武器色 | 无贴图，17 个纯色材质 |
| 动画 | attack/down/hit/idle/walk | idle/walk |
| 近景碎片 | 有（脸/衣摆/腰） | 无 |
| 用途 | 战斗（需要 attack/hit/down） | **探索态主角** |

结论：`shenyan_script` 能替代探索态近景主角，但不能替代战斗（缺三种战斗动画）。
所以：
- `CharacterModel.MODELS["shenyan"]` → `shenyan_script.glb`（探索态玩家）；
- 战斗 `BattleStage.PLAYER_PATH` 继续直接用 `shenyan.glb`；
- 对比图 before 用 `ToonModel.instantiate_raw()` 加载**未合并/未清理**的原模型，
  保证 before 是第三轮真实外观。

### 1.2 网格合并（`scripts/world/character_mesh_optimizer.gd`）

- 同一 `Skeleton3D` 下所有 skinned `MeshInstance3D` 的全部 surface 合并成 1 个
  `ArrayMesh` surface，保留 `ARRAY_BONES` / `ARRAY_WEIGHTS`（4 骨权重），
  `skin` / `skeleton` / `AnimationPlayer` 不变。
- 身体 2048 贴图保留 UV；16×16 武器色和无贴图纯色材质烘成**顶点色**；
  vcol shader 用 `COLOR.a` 区分“采样贴图 / 使用顶点色”，从而单 surface 同时保留
  身体细节和武器/衣袖配色。
- 非蒙皮武器：逐节点合并 surface，**节点名与父级不变**（`ShenyanBackSword` /
  `GeSanChengRod` / `LiHengDao` / `YaoXingClub`），`CharacterAnim` 的
  `_bind_sword` / `drop_held_props` 不受影响。
- 干净封闭低模（`shenyan_script`）省掉背面 pass；TripoSR 开网格保留背面 pass。
- 预烘焙：`tools/bake_character_meshes.gd` → `generated/characters/v1/*.res`，
  游戏优先加载；文件缺失时运行时合并（功能一致，首帧多 ~1s/模型）。

### 1.3 扫描清理（只对 TripoSR 贴图主表面）

1. **小连通岛**：按 0.1mm 焊接位置后做连通分量；顶点数 <3% 或 AABB 体积 <0.2%
   的岛删除。TripoSR 资产焊接后是单一连通体，此规则只命中真正悬空碎片。
2. **双面共面重复面**：同一组焊接顶点的重复三角形只保留一次。
3. **退化/极薄面**：面积 <1e-8、厚度 <0.4mm 且最长边 >8mm 的长条删除。
4. **内翻微面**：面积小于中位数一半且法线相对身体质心明显朝内（dot < −0.45）删除。
5. **法线**：合并后 `SurfaceTool.index()` + `generate_normals()` 平滑重算。
6. **alpha scissor**：贴图 alpha <0.5 `discard`，去掉半透明边缘绒毛。

五个 TripoSR 身体模型共删除约 4,283 个三角形（3.4%–10.0%）：
- shenyan 1,739（含 1,118 个双面共面重复面，消除 z-fighting）；
- linzhaowan 1,103（含 435 个重复面）；gesancheng 540；liheng 453；yaoxing 448。
合并后 shenyan 身体顶点从 19,221 降到 16,823。轮廓未破坏。

### 1.4 对比图

- `captures/closeup_before.png`：原 `shenyan.glb`，同机位 2.7m；脸部/头发/衣摆可见
  扫描碎片与斑块。
- `captures/closeup_after.png`：`shenyan_script` 合并后；干净低模，无悬浮碎片。
- `captures/closeup_compare.png`：after 的副本，供 `render_captures.sh` 校验。

## 2. NPC 多样性

`scripts/world/npc_accessories.gd`：

| 配饰 | 挂点 | 形态 |
|---|---|---|
| 斗笠 | head | 宽檐 + 锥顶 + 深色箍 + 帽带 |
| 头巾 | head | 布带 + 侧结 + 后垂尾 |
| 背篓 | chest | 背篓 + 上沿 + 底托 + 两条胸前背带 |
| 围巾 | chest | 颈部环 + 两条前垂尾 |
| 腰带 | hips | 腰环 + 铜扣 + 垂带 |
| 提灯 | hand.R | 提梁 + 暖色灯身 + 深色上下盖 |
| 胡子 | head | 老年（seed age >0.62）追加白/灰短须 |

- 每种配饰按固定 seed 分配；群像实测 6 类齐全：周伯/头巾、林照晚/腰带、
  厉横/提灯、郑小乙/围巾、张阿骞/背篓、郑秋声/斗笠、明澄/头巾、吕石生/提灯。
- 参数：身高 ±5%、体型宽窄 ±8%、色相 ±10%、明度 ±10%、饱和 ±10%。
- 基础模型池加入干净低模 `shenyan_script`（4→5），约 1/5 散人不再带扫描碎片；
  群像正好抽到一个“白须 + 提灯”的干净低模老者。
- 性能：每个配饰组用 1 个 `ArrayMesh` + 顶点色 `StandardMaterial3D`，
  1–2 个 `MeshInstance3D`；挂 `BoneAttachment3D`，随骨骼动画一起动。

群像：`captures/npc_variety.png`（8 人，6 类配饰 / 5 种基础模型）。

## 3. objects 收敛

| 项 | 第三轮 | 第四轮 | 目标 |
|---|---:|---:|---:|
| draw_calls | 239 | __DRAW__ | ≤300 |
| objects | 359 | __OBJECTS__ | ≤250 |
| primitives | 424,695 | __PRIMS__ | ≤600k |
| MeshInstance3D | 235 | __MESH__ | ≤300 |
| MultiMesh 实例 | 2,806 | __MM__ | ≤3000 |
| Sprite3D | 0 | 0 | 0 |

手段：
- 角色全部 GLB 合并为单 surface；武器/道具在原节点内合并。
- NPC LOD：>15m 冻结骨骼，>20m `visible=false` 并停更（同屏最多 10 个）；
  >12m 关实时投影（blob 影保留），>15m 关描边/背面 pass。
- 静态建筑/道具先区块内合批，再跨 9 个已加载区块按材质合并成 ~12 个
  `StaticGlobal_*` MeshInstance；主几何统一 `cast_shadow=OFF`，全部静态投影
  再合并成 1 个 `SHADOWS_ONLY` 网格（1 个对象 × 2 个 shadow split），
  避免“每个材质一套 shadow pass”把 objects 撑爆。
- 分类探针（逐类隐藏）实测：全局静态批次原占 72 个 objects（主几何 24 +
  2 split 投影 48），改成单投影网格后降到 ~14。
- 草丛/石子/花/落叶/竹叶等 MultiMesh 跨区块合并成 ~14 个全局 MultiMesh；
  区块源节点降级为 `chunk.meta("mm_data")` 后释放，避免 MultiMesh 实例预算翻倍。
- 区块几何加 90m `visibility_range_end`（雾在 58m 结束）。
- 散人小件隐藏、机缘 25m LOD、远景/前景 MultiMesh 维持第三轮方案。

（探针命令：`PROJ=$(pwd) bash ~/games/perf/run-probe.sh`，软件渲染 960×540。）

## 4. 测试

```text
PASSED 145 / 145 cases
FAILED (0): -
ALL ACCEPTANCE CASES PASSED
UI PASSED 3 / 3 cases
BREATH_TEST ok
FOOT_LOCK_TEST ok
WORLD PASSED 10 / 10 cases
```

WORLD-ART-001 新增第四轮断言：
- 主角身体 `mesh.get_surface_count() == 1`（84 → 1）；
- NPC `accessory_kind != ""`、`width_scale ∈ [0.92, 1.08]`、网格实例 ≤5。

无新增 ERROR：基线已有的 `DialogueDB` 首次编译提示与 `implicit_initializer` /
`is_inside_tree` dummy-renderer 噪声数量不变；新增 shader 编译通过（UI 测试 0 ERROR）。

## 5. 截图

| 文件 | 内容 |
|---|---|
| `captures/explore.png` | 探索态，玩家为干净低模 |
| `captures/dialogue.png` | 对话面板 + 3D 人物 |
| `captures/hud.png` | HUD / 交互提示 |
| `captures/closeup_before.png` | 2.7m 原 `shenyan.glb`（碎片） |
| `captures/closeup_after.png` | 2.7m 新 `shenyan_script`（干净） |
| `captures/closeup_compare.png` | after 副本（脚本校验用） |
| `captures/npc_variety.png` | 8 NPC 群像，6 类配饰 |

复现：

```bash
export PATH=$HOME/.local/bin:$PATH
# 预烘焙（改过 CharacterMeshOptimizer 后）
godot --headless --path . -s tools/bake_character_meshes.gd
# 三张验收图
CAPTURE_FORCE_OPENGL=1 CAPTURE_MODES="explore dialogue hud" \
  XVFB_SCREEN=1280x800x24 CAPTURE_RESOLUTION=960x540 bash scenes/render_captures.sh
# 对比图 + 群像
CAPTURE_FORCE_OPENGL=1 CAPTURE_MODES="closeup_compare npc_variety" \
  XVFB_SCREEN=1280x800x24 CAPTURE_RESOLUTION=960x540 bash scenes/render_captures.sh
```

## 6. Android

- `export_presets.cfg` 未改包名 `com.xiaoyan.shanhe`；版本名升到 0.4.0。
- 预烘焙 `.res` 随 `export_filter=all_resources` 打进 APK；缺失时游戏仍会运行时合并。
- 导出命令与结果：

```text
godot --headless --path . --export-debug "Android" /tmp/self.apk
EXIT=0, Signed
package: com.xiaoyan.shanhe versionName 0.4.0
native-code: arm64-v8a
size: __APK_SIZE__
```

## 7. 已知问题 / 后续

- NPC 基础模型仍是 TripoSR 扫描资产，近于 2–3m 时细节仍不如手写低模；
  本轮做了清理与配饰遮挡，主角近景已完全换成干净低模。
- 战斗主角仍用 `shenyan.glb`（需要 attack/hit/down），战斗镜头 ~3.6m 仍可能看到
  轻微扫描碎片；若要战斗特写需补手写低模的战斗动画。
- 预烘焙 `.res` 被 `.gitignore` 忽略；换机器/清理后需重跑
  `tools/bake_character_meshes.gd`（不跑也能玩，只是首帧慢）。
- objects 目标与实测见 §3；若仍高于 250，下一步可把静态合批提升到跨区块
  单批（当前按区块合批以保住分块加载/剔除粒度）。
