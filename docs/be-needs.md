# 后端需要的场景/UI 接口

本文件只记录 `scripts/battle`、`scripts/dialogue`、`scripts/autoload` 与场景/UI 之间需要对接的内容；后端不直接改 `project.godot`、`scenes/`、`scripts/world`、`scripts/ui`。

## Autoload

`project.godot` 已注册，无需改动：

- `SaveManager` → `scripts/autoload/save_manager.gd`
- `GameState` → `scripts/autoload/game_state.gd`
- `DialogueDB` → `scripts/autoload/dialogue_db.gd`

## 对话

`DialogueDB` 自动加载 `data/dialogue-v1.json` 与 `data/chapter2-dialogue.json`；交互点 `village.zhoubo` / `village.mingcheng` 以后加载的第二章完整列表为准。

场景侧需要：

1. 放置一个 `DialogueRunner`（`scripts/dialogue/dialogue_runner.gd`），并把现有的 `DialoguePanel` 绑定进去：
   ```gdscript
   dialogue_runner.bind(dialogue_panel)
   ```
2. 与 NPC 交互时：
   ```gdscript
   var dlg := DialogueDB.pick_dialogue("village.zhoubo")
   if not dlg.is_empty():
       dialogue_runner.start(dlg)
   ```
   `pick_dialogue()` 会先跑一次 `GameState.normalize()`，再按交互点顺序取第一个条件为真的对话；没有匹配返回 `{}`。
3. 监听提交结果：
   ```gdscript
   dialogue_runner.finished.connect(_on_dialogue_finished)       # (effects, cancelled, reward_count)
   dialogue_runner.battle_requested.connect(_on_battle_requested) # (battle_id)
   ```
   `battle_requested` 只在整段对话成功走到 `end` 节点后发出，顺序固定为：`setFlags` → `questEvent` → `startBattle`。场景只需在收到 `battle_requested` 时进入战斗；不要再用 `finished` 里的 effects 重复开战。
4. 中途取消（Esc、切后台等）时 `finished` 的 `cancelled` 为 `true`，所有待提交标记和 effects 都已丢弃。`DialoguePanel` 已在取消时补发 `line_done` / `choice_selected(-1)`，场景不要额外补发。
5. 对话本身不写任务状态，只发 `questEvent`；奖励提示由 `GameState.reward_granted` 信号负责。

## 战斗

`BattleLogic`（`scripts/battle/battle_logic.gd`）是纯 `RefCounted`，不依赖场景：

```gdscript
var battle := BattleLogic.new()          # 默认 liheng
battle.set_battle_id("ch2_thug")         # 也可用 ch2_gesancheng / ch2_liheng_spar
battle.enemy_next_action()               # "attack"/"charge"/"heavy"，用于预告
battle.enemy_charging                    # 蓄力标记（头顶/日志）
var result := battle.take_turn("guard")  # attack/skill/guard/potion
```

场景进出流程（`battleId` 来自 `DialogueRunner.battle_requested`）：

```gdscript
# 进入：接住 battle_requested
GameState.set_in_battle(true)
var battle := BattleLogic.new()
battle.set_battle_id(battle_id)

# 胜利返回探索：清 in_battle + 写 battle.<id>.won + 立即存档
var exit := GameState.leave_battle(battle_id, true)
# exit.return_point == "battle_return.<battleId>_victory"

# 失败/撤退返回探索：不写存档
GameState.leave_battle(battle_id, false)

# 失败后「再战」：保持 in_battle=true，不播战前对话
battle.restart_from_snapshot()
```

- `leave_battle()` 胜利时调用 `mark_battle_won()` 并保存完整探索状态；失败/撤退只清 `in_battle`，返回 `saved=false`，存档内容保持进战前不变。
- “返回”使用 `battle.restore_snapshot()`，再由场景调用 `leave_battle(battle_id, false)`。
- 战斗中 `GameState.save_game()` 被 `in_battle` 拦截；不要绕过。
- 胜利不等于交付任务：不写 `main.*`、不发 `questEvent deliver`；推进仍走对话事件。

## 存档

- 存档入口：`GameState.save_game()` / `GameState.load_game()`，底层是 `SaveManager.save_state()` / `load_state()`（`user://save_v1.json`）。
- 存档带 `version` 字段（当前为 2）；版本 1 旧档仍可读，缺的第二章任务块按默认值补齐。
- 写入是原子的：先写 `*.tmp` 并回读校验，再替换正式文件；旧档保留为 `*.bak`。
- UI 已有保存按钮可直接沿用；读档成功后 `GameState` 会发出 `changed` 信号。

