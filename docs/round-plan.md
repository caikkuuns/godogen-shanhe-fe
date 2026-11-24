# 本轮改造计划：2.5D 人物 + 3D 建筑 + 开放世界

> 依据：本轮任务提示 > `BRIEF.md` > 其它旧文档。硬约束：现有 145/145 测试不退、
> Mobile + 30fps + 3D scale 0.75、禁用 SSAO/SSR/SDFGI/体积雾、只改本目录。

## 0. 资产现状
- `docs/ref-characters-v2/`：沈砚/林照晚 8 方向 idle + walk（420×500，锚点 210,476，
  pixel_size 0.00386）。注意包内单帧有缺失：沈砚有完整 `walk_sheet`（4 列×8 行），
  林照晚只有部分单帧；缺帧按同方向最近帧/已有 idle 回退。
- `docs/ref-characters-v3/`：周伯/明澄/厉横 idle（正方向，周伯/明澄另有 v3b 斜向），
  以及 v2/v3 立绘。NPC 散人复用这些 idle；游走不伪造 walk 帧。
- 全程 **不做运行时镜像**；沈砚 walk 播 0-1-2-1。
- `hud.gd`/`dialogue_panel.gd` 的 v3 立绘路径已改为真实存在的 v2/v3 文件。

## 1. 模块划分 / 新增文件

### 数据（data/）
| 文件 | 内容 |
|---|---|
| `regions.json` | 240×240 世界、60m 分块、8 个具名区块 + 8 个远岭块、路网、POI 坐标、区块色板 |
| `encounters.json` | 机缘池：id/kind/rarity/weight/region_tags/level_band/trigger/payload/cooldown_minutes |
| `npcs.json` | 姓氏/名字字典、身份模板（村民/商贩/游侠/樵夫/道士/说书人/神秘老人）、3 套性格台词、立绘映射 |
| `hidden-dialogues.json` | ≥6 条隐藏触发，覆盖 ≥3 种身份；条件 + 台词 + `dlg.hidden.*` flags |
| `growth.json` | 1→20 级修为曲线、境界名 |

### 自动加载（scripts/autoload/）
| 文件 | 职责 |
|---|---|
| `game_clock.gd` | 游戏内时间（24 分钟刷新用）、昼夜时段、天气（clear/mist/rain） |
| `encounter_db.gd` | 机缘权重抽取（common 70%/rare 25%/legendary 5%）、每区传奇上限 1、冷却/刷新、已用记录 |
| `npc_db.gd` | 模板池组合、确定性去重、18 个 NPC 分布到区块 |
| `hidden_quest_db.gd` | 隐藏分支条件求值（对话次数/持有物/声望/时段/天气/附近机缘状态），只产出 flags |

`GameState` 只新增成长与轻量进度字段（cultivation/level/inventory/reputation/talk_counts），
沿用现有存档 v3 结构，避免破坏 145 个验收用例；新字段缺失时按新游戏默认值迁移。

### 世界（scripts/world/）
| 文件 | 职责 |
|---|---|
| `open_world.gd` | 新主世界：环境/灯光/相机/玩家/地块管理/NPC 分布/区块色板调制 |
| `chunk_builder.gd` | 60m 高度场 ArrayMesh、路面着色、草丛/石子/落叶/水洼 MultiMesh、区块碰撞 |
| `building_factory.gd` | 村舍/门楼/山门三套 3D 建筑（起翘檐、瓦楞、木柱、门窗、台阶、灯笼）+ canvas 程序纹理 |
| `sprite_sheet.gd` | 现有 4 方向帧表、walk 0-1-2-1、8→4 方向映射、像素尺寸/脚底锚点 |
| `encounter_manager.gd` | 机缘点位/提示/主键触发/结果结算；记录跨区块保留 |
| `region_decor.gd` | 区块 POI（竹林、田埂、溪谷、断崖、废祠、野岭）程序化摆放 |

保留 `world_builder.gd` 与旧 GLB/动画脚本（战斗、旧测试还在用），但主场景改为
`open_world.gd`；旧 GLB 不再被探索角色引用。

### UI / 画面
- `PlayerCamera`：pitch ≈ -42°，FOV 46~50，距离 14m，0.12s 阻尼。
- `UiTheme`：墨底 alpha 0.72、金边、圆角 18、行距拉开；任务追踪面板不再显示
  （开放世界无强制任务列表），状态栏增加“修为/境界”。
- `hud.gd` 头像改用存在的立绘；`dialogue_panel.gd` 兜底表改到现有立绘。
- `open_world.gd` 内建 WorldEnvironment（Filmic/glow/depth fog/height fog/adjustment）
  与 1 主光 + 1 补光；`shaders/ink_post.gdshader` 做暗角 0.15 + 颗粒 0.015。

## 2. 关键数据结构
- 分块：`Vector2i(col,row)` → `Chunk` 节点；每帧只保持玩家周围 3×3；离开立即
  `queue_free`，进入时按需生成。已用机缘记录保存在 `EncounterManager`，不随区块卸载丢失。
- 机缘：`{id, kind, rarity, weight, region_tags, level_band, trigger, payload, cooldown_minutes}`。
- NPC：`{id, name, identity, personality, sprite, tint, portrait, region, home, radius}`。
- 隐藏条件：AND 字典；未知条件视为不命中；命中后只 `GameState.set_hidden_flag("dlg.hidden.*")`。

## 3. 优先级 / 执行顺序
1. 数据 + autoload（可单测）
2. 开放世界分块 + 相机 + 地面细节
3. 机缘系统 + 交互
4. NPC 多样性 + 隐藏触发
5. 成长曲线
6. Sprite3D 人物 + 3D 建筑 + 画质/UI
7. 新测试接入 `run_all.sh`，两轮截图迭代
8. README / REPORT / 提交

## 4. 风险点
- **旧测试依赖旧脚本**：不删除 `world_builder.gd`、GLB、`character_anim.gd`，只改探索入口。
- **分块与物理**：每块用 `ArrayMesh.create_trimesh_shape()`，避免高度场缩放兼容问题；
  区块卸载时物理体一并 `queue_free`。
- **MultiMesh 预算**：每块 ≤ 320 个地面实例，3×3 同时 ≤ 2880，低于 3000。
- **软件 Vulkan 截图慢**：优先保证 960×540 下三张图稳定输出；画面迭代以两轮为准。
- **存档兼容**：新字段只加在 `player` 字典，读取失败回默认；不改 `SaveManager.VERSION`。
- **素材缺口**：v2/v3 不存在是硬事实，不伪造路径；在 README/REPORT 标注替换点。
