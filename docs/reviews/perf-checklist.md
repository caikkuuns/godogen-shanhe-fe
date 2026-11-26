# 性能静态审查清单 · 《山河剑行》

- 审查对象：服务器工程 `<project>`，快照 commit `ad785ce`（抓取 2026-11-21 00:07 UTC），本地副本 `perf/src/`
- 预算口径：以工程内 `docs/shanhe_android_perf_budget.md` 为准（默认档 30fps、draw call ≤300、primitives ≤600k、同屏唯一材质 ≤30）
- **没有任何真机/渲染实测**（服务器无 GPU，软件 Vulkan 的 FPS 不可信）。除特别注明外，所有量级是【静态估算】，需用 `perf/probe/` 的探针确认
- **快照处于重构中间态**：`player.gd`/`npc.gd` 已改成 Sprite3D 广告牌方案，但 `world_builder.gd:932-941` 还在给 `WorldNpc` 写已删除的 `dirs/model_path/height_px/...` 字段 → 当前这条 HEAD 跑探索场景大概率报 `Invalid set index`。所以旧 GLB/骨骼相关结论只对战斗场景有效，探索按「Sprite3D 最终形态」评估
- 新系统（`NpcDB`/`EncounterDB`/`HiddenQuestDB`/`GameClock`/`BuildingFactory`）本次快照里**还没有调用方**，属于即将接线；接线后 NPC 数量会从 13 → 约 31，见 A4/B1

---

## 一、P0：收益最大（先做）

### A1 静态建筑没有合批：约 250 个独立 MeshInstance3D，且默认全部投影

- 证据：`scripts/world/world_builder.gd:173-181`（`_add_mesh` 只设 mesh/material/transform，**从不设 `cast_shadow`**，默认 ON）
  - 门楼 `world_builder.gd:383-436`：每根柱 4 件 ×4 + 枋 3 + 斗拱 8 + 屋面 2 + 匾/灯/门槛/幡 ~16 ⇒ 约 40 件
  - 4 栋民居 `world_builder.gd:442-480`：每栋约 24 件 ⇒ 约 100 件
  - 驿亭 `1044-1066`、石阶 `1080-1111`、清溪庵 `1114-1165`、松树 `874-882`、远山 `865-873`、水岸石 `375-381`：合计约 60 件
  - 加地面/石/雾片 ⇒ **主 pass 约 250 draw call（粗算）**；方向光 `shadow_enabled=true` + 2 级 split（`world_builder.gd:281-289`）会让同一批件再进阴影 pass 1~2 遍
- 为什么慢：Mobile 渲染器不会自动合批独立 MeshInstance3D，1 个 mesh = 1 draw call；阴影 pass 叠加后很容易冲破 300 预算
- 修法（给改代码的人）：在 `world_builder.gd` 里把「材质 → SurfaceTool」累积起来（`SurfaceTool.append_from(mesh, transform)`），每种材质最后 `commit` 成 1 个 MeshInstance3D 挂到静态父节点；小装饰件 `cast_shadow = SHADOW_CASTING_SETTING_OFF`，只留主梁/墙/屋顶投影
- 预期收益：主 pass draw call ≈250 → ≈35（材质数），加阴影 pass 总量降 ≥50%
- 风险：中（需重建视觉，碰撞本来就独立于渲染，不受影响）；工作量：M~L

### A2 SpriteSheet 每次取帧都 `ResourceLoader.exists()+load()`

- 证据：`scripts/world/sprite_sheet.gd:44-47`（`idle_texture`）、`49-52`（`walk_texture`）——两个函数都 `load(path) if ResourceLoader.exists(path)`
  - 调用点：`scripts/world/player.gd:107`（行走每帧）、`116`、`130`、`41`；`scripts/world/npc.gd:65`、`161`、`167`（**每个 NPC 每帧**）
