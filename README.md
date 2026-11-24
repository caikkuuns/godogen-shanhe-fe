# 山河剑行 · Godot vertical slice

Godot 4.7.2 / GDScript / Mobile renderer，横屏 1920×1080（20:9 时 canvas_items + expand 扩到约 2400）。

## 已建成

- 主场景 `scenes/main.tscn` → `scenes/world/explore.tscn`：程序化村落、山门、竹林、溪流、雾与远山；倾斜跟随相机。
- 探索：键盘/虚拟摇杆移动、碰撞、NPC 靠近提示、E/主键触发 `scripts/dialogue` 对话。
- HUD：SafeArea、气血/内力状态、任务提示、右上菜单、右下主键、技能键；对话面板含打字机、选项与双立绘。
- **人物全部为 3D 卡通模型**（第三轮起）：沈砚与全部 NPC 用 `assets/glb/*.glb` + toon 材质 + `ink_hull` 反向外壳描边；idle/walk 循环，移动时按速度方向平滑转 Y 轴（不做 8 向贴图/镜像）。
  - 第四轮近景主角换成手写低模 `shenyan_script.glb`（无 TripoSR 扫描碎片）；战斗仍用带 attack/down/hit 的 `shenyan.glb`。
  - `CharacterMeshOptimizer` 把每个 GLB 的多个 mesh/surface 合并成 **1 个 skinned surface**（保留骨骼权重），武器等小件在原节点内合并，节点名不变（拔刀/掉落逻辑不受影响）。
  - TripoSR 扫描网格做保守清理：小连通岛、退化/极薄三角形、内翻微面、平滑重算法线、贴图 alpha discard。
  - NPC 从 4 个 GLB 轮换，固定模型 + 色相/明度 ±8% + 身高 ±5% + 体型宽窄 ±8%；按 seed 生成 6 类配饰（斗笠/头巾/背篓/围巾/腰带/提灯），老年 NPC 加胡子。
  - 3D 模型开实时投影（仅主光），脚下再叠软 blob 影补接触暗部。
  - NPC LOD：15m 外冻结骨骼动画，20m 外隐藏；同屏最多渲染 10 个。
  - 对话/HUD 的 2D 立绘头像继续保留；`CharacterBillboard` 文件已退役且不再被引用。
- **第八轮 HD-2.5D 画稿建筑**（Grok Bot 资产吸收）：相机固定俯角朝北看，村口山门用 gate_L0/L1/L2 三层画稿
  （L0 铺地平铺 + L1 后柱 + L2 前柱屋顶，门洞可走、柱基阻挡、影子实体），民居/石灯幢换画稿+配套投影，
  竹林垫画稿竹丛（2 draw call），地形铺画稿草地 tile。走路锁步升级为鞋底级两骨 IK（FOOT_LOCK 5 角色 ≤1mm），
  流苏三段惯性摆动、拔剑过肩弧线、战报金框不再裁切（UI 4/4）。
- 相机：pitch −28° / FOV 36 / 距离 11.5m / look_height 1.05 / 阻尼 0.12s；960×540 下人物屏高约 21%（内部 1920×1080 计 232px）。
- 调色：FILMIC exposure 0.82 / white 8.0 / ambient 0.34 / contrast 1.10 / saturation 1.05；DEPTH 雾 16–58m；glow 0.28/0.04/1.15；暖主光 `#FFD9A8` + 冷补光 `#7FA6C9`。
- 性能：角色每个 GLB 合并为 1 个 skinned surface（武器/道具在原节点内合并），NPC 配饰 1–2 个 MeshInstance3D；静态建筑/道具先区块内合批、再跨 9 区块合并成 ~12 个全局 MeshInstance；草地/石子/花/竹叶等 MultiMesh 跨区块合并成 ~14 个全局 MultiMesh（同屏约 2800 实例）；远景竹/山/前景枝叶单独 MultiMesh。

## 资产表