## 测试

```bash
godot --headless -s tests/run_tests.gd
```

覆盖对话数据/条件/分支/取消/标记提交/开战信号、战斗数值/循环/胜败/快照、存档往返/版本校验/损坏档/备份；有任何失败时退出码非 0。

## step9：旁白说话人（黑屏转场）

- 第二章 v1.1 新增说话人 `narrator`（显示名“旁白”），立绘 key `transition.fade_black`，`resPath` 为空。节点：`ch2_zc_07`、`ch2_zo_06`。
- 后端已按普通台词加载：`DialogueDB.speaker_id(node) == "narrator"`，`speaker_display_name()` 返回“旁白”，`portrait_path()` 返回空串（不报错）。
- 新接口 `DialogueDB.portrait_key(node) -> String`：返回立绘逻辑 key。场景可据此做表现：
  ```gdscript
  if DialogueDB.portrait_key(node) == "transition.fade_black":
      # 淡出到黑屏 + 居中显示旁白文本；点击后淡入
  ```
  不支持时按“只有名字、无立绘”的普通台词显示，流程照样走通。`main.ch2Herbs/accept` 挂在旁白节点上，转场播完才提交（chapter2.md Q13）。

## step9：奖励结算与存档（DQ-05）

奖励要等存档成功才算数，失败就回滚、可以重试。
- `dispatch_quest_event()` 结算奖励时（支线 ready→completed、`side.ch2Spar` settle、`side.ch2Tea` told→completed）先记下结算前快照，仍会发 `reward_granted(text)`。
- 新接口：
  - `GameState.has_pending_settlement() -> bool`：有未落盘的结算。
  - `GameState.pending_rewards() -> Array[Dictionary]`：`{quest, event, message}` 列表。
  - `GameState.rollback_pending_settlement() -> bool`：手动回滚到结算前（state 回到 ready / available / told，回执清空）。
- `GameState.save_game()`：
  - 成功：提交结算，清空 pending。
  - 失败（非战斗拦截）：自动回滚，返回字典多一个 `rolled_back: bool`。玩家可以再次和 NPC 对话重新结算、再存档。
  - 战斗中被拦截（`blocked`）：不回滚。
- 快照只覆盖任务状态和回执；对话中写入的 `dlg.*` 已读标记不回滚，重播时条件仍按任务状态选对话。
- 场景侧需要配合（`scripts/ui/hud.gd` 等，后端不改）：
  1. `reward_granted` 时**不要立即弹提示**，先缓存文本。
  2. 对话 `finished` 后调用 `GameState.save_game()`。
  3. `ok == true` 才弹缓存的奖励提示；`ok == false` 丢弃缓存，提示“存档失败，奖励未发放，可再次对话重试”。
  4. 对话被取消时如有 pending 结算，同样走第 2–3 步（或直接 `rollback_pending_settlement()`）。

## step9：第二章 NPC 可见性（同步清单第 3 项）

- 新接口 `GameState.is_point_visible(point: String) -> bool`，场景按它显示/隐藏 NPC 节点（建议照厉横 `set_dormant()` 的做法），未列出的交互点一律返回 true。
  | 交互点 | 可见条件 |
  |---|---|
  | `bamboo.linzhaowan` | `main.ch2Herbs` 不在 accepted / toldByLiheng / stationCleared / completed |
  | `gate.liheng` | `main.ch2Herbs` ∈ accepted / toldByLiheng / stationCleared / completed |
  | `gate.linzhaowan` | `main.ch2Herbs` ∈ accepted / completed，且 `main.ch3Hermitage` 不在 accepted…completed（step10 修正：toldByLiheng 时她已随沈砚去驿亭，只在 `yiting.linzhaowan` 出现） |
  | `yiting.gesancheng` | `main.ch2Herbs == toldByLiheng` 且 `battle.ch2_gesancheng.won` 为假（打赢后葛三秤离场） |
  | `yiting.linzhaowan` | `main.ch2Herbs` ∈ toldByLiheng / stationCleared |
- 在 `GameState.changed` 信号和读档后重新查询。

## step10：第三章（chapter3.md v1.1）