- 为什么慢：每帧几十次字符串格式化 + 资源数据库查找；更糟的是**某帧第一次用到的 PNG 会在主线程解码**——玩家第一次走路/转向时卡一下（320×420 / 340×420 PNG，每角色 idle+walk ≈20 张）
- 修法：`SpriteSheet` 加 `static var _cache := {}`（path→Texture2D），首次进表，后续 O(1) 取；再在启动/加载屏用 `ResourceLoader.load_threaded_request` 把两个角色的全部帧预载完成（约 40 张，RGBA8 ≈21MB，在预算内）
- 预期收益：消除每帧 load 调用 + 消除首次行走/转向的卡顿尖刺
- 风险：低；工作量：S

### A3 战斗 SubViewport 从启动起一直 `UPDATE_ALWAYS`

- 证据：`scripts/ui/battle_panel.gd:47-52`——`_build()` 里就设 `render_target_update_mode = SubViewport.UPDATE_ALWAYS`，`size = Vector2i(1920, 670)`；`123` 战斗开始再设一次；`174` 关闭时才 `UPDATE_DISABLED`
- 为什么慢：探索时每帧额外渲染一个 1920×670 独立 `World3D`（1.29M 像素 ≈ 主场景的 62%），白吃半份 GPU/带宽预算；软件渲染下尤其明显
- 修法：`_build()` 里改 `UPDATE_DISABLED`；`start()` 时才 `UPDATE_ALWAYS`；关闭时回 `UPDATE_DISABLED`；顺手把 `size` 降到 1280×448（移动端面板区只占 62% 屏高）
- 预期收益：探索态整帧渲染成本砍掉约三分之一（第二视口归零）
- 风险：低；工作量：S

### A4 每个 NPC 3~4 个 draw call，名字标签没有可视距离

- 证据：`scripts/world/npc.gd:69-80`（`_name_label`）、`82-94`（`_prompt`）、`96-111`（blob shadow MeshInstance）、`56-67`（Sprite3D）；现 13 个剧情 NPC（`world_builder.gd:969-1041`），接 `NpcDB.generate()`（默认 18，`npc_db.gd:97-111`）后 ≈31 个
- 为什么慢：每个 NPC = 1 Sprite + 1 阴影 quad + 2 个 Label3D（每个 Label3D 自己一张纹理、1 draw call），31 个 NPC ⇒ 约 124 个 draw call 只画 NPC；远处的名字标签照画不误
- 修法：`_name_label.visibility_range_end = 12.0`（`_prompt` 已经只在聚焦时显示，`npc.gd:239-241`）；或改成屏幕空间只画聚焦 NPC 的名字
- 预期收益：中远景 draw call 降 20~40，且省 Label3D 的纹理/overdraw
- 风险：低（近处观感不变，需调 12~15m 阈值）；工作量：S

---

## 二、P1：每帧脚本开销（低风险）

### B1 每个 NPC 每帧全量跑 `_process`，不按距离裁剪

- 证据：`scripts/world/npc.gd:117-136`——每帧：`_sprite.modulate` 无条件 lerp+赋值（`121`）、算玩家距离（`124`）、每 0.25s 跑一次 `_keep_labels_clear_of_hud()`（`130-132` → `190-237`，内含 `get_tree().get_nodes_in_group("hud_persistent")` 新建数组 + 每个标签 `get_aabb()` + 2 次 `unproject_position`）、`_update_frames`（`136`，进一步每帧 `load()`，见 A2）
- 修法：① `_process` 开头算一次与相机/玩家的距离，`> 25m` 直接 `return`；② `_sprite.modulate` 与目标差 `> 0.004` 才写；③ `_keep_labels_clear_of_hud` 改 2Hz，且 HUD 矩形列表缓存在 NPC 外部/静态，连接 `hud.modal_changed`、`get_viewport().size_changed` 时刷新；④ 帧表走 A2 的缓存
- 预期收益：31 NPC 时每帧脚本从 O(31×全量) 降到 O(近处几个)
- 风险：低；工作量：S~M

### B2 玩家每 physics tick（60Hz）无条件写 `sprite.modulate`