| 资产 | 路径 | 说明 |
|---|---|---|
| 人物 GLB | `assets/glb/{shenyan_script,shenyan,linzhaowan,gesancheng,liheng,yaoxing_dashou}.glb` | 探索态沈砚用干净低模 `shenyan_script`（84 mesh → 1 surface）；战斗沈砚与 NPC 用 TripoSR 资产 |
| 角色网格优化 | `scripts/world/character_mesh_optimizer.gd` | skinned surface 合并、扫描清理、顶点色/贴图混排；预烘焙入口 `tools/bake_character_meshes.gd` |
| NPC 配饰 | `scripts/world/npc_accessories.gd` | 6 类程序化配饰 + 胡子，BoneAttachment3D 挂骨骼，单材质顶点色 |
| 预烘焙角色场景 | `generated/characters/v1/*.res` | 由 bake 工具生成（见 `.gitignore`，缺失时运行时自动合并） |
| 卡通着色 | `shaders/toon_char*.gdshader` + `shaders/ink_hull.gdshader` | toon 两段明暗 + 约 0.8–1.2px 描边；`toon_char_vcol*` 供合并 surface 使用 |
| 应用图标 | `assets/branding/icon_512.png`（及 192/432） | 由 `tools/make_icon.gd` 从沈砚立绘裁切生成 |
| 3D 三视角预览 | `captures/shenyan_3d_preview.png` | 正面 / 侧面 / 斜 45°，Workbench |
| 第四轮探索道具 | `assets/props/` | 石灯、篱笆、木箱、路牌、水井及对应影子图 |
| 招式/意图图标 | `assets/icons/` | 玩家 4 个 + 敌方意图 3 个 |
| 2D 角色参考 | `docs/ref-characters-v2/`、`docs/ref-characters-v3/` | 只用于对话/HUD 头像与回滚参考 |
| **第八轮吸收画稿** | `assets/imported/`（索引见其 INDEX.md） | 村口山门三层画稿、民居、竹丛、草地 tile、石灯幢 r4b——已接入 `BuildingFactory`/`ChunkBuilder` 运行时 |

## 验收截图

- `captures/explore.png`、`captures/dialogue.png`、`captures/hud.png`（`scenes/render_captures.sh` 用 xvfb 渲染 960×540）。
- 第四轮近景对比：`captures/closeup_before.png`（原始 `shenyan.glb`）与 `captures/closeup_after.png`（`shenyan_script` 合并后），同机位 2.7m。
- NPC 群像：`captures/npc_variety.png`，8 人覆盖 6 类配饰。
- 诊断用近景：`captures/npc_close.png`（周伯 3D 模型受光/描边/投影）。
- 第八轮吸收对比：`captures/compare_village_r8.png`、`captures/compare_gate_r8.png`（吸收前/后同机位）；
  `captures/gate.png`（村口画稿牌坊）、`captures/bamboo.png`（画稿竹丛）。

## 测试与性能

```bash
export PATH=$HOME/.local/bin:$PATH
godot --headless --path . -s tools/bake_character_meshes.gd  # 改过网格优化器后重跑
GODOT=godot bash tests/run_all.sh          # 145/145 + UI 4/4 + BREATH + FOOT_LOCK(5 角色) + WORLD 10/10
PROJ=$(pwd) bash ~/games/perf/run-probe.sh # 软件渲染探针
```

本轮数字与对比见 `REPORT.md`。

## Android

`export_presets.cfg` 已就位：包名 `com.xiaoyan.shanhe`、arm64-v8a、横屏（sensor_landscape）、Gradle 关闭、应用图标已设置。

```bash
export JAVA_HOME=$HOME/android/jdk17
export ANDROID_HOME=$HOME/android/sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
godot --headless --path . --export-debug "Android" /tmp/self.apk
```

## 待办 / 已知缺口

- NPC 基础模型仍是 TripoSR 扫描资产，近于 2–3m 仍可能有细节碎片；本轮做了清理与配饰遮挡，探索态主角已换干净低模。
- NPC 基础模型池 5 个（含干净低模 `shenyan_script`），配饰 6 类；后续可补更多手写低模。
- 战斗主角仍用 `shenyan.glb`（需要 attack/hit/down），战斗镜头近看仍可能有轻微扫描碎片。
- 机缘点视觉在 25m 外按 LOD 隐藏；更远的名称/光环需要时再开。
- 战斗场景与 BattleHUD 已接入主流程；更细的战斗演出仍可继续打磨。
- 性能：battle objects 297 / primitives 621k 略超预算（250 / 600k），削减路径见 `REPORT-INTEGRATION.md`。
- `data/regions.json` 的 farmland→"fields"、mountain_road→"stairs" feature 与 dispatch 不匹配（与第八轮修的 gate→"shanmen" 同类死值），解锁前先确认对应 POI builder。
- 资源管线缺口见 `docs/fe-needs.md`。
