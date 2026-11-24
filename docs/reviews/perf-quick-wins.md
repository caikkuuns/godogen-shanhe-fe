# Quick Wins · Top 10（低风险、可照做）

> 口径：基于快照 commit `ad785ce`（`perf/src/`）。**未实测**，收益为静态估算；做完请用 `perf/probe/run-probe.sh` 对 draw call/内存前后对比。
> 顺序 = 建议执行顺序（先做 1，再做 2…），每一项都能独立提交。

## 1. SpriteSheet 加纹理缓存 + 启动预载

- 问题：取每一帧都 `ResourceLoader.exists()+load()`，玩家行走每帧、NPC 每帧；首次用到的 PNG 在主线程解码（卡顿）
- 证据：`scripts/world/sprite_sheet.gd:44-47`、`49-52`；调用 `scripts/world/player.gd:107`、`116`、`130`；`scripts/world/npc.gd:161`、`167`
- 改法：`SpriteSheet` 加 `static var _tex_cache := {}`，`idle_texture/walk_texture` 改为「先查缓存、miss 才 load 并写回」；再补一个 `static func preload_all(ids: Array)`，在 `main.gd:_ready()`（或加载屏）把 `shenyan`/`linzhaowan` 的 idle 4 方向 + walk 4 方向 4 帧全部载入
- 预期收益：消除每帧几十次资源查找；消除首次走路/转向的掉帧
- 风险：低（纯缓存，纹理总量 ≈21MB）
- 工作量：S（约 20~30 行）

## 2. 战斗 SubViewport 初始改为 `UPDATE_DISABLED`

- 问题：探索时每帧仍渲染 1920×670 的第二个 3D 视口（≈主场景 62% 像素）
- 证据：`scripts/ui/battle_panel.gd:47-52`（`_build` 里就 `UPDATE_ALWAYS`）、`123`、`174`
- 改法：`_build()` 里设 `SubViewport.UPDATE_DISABLED`；`start()` 里再设 `UPDATE_ALWAYS`；`close_and_release()` 已设 DISABLED 不用动；顺手 `_stage_host.size = Vector2i(1280, 448)`
- 预期收益：探索态 GPU 负载直接去掉一个 1.29M 像素视口
- 风险：低（战斗内观感需看一次截图）
- 工作量：S（改 2 行 + 1 个尺寸）

## 3. 给 NPC 名字标签加可视距离

- 问题：每个 NPC 2 个 Label3D + 1 阴影 + 1 Sprite ≈4 draw call；远处标签照画
- 证据：`scripts/world/npc.gd:69-80`（名字）、`82-94`（prompt）、`96-111`（阴影）；NPC 数量从 13（`world_builder.gd:969-1041`）涨到 ~31（`npc_db.gd:97-111` 默认 18 个）
- 改法：`_build_visuals()` 里 `_name_label.visibility_range_end = 12.0`（`_prompt` 已按聚焦控制，`npc.gd:239-241`）；阈值 12~15m 可调
- 预期收益：中远景 draw call / Label3D 纹理开销降 20~40
- 风险：低（近处不变）
- 工作量：S（1 行）

## 4. NPC `_process` 加距离门限 + HUD 矩形缓存

- 问题：每个 NPC 每帧跑 modulate lerp、距离、标签避让（4Hz，但每次都 `get_nodes_in_group` 新建数组 + `get_aabb` + `unproject_position`）
- 证据：`scripts/world/npc.gd:117-136`（主循环）、`121`（无条件写 modulate）、`130-132`（4Hz 避让）、`190-237`（避让实现）
- 改法：① 开头 `if global_position.distance_to(player_ref.global_position) > 25.0: return`（玩家为空时跳过）；② `_sprite.modulate` 与目标差 >0.004 才写；③ 避让频率 0.25s → 0.5s，HUD 矩形列表缓存为静态变量，在 `hud.modal_changed` / `get_viewport().size_changed` 时刷新
- 预期收益：31 NPC 时每帧脚本开销降一个数量级（近处几个 NPC 才有完整逻辑）
- 风险：低（远处 NPC 不转向/不播走路帧，视觉几乎无感）
- 工作量：S~M

## 5. 玩家 `sprite.modulate` 加变化判断