- 证据：`scripts/world/player.gd:98-99`——`_region_tint = _region_tint.lerp(...)` 后**无条件** `sprite.modulate = _region_tint`；颜色收敛后仍每帧 60 次写渲染服务器属性
- 修法：`if not _region_tint.is_equal_approx(sprite.modulate): sprite.modulate = _region_tint`，或只在 `set_region_tint()` 里写
- 预期收益：小（60 次/秒属性写 → 0），但零风险、顺手
- 风险：极低；工作量：S

### B3 `main.gd` 每帧 `get_nodes_in_group()` 重建数组

- 证据：`scenes/main.gd:73-95`——`_update_interaction_focus()` 每帧 `get_tree().get_nodes_in_group("interactable")`（新建 Array）并遍历，逐 NPC `is_visible_in_tree()` + 距离；31 NPC 时每帧 31 次
- 修法：缓存 group 数组（NPC 生成/`set_dormant` 时刷新），或直接遍历 `world.npcs` 字典；判定频率可降到 10Hz（NPC 移动很慢）
- 预期收益：每帧一次数组分配 + 遍历（约 0.1~0.3ms/帧，31 NPC）
- 风险：低；工作量：S

### B4 雾片每帧改材质颜色 + 一段死代码在空转

- 证据：`scripts/world/world_builder.gd:83-101`——每帧 4 张雾片改 `mat.albedo_color`（`92-98`，`_build_mist` 里每片 `mat.duplicate()`，`855-857`）；`99-101` 循环 `_lantern_lights`，但 `_build_stone_lantern()`（`580-598`）**从未被调用**，列表永远为空
- 修法：雾片透明度只与玩家距离有关，限到 5~10Hz；共享 1 个 material 改 instance uniform（省状态切换）；删除 `_build_stone_lantern`/`_lantern_lights` 死代码（或真接线并受 4 个点光预算约束）
- 预期收益：每帧材质更新 4 次 → 0；少 3 份材质
- 风险：低；工作量：S

### B5 地图界面每帧整张重画

- 证据：`scripts/ui/map_view.gd:9-11`——`_process` 里 `if visible: queue_redraw()`；`_draw`（`21-74`）含 2 条 21/33 点折线、46 个圆、24 段弧、3 次 `draw_string`（中文排版）
- 修法：只在玩家移动 >0.5m 或 5Hz 定时 redraw；静态底图（河/路/房/竹/字）一次性画进 `ImageTexture`，每帧只画玩家红点
- 预期收益：打开地图时 UI 重绘成本降 >80%
- 风险：低；工作量：S~M

### B6 虚拟摇杆拖动期间每帧重画

- 证据：`scripts/ui/virtual_joystick.gd:37-42`（每次 `_active` 就 `queue_redraw()`；`_redraw_time` 变量算了没用）；`_draw` `107-126` 有 2 个 64 段 `draw_arc`
- 修法：限 30Hz，或 `value`/`_press_scale` 变化 >0.01 才重画
- 预期收益：小；风险：低；工作量：S

### B7 对话面板每帧写 `_hint.visible` + 每句 `load()` 立绘

- 证据：`scripts/ui/dialogue_panel.gd:242-247`（每帧写 `_hint.modulate.a` 和 `_hint.visible` → CanvasItem 更新）；`284-297`（`_show_portrait` 里 `load(resolved)`，`288`，首次约 1000×1050 PNG 主线程解码）
- 修法：`visible` 只在 `_typing/_awaiting_choice/_narrating` 变化时写；立绘加静态缓存并和 A2 一起预载
- 预期收益：消除开对话时的首帧卡顿；风险：低；工作量：S

### B8 相机在 `_process` 里平滑

- 证据：`scripts/world/player_camera.gd:19-25`——`global_position.lerp` + `look_at` 在渲染帧执行，而移动在 60Hz 物理帧；30fps 目标下相机与角色节奏不一致（轻微顿挫）
- 修法：移到 `_physics_process`，或开 `physics/common/physics_interpolation=true`（需复测构图/跟随手感）
- 预期收益：30fps 下手感一致性；风险：低-中；工作量：S

---

## 三、P2：渲染设置与预算

### C1 没有锁 30fps