### 数据与加载
- `DialogueDB.DB_PATHS` 追加 `res://data/chapter3-dialogue.json`（与策划 v1.1 逐字节一致，28 段 / 79 节点）。`gate.liheng`、`gate.linzhaowan` 整表被第三章版本替换（已含第二章全部 ID）。
- 新交互点：`stair.dashou`、`stair.linzhaowan`、`hermitage.chutie`、`hermitage.linzhaowan`、`hermitage.wensu`，以及 `battle_return.ch3_stair_victory` / `ch3_chutie_victory` / `ch3_herb_thief_victory`（胜利返回时用 `GameState.battle_return_point(id)`）。

### 场景侧需要做（后端不改 scripts/world、scenes）
1. **地图往北扩（D5）**：北界碰撞墙现在 z≈−39（`world_builder.gd`）。往北接后山石阶（`stair.*`）和清溪庵（`hermitage.*`），把上面 5 个交互点放进去。
2. **NPC 显隐（D6）**：一律查 `GameState.is_point_visible(point)`，在 `changed` 信号和读档后刷新；用厉横 `set_dormant()` 的做法隐藏。`GameState.NPC_POINTS` 按角色列出了所有站位，同一时刻每个角色最多一个可见（测试 STEP10-VIS-001）。
   | 交互点 | 可见条件 |
   |---|---|
   | `stair.dashou` | `main.ch3Hermitage == accepted` |
   | `stair.linzhaowan` | `main.ch3Hermitage == accepted` |
   | `hermitage.chutie` | `main.ch3Hermitage == stairCleared` 且 `battle.ch3_chutie.won` 为假 |
   | `hermitage.linzhaowan` | `main.ch3Hermitage` ∈ stairCleared / gateHeld / completed |
   | `hermitage.wensu` | `main.ch3Hermitage` ∈ gateHeld / completed |
3. **黑屏旁白（D7）**：本章 5 处 `ch3_so_06`、`ch3_st_06`、`ch3_cb_02`、`ch3_hb_02`、`ch3_wf_09`，`DialogueDB.portrait_key(node) == "transition.fade_black"` 时淡出到黑屏、居中显示。不做时按普通台词也能走通。
4. **战斗**：`battle_requested` 的 id 为 `ch3_stair` / `ch3_chutie` / `ch3_herb_thief`，进出流程同第二章（`set_in_battle` → `BattleLogic.set_battle_id` → `leave_battle`）。战斗日志直接显示 `BattleLogic.log_lines`，每拍蓄力/重击日志已由后端按拍给出；头顶“蓄力”标签仍按 `enemy_charging`。
5. **奖励提示**：`side.ch3Debt`（“另一半账”）、`side.ch3Herb`（“雪见草”）同 DQ-05：缓存 `reward_granted`，对话结束后 `save_game()` 成功才弹。

### 新接口
- `BattleLogic.cycle_step_log(index) -> String`：某一拍会打出的日志（有 `log` 用 `log`，否则退回 `chargeLog` / `heavyLog`）。
- `GameState.NPC_POINTS`（常量字典）。
- 存档版本升到 **3**（新增 `main.ch3Hermitage`、`side.ch3Debt`、`side.ch3Herb`）；v1 / v2 存档仍可读，缺的块按默认值补齐，下次存档写成 v3。

## step10b：存档未知字段保留 / 显隐规则收紧

- **未知字段原样保留**：读档时顶层、`quests` 下、各任务块（side / side.ch2* / side.ch3*）内、`player` 下不认识的键都会记下，`save_game()` 原样写回；已知字段始终以当前状态为准。未知的布尔 flag 本来就保留。新游戏（`reset_new_game()`）清空。调试可用 `GameState.unknown_fields()`。
- **显隐**：`GameState.VISIBILITY_POINTS` 列出全部 13 个 NPC 交互点（含 `village.zhoubo`、`village.mingcheng` 常驻，`bamboo.liheng`）。**未列出的点一律返回 false**（并 `push_warning`），避免拼错 id 多刷出一个 NPC。
- 林照晚、厉横各由一个函数给出唯一站位：`GameState.linzhaowan_point()`、`GameState.liheng_point()`（厉横被打败且未到山门时返回空串）。`bamboo.liheng` 现在后端已经包含“打败后或到山门后离开竹林”的规则，场景里原来额外的判断可以保留也可以删。
- 第三章站位（石阶、庵）只在 `main.ch2Herbs == completed` 时出现，存档状态不一致时也不会多出 NPC。