- 问题：`_physics_process`（60Hz）每帧无条件写 `sprite.modulate`，颜色早已收敛
- 证据：`scripts/world/player.gd:98-99`
- 改法：`if not _region_tint.is_equal_approx(sprite.modulate): sprite.modulate = _region_tint`
- 预期收益：每秒 60 次无意义渲染属性写 → 0
- 风险：极低
- 工作量：S（1 行）

## 6. `main.gd` 交互聚焦缓存 group 数组

- 问题：每帧 `get_nodes_in_group("interactable")` 新建数组并遍历全部 NPC
- 证据：`scenes/main.gd:73-95`（`76` 是 group 查询）
- 改法：`_interactables` 缓存数组，NPC 生成 / `set_dormant` 时刷新（`npc.gd:243-250` 加/移除 group 的地方同步）；或直接遍历 `world.npcs.values()`；判定可降到 10Hz
- 预期收益：每帧一次数组分配 + 31 次 `is_visible_in_tree` 降为 1/6 频率
- 风险：低
- 工作量：S

## 7. 地图界面限频 / 底图缓存

- 问题：地图打开期间每帧整张重画（折线 + 46 圆 + 24 段弧 + 3 次中文 `draw_string`）
- 证据：`scripts/ui/map_view.gd:9-11`（每帧 `queue_redraw`）、`21-74`（`_draw` 内容）
- 改法：① 最低成本：`_process` 里改成每 0.2s（5Hz）或玩家移动 >0.5m 才 redraw；② 更彻底：静态底图一次性画进 `ImageTexture`，之后只画玩家点
- 预期收益：打开地图时 CPU/UI 重绘成本降 >80%
- 风险：低
- 工作量：S（限频）/ M（底图缓存）

## 8. 雾片降频 + 删两段死代码

- 问题：每帧改 4 张雾片材质颜色；`_lantern_lights` 永远是空数组（`_build_stone_lantern` 从未被调用）
- 证据：`scripts/world/world_builder.gd:83-101`（`92-98` 改材质、`99-101` 空转）、`580-598`（死函数）、`855-857`（每片 `duplicate()` 材质）
- 改法：雾片透明度改 5~10Hz 更新，或改 instance uniform 共享材质；删除 `_build_stone_lantern` 与 `_lantern_lights` 相关代码（要灯笼再单独接线并遵守「每视图点光 ≤8」预算）
- 预期收益：每帧 4 次材质更新 → 接近 0；少 3 份材质
- 风险：低
- 工作量：S

## 9. 锁 30fps

- 问题：工程约定 30fps 目标，但 `project.godot` 没有 `max_fps` → 60/120Hz 屏跑满刷新率，费电发热，温控预算被吃掉
- 证据：`project.godot:5-11`（`[application]` 段无 `run/max_fps`）
- 改法：`[application]` 下加 `run/max_fps=30`（画质分档时用 `Engine.max_fps` 动态改）
- 预期收益：功耗/温度/帧稳定性；风险：低
- 工作量：S（1 行）

## 10. 地面细分 92×92 → 48×48

- 问题：地面 ≈17k 三角，且是单张 92×132m 无 LOD 大网格；启动时 8649 个顶点逐点算色
- 证据：`scripts/world/world_builder.gd:298-301`（`subdivide_width/depth = 92`）、`313-333`（逐顶点上色）
- 改法：两个细分值改 48；颜色算法不动
- 预期收益：每帧少 ≈12k 三角 + 启动时间小幅下降
- 风险：低（颜色噪声尺度约 2m，肉眼差异小；对一张截图确认）
- 工作量：S（2 个数字）

---

## 附：第 11 项（最大收益，但工作量 M~L，需单独排期）

**静态建筑按材质合并（A1）**：`world_builder.gd:173-181` 的 `_add_mesh` 每次 new 一个 MeshInstance3D（约 250 个，且默认全部投影），是 draw call 破 300 预算的主因。
做法：`SurfaceTool.append_from(mesh, transform)` 按材质累积 → 每材质 1 个 MeshInstance3D；小装饰 `cast_shadow=OFF`。
预期：主 pass ≈250 → ≈35 draw call，加阴影 pass 总量降 ≥50%。风险：中（视觉需逐张对比），工作量 M~L。建议在 Top 10 之后做。