- 证据：`project.godot:5-11` 的 `[application]` 段没有 `run/max_fps`；预算文档默认档要求 30fps（60/120Hz 屏会跑满刷新率，费电发热、挤占温控余量）
- 修法：`[application] run/max_fps=30`（或用 `Engine.max_fps` 做画质分档）
- 预期收益：功耗/温控直接受益，帧率稳定；风险：低；工作量：S

### C2 阴影距离/质量偏预算上限

- 证据：`scripts/world/world_builder.gd:281-289`——`shadow_enabled=true`、`SHADOW_PARALLEL_2_SPLITS`、`directional_shadow_max_distance=70.0`、`shadow_blur=1.7`
- 预算文档默认档建议 40m / Soft Very Low。修法：`max_distance 40`、`shadow_blur 0.9~1.2`；`project.godot` 显式写 `rendering/lights_and_shadows/directional_shadow/size.mobile=2048`、`.../soft_shadow_filter_quality.mobile=1`、`.../directional_shadow/16_bits=true`
- 预期收益：阴影 pass 带宽/填充率下降；风险：低-中（阴影边缘变硬，需对截图）；工作量：S

### C3 地面 92×92 细分 ≈17k 三角 + 启动时逐顶点上色

- 证据：`scripts/world/world_builder.gd:298-341`——`PlaneMesh.subdivide_width/depth = 92`，顶点数 ~8649，`313-333` 逐顶点 `sin/cos/smoothstep` 算颜色（启动一次性，几十 ms 级）
- 修法：细分降到 48×48（~4.6k 三角，颜色噪声尺度约 2m，外观差异很小）；颜色算法保留
- 预期收益：~12k 三角/帧 + 启动时间；风险：低；工作量：S

### C4 雾片过大（overdraw），且每片一份材质

- 证据：`scripts/world/world_builder.gd:836-862`——4 张 28~36m 宽、7.5m 高的半透明 quad，每片 `mat.duplicate()`（`857`），屏占比远超预算文档建议的「每片 <15%」
- 修法：减到 2~3 片或拉近缩小；共享 1 个 material + instance uniform；`depth_draw_mode=DISABLED` 保持
- 预期收益：Mali 类 GPU 的 overdraw 明显下降；风险：低-中（雾观感需对图）；工作量：S

### C5 同屏唯一材质数超预算（≈40+，预算 ≤30）

- 证据：世界 `_mat` 26 种（`world_builder.gd:112-150`）+ 每个道具新建 material（`_add_prop` `505-549`，12 个道具 shadow 各一份，`542-547`，且 alpha 全是 0.92 可复用）+ 雾片 4 份 duplicate + 战斗角色 3 份 next_pass shader 材质（`toon_model.gd:28-47`）
- 修法：道具 shadow material 复用同一份；雾片共享（见 C4）；配合 A1 按材质合并
- 预期收益：状态切换/排序更友好；风险：低；工作量：S

### C6 Sprite3D 双面 + alpha scissor 的 overdraw

- 证据：`scripts/world/player.gd:37-38`、`scripts/world/npc.gd:61-62`（`double_sided = true` + `ALPHA_CUT_DISCARD`）
- 说明：alpha scissor 是正确选择（不要改 blend）；但 `double_sided` 让 Billboard 背面也画。修法（可选）：确认人物卡始终正面朝向相机后设 `double_sided=false`；不确定就保留
- 预期收益：片元成本降约一半（人物占屏比大时才有感）；风险：中（可能穿帮）；工作量：S

### S1~S3 Shader 专项（shaders/ 共 3 个）

