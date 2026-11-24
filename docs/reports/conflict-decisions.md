# 第八轮：27 个冲突文件逐个裁决（Grok Bot fe@04e2275 ← master）

逐个 diff 了清单上全部同名冲突文件（清单实际点名 25 个路径；全量 same-path 扫描又发现 3 个
清单外差异：`world_builder.gd`、`test_idle_breath.gd`、`ui_tests.gd`，一并覆盖）。
逐文件的分析底稿见 `/tmp/conflict-diffs-draft.md`（本轮会话产物），本文是裁决与执行记录。

裁决口径：
- 主线引用 open_world / encounters / game_clock / hidden_quest / npc_db / cultivation，
  它那边没有 → 引用它的版本直接编译失败，只能丢弃或混合。
- 用户反馈优先：走路连贯、对话点击推进、人物立体（少侠感）、场景纵深。
- 吸收以「成套」为单位（见文末约束），吸收一项跑一次测试。

## 裁决总表

| # | 文件 | 裁决 | 本轮执行 |
|---|---|---|---|
| 1 | world/foot_lock.gd | **吸收（整体）** | ✅ 已换为它的鞋底级锁定+两骨 IK 版 |
| 2 | tests/test_foot_lock.gd | **吸收（整体）** | ✅ 与上成对（5 角色 × physics tick × 鞋底滑移） |
| 3 | world/tassel_hang.gd | **吸收（整体）** | ✅ 惯性滞后 + J 形逐段下垂流苏 |
| 4 | world/character_anim.gd | **混合** | ✅ 吸收拔剑缓降/过肩弧线/入鞘手引导/跪地定格/三段流苏 |
| 5 | world/idle_breath.gd | **混合** | ✅ 吸收真跪姿/伸手向柄/down 时序；保留我们的呼吸幅度 |
| 6 | world/sheath_follow.gd | **混合** | ✅ 吸收实测 HILT/TIP 映射（已用 dump_sword 复核） |
| 7 | battle/battle_stage.gd | **吸收（仅机位）** | ✅ 3/4 后方机位 (2.18,1.46,2.68) fov46 |
| 8 | ui/dialogue_panel.gd | **混合** | ✅ 只搬 PORTRAIT_FALLBACKS 五条 v3 路径 |
| 9 | ui/battle_panel.gd | **混合** | ✅ 搬 _fit_log_min_height + 空 result_row 隐藏 |
| 10 | tests/ui_tests.gd | **混合** | ✅ FE-UI-004 与上成对 |
| 11 | shaders/toon_char.gdshader | **混合** | ✅ 吸收 hole_grow+肤色细化；保留 albedo_gain 与雾 |
| 12 | shaders/toon_char_front.gdshader | **混合** | ✅ 吸收肤色细化；保留 albedo_gain 与雾 |
| 13 | world/toon_model.gd | **混合** | ✅ 搬 hole_grow_for（shenyan=0）+ BackPatch 染色 |
| 14 | world/npc.gd | 丢弃 | 它是 CharacterModel 之前旧版，吸收即 main/open_world 编译失败 |
| 15 | world/player.gd | 丢弃 | 缺 normalize_move_input/.character/set_region_tint；且无加减速斜坡（正是「起步/停步」要的反面） |
| 16 | world/player_camera.gd | 丢弃 | 我们机位有屏高验收指标 + CLI A/B 工具链 |
| 17 | world/toon_model.gd 主体 | 丢弃 | 场景缓存/优化器/归一化是管线本体，npc/character_model/main 都依赖 |
| 18 | ui/hud.gd | 丢弃 | 它缺修为显示、quest 面板常显与开放世界决策相反；CLAUDE.md 里 hud.gd:100 立绘缺失是旧信息（文件在、且有 exists 兜底） |
| 19 | autoload/dialogue_db.gd | 丢弃 | 它指向 res://assets/portraits/，该目录我们树里没有 |
| 20 | autoload/game_state.gd | 丢弃 | 它缺整块成长/修为/背包系统 |
| 21 | project.godot | 丢弃 | 它缺 4 个 autoload + 中文字体 + icon |
| 22 | scenes/main.gd | 丢弃 | OpenWorld/机缘/隐藏分支硬依赖；仅 _rec_slow_warned 记录为可选后置 |
| 23 | scenes/render_captures.sh | 丢弃 | 我们的 lavapipe→OpenGL 回退是本机实测必需 |
| 24 | tests/run_all.sh | 丢弃 | 它删了 movement/open_world 两行测试 |
| 25 | README.md | 丢弃 | 0.1 时代旧状态 |
| 26 | ui/ui_theme.gd | 丢弃 | 3 个纯口味常量（panel alpha/圆角/行距） |
| 27 | ui/virtual_joystick.gd | 丢弃 | 死区 0.20 与 player/test 是一套，改 0.15 破坏一致 |
| 附1 | world/world_builder.gd | 丢弃（冲突本体） | 唯一差异是石灯幢 r4→r4b 贴图引用；本轮我们独立做了同一替换（美术评审结论一致），另有本轮新增的画稿场景系统 |
| 附2 | tests/test_idle_breath.gd | 丢弃 | 我们多一行 ToonModel.clear_scene_cache() 修复 |
| 附3 | tests/ui_tests.gd 已并入 #10 | — | — |