- **没有**全屏遍历 shader、没有 `SCREEN_TEXTURE`/`DEPTH_TEXTURE` 采样、没有 `TIME` uniform、没有每帧 `set_shader_parameter`（grep 全工程：`set_shader_parameter` 只在材质创建时调用）→ 这几类是干净项，不用改
- S1 `shaders/ink_hull.gdshader:25-29`：`fragment` 里 `if (view_dist < min_distance) discard;`——近距离整片丢弃本身是省的，但 `discard` 会破坏 early-Z（预算文档 §4.6 提醒 Mali 尤其敏感）。**真正的大头不在 shader，而在它被挂了 3 层**：`toon_model.gd:28-47` 每个角色 surface = front toon + 内层 unshaded + hull（`next_pass` 链），每个角色 mesh 渲染 3 遍。修法：hull 只挂主要 body surface，小件（发丝/饰物/剑）不挂；`min_distance` 保持 6 或调到 4~6；远距离可直接整条 hull 不做（`visibility_range`）
- S2 `shaders/ink_hull.gdshader:16-22`：vertex 里 `MODELVIEW_MATRIX * vec4(VERTEX,1)` 算了两次（17 行和 19 行）→ 合并成一次，每个顶点的矩阵乘法减半（hull 顶点数=角色顶点数×3 pass，有实际意义）
- S3 `shaders/toon_char_front.gdshader:13-25`：每像素 1 次采样 + lum/chroma + 4 次 UV 边界比较，最后 `if/else` 两个分支各写一次 `ALBEDO/EMISSION` → 可合并为「先算 c，再统一 `ALBEDO=c; EMISSION=c*e`」，省一次 ALBEDO 赋值和一个分支；`toon_char.gdshader:10-23` 同理。两个 shader 都是 `fog_disabled`（`toon_char*.gdshader` render_mode），与移动端雾预算一致，保持
- 结论：shader 本身不慢，**慢在「同一可见物体被 3 个 pass 覆盖」**（只在战斗 3D 角色上出现，探索态是 Sprite3D 广告牌，只有 1 pass）

---

## 四、P3：启动/战斗/后续接线

### D1 4 个数据 autoload 在 `_ready` 同步读 JSON

- 证据：`dialogue_db.gd:37-56`（3 个 JSON + `validate()` 全图环检测/可达性，`380-412`）、`npc_db.gd:20-54`（2 个 JSON）、`encounter_db.gd:33-73`、`hidden_quest_db.gd:14-46`
- 修法：数据校验移到单元测试/构建期；运行时只 parse；或改 `load_threaded_request` 在首帧后完成
- 预期收益：冷启动预算（≤5s）里的几十~几百 ms；风险：低；工作量：S~M

### D2 战斗场景首次进入的实例化 + 着色器编译

- 证据：`battle_stage.gd:73-96`（每次 `setup()` 都 `ToonModel.instantiate` 两个 GLB，各带 3 份 next_pass shader 材质 → 首次进战斗有管线编译）；`battle_panel.gd:170-176` 关闭时只 queue_free 模型、viewport 保留
- 修法：进战斗前预热（加载屏里 instantiate 一次再 free / `RenderingServer` 预热管线），避免战斗首帧卡顿
- 预期收益：探索→战斗切换 ≤1s 且无 >100ms 尖刺；风险：低；工作量：S~M

### D3 `BuildingFactory`（未接线）在 `_init` 生成 8 张 128×128 噪点纹理

- 证据：`scripts/world/building_factory.gd:16-41`（`_make_tex` 8 次）、`65-113`（128×128 逐像素 `set_pixel` + `match`/三角，约 13 万次 ×8；`ImageTexture.create_from_image` 每张）
- 说明：目前无调用方；Claude 接线后它会在启动时跑。修法：合成 1 张图集（8 个 64×64 tile）或改用 `NoiseTexture2D`/shader；不要加大尺寸
- 预期收益：避免接线后几十~上百 ms 启动尖刺；风险：低；工作量：S

### D4 只在战斗用的骨骼/动画每帧开销（当前探索态已无）

- 证据：`character_anim.gd:189-192`、`213-220`（`create_timer(1/60)` 每帧建一个 SceneTreeTimer，一次倒地可建上百个）；`291-294`（`_measure_walk_scale` 里 pts×pts 双重循环 48² = 2304 次，每次 attach 跑一遍）；`idle_breath.gd:45-67`、`foot_lock.gd:33-43`（SkeletonModifier 每帧写骨骼）
- 说明：玩家/NPC 改 Sprite3D 后，探索态不再有骨骼；这些只剩战斗用，故降级到 P3。修法：倒地/伸手阶段改用 `_process` 累加器或 Tween；`_measure_walk_scale` 的 extrema 用 min/max 一次遍历，且按模型路径缓存结果
- 风险：低；工作量：S

---

## 五、优先级总表（收益/风险/工作量）

| # | 条目 | 收益 | 风险 | 工作量 | 证据 |
|---|---|---|---|---|---|
| A1 | 静态建筑按材质合并 + 小件关阴影 | ★★★★★ | 中 | M~L | world_builder.gd:173-181, 383-480 |
| A2 | SpriteSheet 纹理缓存 + 预载 | ★★★★★ | 低 | S | sprite_sheet.gd:44-52 |
| A3 | 战斗 SubViewport 初始禁用 | ★★★★☆ | 低 | S | battle_panel.gd:47-52 |
| A4 | 名字标签可视距离 | ★★★☆ | 低 | S | npc.gd:69-94 |
| B1 | NPC _process 距离裁剪 + HUD rect 缓存 | ★★★☆ | 低 | S~M | npc.gd:117-136, 190-237 |
| B2 | 玩家 modulate 加变化判断 | ★★ | 极低 | S | player.gd:98-99 |
| B3 | 交互聚焦不每帧取 group | ★★ | 低 | S | main.gd:73-95 |
| B4 | 雾片降频 + 删死代码 | ★★ | 低 | S | world_builder.gd:83-101, 580-598 |
| B5 | 地图界面限频/缓存底图 | ★★★ | 低 | S~M | map_view.gd:9-11 |
| B6 | 摇杆重画限频 | ★ | 低 | S | virtual_joystick.gd:37-42 |
| B7 | 对话面板 hint/立绘缓存 | ★★ | 低 | S | dialogue_panel.gd:242-247, 288 |
| B8 | 相机平滑移到物理帧 | ★★ | 低-中 | S | player_camera.gd:19-25 |
| C1 | 锁 30fps | ★★★ | 低 | S | project.godot:5-11 |
| C2 | 阴影距离/质量收紧 | ★★★ | 低-中 | S | world_builder.gd:281-289 |
| C3 | 地面细分 92→48 | ★★ | 低 | S | world_builder.gd:298-341 |
| C4 | 雾片数量/材质 | ★★ | 低-中 | S | world_builder.gd:836-862 |
| C5 | 道具/雾片材质复用 | ★★ | 低 | S | world_builder.gd:505-549 |
| C6 | Sprite3D 单面（可选） | ★★ | 中 | S | player.gd:37-38 / npc.gd:61-62 |
| D1 | autoload JSON 启动优化 | ★★ | 低 | S~M | dialogue_db.gd:37-56 |
| D2 | 战斗切换预热 | ★★ | 低 | S~M | battle_stage.gd:73-96 |
| D3 | BuildingFactory 纹理 | ★★ | 低 | S | building_factory.gd:65-113 |
| D4 | 战斗骨骼/计时器开销 | ★ | 低 | S | character_anim.gd:189-220 |
| S1 | hull/内层 pass 只挂主要 surface | ★★ | 低-中 | S | toon_model.gd:28-47, ink_hull.gdshader:25-29 |
| S2 | ink_hull 顶点矩阵乘合并 | ★ | 低 | S | ink_hull.gdshader:16-22 |
| S3 | toon shader 分支合并（可选） | ★ | 低 | S | toon_char_front.gdshader:13-25 |

---

## 六、待探针确认（不要当结论用）