## 关键理由摘要

### 吸收的四个理由
1. **foot_lock（#1/#2）**：我们旧版只钉脚踝，屏幕上脚尖仍拖地；它从 rest 原点每帧重建 +
   鞋底接触点 + 大小腿两骨 IK，是「走路不滑步」的最大单项升级。API 与我们 CharacterAnim
   完全兼容；它的 test 严格更强（5 角色、physics tick 驱动、鞋底 ≤2cm、触地帧数下限）。
2. **流苏/剑（#3/#4/#6）**：tassel_hang 的惯性滞后 + 逐段下垂直接命中「布料摆动」；
   `_lerp_sword` 过肩弧线让拔剑不穿腰；sheath_follow 的 HILT/TIP 实测几何纠正了我们旧注释
   里自相矛盾的枢轴（已用 tools/dump_sword.gd 在本地复核过网格轴）。
3. **跪姿/拔剑手（#5）**：跪姿髋 0.74→0.44 修「像坐地」，伸手向量修「手够不到剑柄」，
   都是可见缺陷；呼吸幅度是我们自己的校准，保留。
4. **机位（#7）**：3/4 后方位角让角色填满 HUD 上方、倒地者脚部不贴 HUD，单函数可回滚。

### 丢弃的两个代表性理由
1. **编译失败类**（npc/player/dialogue_db/game_state/project.godot/hud/main）：它那边
   没有 open_world/encounters/成长系统，吸收即挂；这些「缺失」正是主线权威性的来源。
2. **决策相反类**：battle_panel 的 UPDATE_ALWAYS（30fps 预算回退）、toon shader 的
   fog_disabled（第三轮刻意留雾做纵深）、hud 的 quest 常显（开放世界无强制任务）——
   它们不是错，是旧决策；按 BRIEF 与 PERF DECISION 保留我们的。

## 吸收的成套约束（本轮已按此执行）
1. foot_lock 套：foot_lock.gd + test_foot_lock.gd + character_anim 的树优先级 +
   idle_breath 的 `_process(40)` 时序——否则两套写骨骼的时序混跑。
2. 流苏套：tassel_hang.gd + character_anim `_ensure_tassel` + sheath_follow 实测映射。
3. shader 套：hole_grow + 肤色细化 + toon_model `hole_grow_for`（shenyan=0），
   保留 albedo_gain（四处 set 暗模补光）与雾（纵深决策）。
4. battle_panel 套：_fit_log_min_height + _result_row.visible + ui_tests FE-UI-004。
5. 对话套：PORTRAIT_FALLBACKS 只换常量表；`advance()` 与 FakePanel 兼容写法不动。

## 后置（记录，不阻塞）
- shaders/toon_char_front 的 gutter 放宽（`speckle && (uv_edge || lum<0.88)`）：可能把
  浅灰布纹刷成 robe fill，需要截图 A/B 再定，本轮未吸收。
- main.gd 的 `_rec_slow_warned`（录像慢 tick 警告）：只在 --fixed-fps 录制流程下有意义。
- ui_theme 三个常量：下次美术 pass 时截图对比后再定。