1. 实际 draw call / primitives / objects / 纹理与视频内存：见 `perf/probe/`，只有计数器可信，FPS 不可信
2. 静态估算的 `≈250` 件 MeshInstance3D 是否准确（探针会按类统计节点数、投影开启数、MultiMesh 实例总数、唯一材质数）
3. 当前 HEAD 的运行时报错（`world_builder` 与 `npc.gd` 字段不一致）会污染探针结果——建议 Claude 提交修复后重跑一次
4. `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 在软件 Vulkan 下是否与真机同口径（计数应为同口径，真机再复核一次）

## 七、Godot 4.7 Mobile 渲染器要点（本项目落地口径）

- **draw call**：预算默认档 ≤300（含阴影 pass），不含阴影主 pass ≤180。本项目静态建筑粗算 ~250 + 阴影 → 必超（A1）；NPC 标签 31 个 ≈60+（A4）；战斗面板第二视口长期常开（A3）。这三项是 draw call 的三个来源
- **纹理压缩**：`project.godot:49` 已开 `import_etc2_astc` ✓。注意 `.import` 不进 git（`.gitignore` 忽略），所以压缩设置只存在于服务器本地：需确认每张运行时贴图是 `detect_3d → VRAM Compressed + mipmap`；角色帧建议 Lossless 或 ASTC 4×4 + `Fix Alpha Border`（ETC2 会让精灵 alpha 边缘出块状）；`Process > Size Limit` 统一 2048（立绘 ~1000 可接受）；`docs/ref-characters/raw/`、`*_turnaround*`、`*_preview*` 不应进导出包（脚本按路径 `res://docs/...` 直接读运行时素材，导出时必须 `exclude_filter` 掉这些非运行时文件）
- **MultiMesh**：竹子（`world_builder.gd:737-769`，128 株 + 叶 ≈270 实例）、草（`787-816`，820 实例）、小石头（`611-629`，34 实例）已经用上 ✓。缺：竹叶/竹竿没有 `visibility_range_end`（草有 42m，`815`），且全部塞进一个 MultiMesh → 没有视锥剔除，远景照样画。建议：竹叶加 `visibility_range_end=60`；预算文档建议按 16m 区块切分（工作量 M）
- **阴影/灯光**：1 个方向光开阴影（`world_builder.gd:281-289`，2 splits / 70m / blur 1.7）+ 1 个补光无阴影（`291-296`）✓；无 OmniLight（灯笼函数是死代码 `580-598`）→ 点光预算当前宽裕，但接灯笼后要守「每网格 ≤4 个 Omni+Spot、全视图 ≤8 个」，且 `_add_mesh` 出来的所有件默认投影（A1/C2 一起改）
- **反射探针/环境**：无 ReflectionProbe ✓；`world_builder.gd:249-276` 没有 SSAO/SSIL/SSR/SDFGI/volumetric_fog（Mobile 不支持，符合）✓；`glow_enabled=false`（`258`）→ 灯笼 emissive 不会发光。若美术要 glow：Mobile 支持，按预算 §4.3 开 2 级 + `glow_hdr_threshold ≥1.0`，只在默认档以上开
- **UI 重绘成本**：`canvas_items` stretch 下 UI 按 1920×1080 逻辑分辨率绘制（不受 3D scale 0.75 影响）；`CanvasLayer` 只有文本变化才重排，`hud.refresh()` 只在 `GameState.changed` 时调用（低频）✓。主要重绘点是两个自绘 `Control`：地图 `map_view.gd:9-11` 每帧全画（B5）、摇杆 `virtual_joystick.gd:37-42` 拖动期间每帧画（B6）。另外 `dialogue_panel.gd:242-247` 每帧写 `visible`（B7）
- **帧率/物理**：没锁 30fps（C1）；物理 60Hz（`project.godot:35-38`）而渲染目标 30fps → 每渲染帧 2 次物理，没开 `physics_interpolation`（B8 一起处理）
- **阴影贴图设置**：`project.godot` 没显式写 `directional_shadow/size.mobile`、`soft_shadow_filter_quality.mobile`、`directional_shadow/16_bits`、`positional_shadow/atlas_size.mobile`，走引擎默认；建议按预算文档 §4.4 显式写死（C2），避免升级引擎后默认值变化导致回归

## 八、给审核的其他 agent 的硬约束

- 只读工程，不改源码/git；合并 geometry（A1）必须在新分支做，并逐张截图对比
- 不要用 `cull_disabled` 修法线、不要 `create_trimesh_shape`（预算文档 §8 P3）
- 改完用 `perf/probe/` 重跑一次，写 `perf/probe-notes.md` 记录前后数字
