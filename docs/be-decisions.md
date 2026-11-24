# 后端实现决定（对齐 acceptance-v1 的“待确认”项）

本文只确定**后端**实现细节，以当前代码为准；探索/UI 专属项不在范围内。`/workspace/wuxia-team/qa/acceptance-v1.md` 只读，未修改。

## 1. 存档路径与格式

- **结论**：单槽本地存档，路径 `user://save_v1.json`；UTF-8 JSON 文本。临时文件 `user://save_v1.json.tmp`，上一份存档保留为 `user://save_v1.json.bak`。不连云存档，不做多槽。
- **写入**：先写 `.tmp` 并回读比对，再备份旧档、原子替换；替换失败会回滚。只有 `SAV-*` 的读失败不会动 `.bak`。
- **代码**：`scripts/autoload/save_manager.gd:7-8`（常量）、`:19-62`（`save_state`）、`:64-93`（`load_state`）。

## 2. 存档字段名

- **结论**：顶层字段为 `version`、`saved_at`、`flags`、`quests`、`player`。
  - `flags`：`{ "battle.liheng.won": bool, "dlg.liheng.postSeen": bool, ... }`，值必须是布尔。
  - `quests.main.zhouCommission`：主线状态字符串（`notAccepted/accepted/delivered/unknown`）。
  - `quests.side`：`{ schemaVersion: int, state: string, rewardReceipt: null | string }`。
  - `player`：`{ hp: int, potions: int, position: [x, y, z], facing: int }`。`facing` 归一化到 0–7。
- **代码**：`scripts/autoload/game_state.gd:436-469`（`to_dict`）、`:471-...`（`apply_dict`）。

## 3. 当前存档版本号

- **结论**：当前 `version = 2`，字段名 `version`，JSON 数字。仍接受版本 `1`。
- **策略**：
  - 缺失、非数字（字符串/数组/null）→ 拒绝加载，错误“存档版本字段缺失或类型错误”。
  - `< 1` → 拒绝：“不支持的存档版本”。
  - `> 2` → 拒绝：“存档版本过新”。
  - 版本 1 缺少第二章块时按默认值补齐（见第 22 节）；旧原生安卓存档格式不在本仓库范围内，按不支持处理并返回错误，不静默覆盖。
- **代码**：`scripts/autoload/save_manager.gd:9-10`、`:67-100`。

## 4. `battle.liheng.won` 就是唯一的胜利标记

- **结论**：是。战斗逻辑只产生 `BattleLogic.won`，不直接写全局状态；场景在胜利返回探索前调用 `GameState.mark_battle_won()`，把 `flags["battle.liheng.won"]` 置为 `true`。该函数幂等，第二次调用返回 `false`，不会重复切换语义或发奖。
- **只读性**：对话只能通过 `dlg.*` 命名空间写标记；`commit_dialogue_flags()` 忽略非 `dlg.` 写入并警告。
- **存档**：该标记随 `flags` 一起保存/读取。
- **代码**：`scripts/autoload/game_state.gd:137-143`（`mark_battle_won`）、`:125-135`（`commit_dialogue_flags`）；`scripts/battle/battle_logic.gd:89-90`（`is_over`）。

## 5. 战斗中不存档

- **结论**：`GameState.in_battle` 为场景拥有的运行态开关；为 `true` 时 `GameState.save_game()` 直接返回 `{"ok": false, "blocked": true, "error": "战斗中不能存档"}`，不写文件。该字段不进入存档，读档/新游戏时重置为 `false`。
- **对接**：战斗场景进入时 `GameState.set_in_battle(true)`，胜利/失败返回探索前 `set_in_battle(false)`。
- **代码**：`scripts/autoload/game_state.gd:60`、`:569-576`；重置见 `:97-115`。

## 6. 失败“再战”怎么重置

- **结论**：`BattleLogic.restart_from_snapshot()` = 完整重开一场：我方生命/药数量回到进场快照，内力回到 20，厉横生命 100，敌方循环步回到 0（第一步普攻），蓄力标记清除，回合数归零，胜负标记清除，战斗日志清空。不是只回血后接着打。
- **进场快照**：由 `BattleLogic.new(start_hp, start_potions)` 记录；不传时用 100/2。
- **“返回”**：`restore_snapshot()` 只恢复我方生命/药/内力并清除胜负与蓄力；场景回探索后重新触发战斗时应**新建** `BattleLogic`（新对象自然从开场开始）。失败路径不设置 `battle.liheng.won`，不授奖。
- **代码**：`scripts/battle/battle_logic.gd:26-58`；敌方常量在 `scripts/battle/battle_data.gd:19-26`。

## 7. 非法 `next`、缺失入口、跨段跳转

- **结论**：
  - 入口节点不存在 → 运行器中止，按取消处理：不提交任何待提交 flags/effects，面板关闭，`finished(cancelled=true)`。
  - 非 end 节点的 `next` 指向不存在节点 → 同上。
  - 跳到另一段对话的节点 → 运行器在每步检查节点 `dialogue` 是否等于当前对话 id，不等则中止（不提交、不崩溃）。
- **数据加载**：`DialogueDB.validate()` 还会静态拒绝缺失 entry/next、跨段 next、环、不可达节点；失败时清空半初始化的图。
- **代码**：`scripts/dialogue/dialogue_runner.gd:65-87`、`:138-149`；`scripts/autoload/dialogue_db.gd:144-312`、`:368-...`。

## 8. 未知条件与缺失标记

- **结论**：
  - 无法识别的条件字典 → `push_error` 后返回 `UNKNOWN`；在 `all/any/not` 里也不会变成 true，顶层按 `FALSE` 处理。
  - 缺失标记（`get_flag()` 返回 `null`）与 `equals` 比较 → `FALSE`（不是 unknown）。
  - 任务状态为 `unknown`（主线不可读）或 `disabled`（支线块损坏/版本不认识）→ 该条件为 `UNKNOWN`；顶层 `unknown` 按 `FALSE` 处理，`not(unknown)` 仍为 `UNKNOWN`。
  - 条件数组为 AND，空数组为 true。
- **代码**：`scripts/autoload/game_state.gd:368-430`（`eval_condition` / `conditions_ok`）、`:145-165`（`get_quest_state`）。

## 9. 选段前做状态归并

- **结论**：`DialogueDB.pick_dialogue()` 先调用 `GameState.normalize()`，再按交互点顺序取第一条条件为真的对话。归并规则：
  - 主线 `accepted` 且支线 `locked` → 支线 `available`；
  - 主线 `delivered` 且支线 `locked/available` → `legacyClosed`；
  - 主线 `delivered` 且支线 `bothMet` → `ready`。
  因此 DLG-037(b) 在归并后选 `bc_finale`，而不是 `zhou_side_pending_monk`。
- **与 DLG-025 的差异**：验收用例把 `accepted + locked` 当作“支线非 available”。但按上述归并，`locked` 会先变成 `available`，从而选中 `bc_zhou_invite`。实现以归并规则为准；测试对 `accepted + locked` 断言归并后的结果，并在 `docs/be-decisions.md` 记录此差异。
- **代码**：`scripts/autoload/dialogue_db.gd:215-...`；`scripts/autoload/game_state.gd:167-219`。

## 10. 对话提交时机与取消

- **结论**：待提交的 `setFlags/effects` 沿路径累积；只有到达 `end:true` 节点、并且玩家确认关闭最后一句后才一次性提交。任何取消/中止都丢弃。提交顺序固定：`setFlags` → `questEvent` → `startBattle`（后者通过 `battle_requested` 信号发出）。
- **取消方式**：`DialoguePanel` 的 Esc/返回触发 `cancel_requested`；运行器也接受任何来源的该信号。取消后 `finished(cancelled=true)`。
- **代码**：`scripts/dialogue/dialogue_runner.gd:113-149`；输入侧在 `scripts/ui/dialogue_panel.gd:230-256`（未改 UI，仅引用）。

## 11. `setFlags` 只允许 `dlg.*`

- **结论**：`commit_dialogue_flags()` 只提交 `dlg.` 前缀；其他 key 忽略并 `push_warning`。因此对话不能改写 `battle.liheng.won`。合法的 `dlg.liheng.postSeen` 正常写入。
- **代码**：`scripts/autoload/game_state.gd:125-135`。

## 12. `questEvent` 状态机映射

- **结论**：
  - `main.zhouCommission` + `accept`：`notAccepted → accepted`。
  - `main.zhouCommission` + `deliver`：`accepted` 且 `battle.liheng.won=true` → `delivered`。
  - `side.bambooCompanions` + `talkZhou`：`available` 且主线 `accepted` → `accepted`；`ready` 且主线 `delivered`、已胜利、无回执 → `completed` 并发奖。
  - `talkGirl`：`accepted` 且主线 `accepted/delivered` → `girlMet`。
  - `talkMonk`：`girlMet` → `bothMet`，随后归并。
- **奖励**：只有 `ready → completed` 的 `talkZhou` 授予“同行之约”（回执 `bambooCompanions.v1.promise`），发出 `reward_granted` 信号。战斗胜利本身不发任何奖励，也不发 `deliver`。
- **代码**：`scripts/autoload/game_state.gd:221-294`、`:14`（回执常量）。

## 13. 战斗数值、动作与预告

- **结论**：数值唯一来源是 `scripts/battle/battle_data.gd`（不是 `.tres`）：生命 100/攻击 12/防御 4、内力 30（开场 20）、药 2；厉横 100/14/2，普攻 1.0、重击 2.5。四个动作 `attack/skill/guard/potion`；无效动作返回 `ok=false`，不扣资源、不推进回合。
- **预告**：敌人固定循环 `普攻 → 普攻 → 蓄力 → 重击`，无随机。`enemy_next_action()` 给出下一步；`enemy_charging` 是蓄力标记；蓄力时 `log_lines` 追加精确文案 `厉横握紧刀柄，正在蓄力！`，重击后清除标记。
- **代码**：`scripts/battle/battle_data.gd:4-39`；`scripts/battle/battle_logic.gd:90-134`（动作可用性）、`:136-215`（回合结算与日志）。

## 14. 胜利/失败返回与位置

- **结论**：战斗逻辑不修改 `GameState.player_position`，场景返回探索时位置自然保持进战前值。胜利只追加 `battle.liheng.won`；不写 `main.zhouCommission`，不出 `questEvent deliver`。失败只设置 `BattleLogic.lost`，不碰胜利标记；“再战/返回”是 UI 两个按钮，后端分别对应 `restart_from_snapshot()` / `restore_snapshot()`。
- **代码**：`scripts/battle/battle_logic.gd:181-...`；`scripts/autoload/game_state.gd:137-143`。

## 15. 战后厉横是否离场

- **结论**：后端不删除交互点。`bamboo.liheng` 始终可查询；胜利后按数据会选 `liheng_defeated_idle`。如果场景选择隐藏 NPC，可不再调用该点，属于表现层决定；逻辑层不崩溃、不误开战。
- **代码**：数据 `data/dialogue-v1.json` 的 `interactionPoints["bamboo.liheng"]`；`scripts/autoload/dialogue_db.gd:215-...`。

## 16. 无立绘时的表现

- **结论**：`portrait_path()` 优先使用数据中非空且资源存在的 `resPath`；否则查回退表，仍不存在则返回空串。空串交给 `DialoguePanel`，只显示名字。周伯/明澄/厉横当前无源文件，返回空串。
- **代码**：`scripts/autoload/dialogue_db.gd:105-127`。

## 17. 缺失/损坏存档与缺字段

- **结论**：
  - 文件不存在 → `ok=false, missing=true`，按无档处理。
  - 空文件、截断、非法 JSON、非对象 → 拒绝，不崩溃。
  - 缺 `version` / `flags` / `quests` → 拒绝。
  - 缺 `player` 整体 → 接受，按新游戏默认值恢复（生命 100、药 2、出生点、朝向 0）。
  - `player` 内缺单个字段 → 该字段用默认值；不沿用当前会话的旧值。
  - 类型错误（版本非数字、flags 非布尔、任务非字符串、玩家数值/位置类型错）→ 整档拒绝，不半应用。
  - 读失败不会覆盖 `.bak`；`restore_backup()` 可手动恢复上一份。
- **代码**：`scripts/autoload/save_manager.gd:67-160`；`scripts/autoload/game_state.gd:471-...`。

## 18. 自动化测试范围

- 能 headless 断言的后端用例在 `tests/run_tests.gd` 中按 acceptance 编号输出（`ok DLG-001 ...`）。
- 纯 UI/画面部分（按钮置灰、立绘、头顶标记、结算界面、提示文案）不在后端测试里冒充通过；这些用例的后端逻辑仍会断言，并在测试末尾清单中标注“仅逻辑覆盖”。
- `DLG-023` 的验收文本仍是旧版 `zmo_05`；当前数据按最新要求为“他砍两刀便要蓄一回力，见他握紧刀柄，下一刀就是重的。”，测试以 `data/dialogue-v1.json` 为准。
- SAV-002 冷启动由测试进程再启动一次 `godot --headless` 子进程完成读写校验。
- 第二章新增用例以 `CH2-*` 编号输出；当前总计 123 个用例。`CH2-FLOW-001..003` 覆盖 `battle_requested` → 胜利存档、失败/撤退不写档、支线战斗与奖励。

## 19. 多对话文件加载（第二章）

- **结论**：`DialogueDB` 按顺序加载 `data/dialogue-v1.json`、`data/chapter2-dialogue.json`（`DB_PATHS`）。
  - `nodes` / `dialogues` 合并；任一文件出现重复节点或对话 ID → 加载失败，`load_error` 写明冲突 ID，并清空半成品图。
  - `interactionPoints` 同名交互点由后加载文件**整表替换**（第二章的周伯、明澄列表已经是合并后的完整列表）。
  - `speakers` 后加载文件覆盖同名项；`states` 取并集；`flagsRead` / `effectTypes` 合并。
  - 加载成功后对合并后的整图做一次校验。
- **代码**：`scripts/autoload/dialogue_db.gd:5-10`、`:36-129`、`:233-...`。

## 20. `battle_return.*` 校验豁免

- **结论**：所有 `battle_return.` 开头的交互点都允许没有兜底对话；其他交互点仍要求最后一段是无条件兜底。第二章的三个返回点因此合法。
- **代码**：`scripts/autoload/dialogue_db.gd:394`。

## 21. 第二章任务与存档块

- **结论**：
  - 新增任务：`main.ch2Herbs`、`side.ch2Spar`、`side.ch2Tea`，状态集合照策划稿。
  - 归并：第一章主线 `delivered` 时 `main.ch2Herbs` 的 `locked → available`；`main.ch2Herbs ∈ {toldByLiheng, stationCleared, completed}` 时两条支线 `locked → available`；第一章主线 `unknown` 时第二章主线按 `unknown` 处理。
  - 事件守卫与迁移：
    - `main.ch2Herbs`：`accept`（available→accepted）、`hearLiheng`（accepted→toldByLiheng，需 `battle.ch2_thug.won`）、`recoverPack`（toldByLiheng→stationCleared，需 `battle.ch2_gesancheng.won`）、`finish`（stationCleared→completed）。
    - `side.ch2Spar/settle`：available→completed，需 `battle.ch2_liheng_spar.won`；回执 `ch2Spar.v1.reward`，奖励提示“再领一刀”。
    - `side.ch2Tea`：`talkMonk` 在 available→accepted、told→completed；`talkLiheng` 在 accepted→told；完成回执 `ch2Tea.v1.reward`，奖励提示“一碗粗茶”。
  - 存档 `quests` 新增：`main.ch2Herbs`（字符串）、`side.ch2Spar` / `side.ch2Tea`（`schemaVersion/state/rewardReceipt`）。`to_dict` / `apply_dict` 读写这些块。
- **代码**：`scripts/autoload/game_state.gd:15-40`、`:145-219`、`:221-294`、`:436-...`。

## 22. 存档版本 2 与旧档兼容

- **结论**：当前存档版本升到 **2**；仍接受版本 **1**。文件名保持 `user://save_v1.json`，避免旧档找不到。版本 1 存档缺少第二章块时，`apply_dict` 用默认值补齐（第二章主线 `locked`，支线 `locked`，回执 `null`，新 flags 为 `false`），随后 `normalize()` 按第一章进度解锁。版本 `<1` 或 `>2` 拒绝；损坏/类型错误仍整档拒绝。
- **代码**：`scripts/autoload/save_manager.gd:9-10`、`:67-150`；`scripts/autoload/game_state.gd:471-...`。

## 23. 按 battleId 取战斗数据

- **结论**：`battle_data.gd` 新增 `BATTLES` 表，保留第一章常量作为 `liheng` 默认值。`BattleLogic.set_battle_id(id)` 切换档案并重开；未知 ID 返回 `false`。`mark_battle_won(battle_id = "liheng")` 现在写 `battle.<battleId>.won`，默认参数保持第一章调用不变。
- **档案**：
  | battleId | 生命/攻/防 | 循环 | 重击倍率 | 蓄力文案 |
  |---|---|---|---|---|
  | `liheng` | 100/14/2 | 普攻→普攻→蓄力→重击 | 2.5 | 厉横握紧刀柄，正在蓄力！ |
  | `ch2_thug` | 60/12/0 | 普攻→普攻→蓄力→重击 | 2.2 | 药行打手抡起短棍，正在蓄力！ |
  | `ch2_gesancheng` | 120/13/2 | 普攻→蓄力→重击→普攻→普攻→蓄力→重击 | 2.6 | 葛三秤甩开秤砣，正在蓄力！ |
  | `ch2_liheng_spar` | 100/14/2 | 普攻→蓄力→重击 | 2.5 | 厉横握紧刀柄，正在蓄力！ |
- **策划稿未写、本次定下的内容**：E1/E2/E3 的重击日志文本、开场日志文本（E1“药行打手拎着短棍逼上来。”、E2“葛三秤把秤砣在掌心掂了掂。”、E3“厉横横刀一立：‘这回换个砍法。’”）；E3 沿用第一章厉横蓄力/重击文案；E1/E2 的敌人名显示为“药行打手”“葛三秤”。奖励文案占位为“再领一刀”“一碗粗茶”。以上均在 `BATTLES` 表中。
- **代码**：`scripts/battle/battle_data.gd:46-124`；`scripts/battle/battle_logic.gd:45-...`。

## 24. 第二章战斗返回点

- **结论**：返回点按 `battle_return.<battleId>_victory` 命名：`battle_return.ch2_thug_victory`、`battle_return.ch2_gesancheng_victory`、`battle_return.ch2_liheng_spar_victory`。每个点只有一段一次性战后台词，没有兜底；胜利标记由战斗系统/场景调用 `GameState.mark_battle_won(battleId)` 写入。
- **代码**：`data/chapter2-dialogue.json` 的 `interactionPoints`；`scripts/autoload/game_state.gd:137-143`。

## 25. zmo_05 与重复提示

- **结论**：`zmo_05` 保持“他砍两刀便要蓄一回力，见他握紧刀柄，下一刀就是重的。”不动；`zmp_01` 已改为“厉横还在竹林里，当心他那口重刀。”，不再重复“见他握紧刀柄”。
- **代码**：`data/dialogue-v1.json`、`docs/dialogue-v1.json` 对应节点。

## 26. 战斗进出流程接口

- **结论**：
  - `GameState.battle_return_point(battle_id)` 返回 `battle_return.<battleId>_victory`，场景不用自己拼字符串。
  - `GameState.leave_battle(battle_id, victory, path)` 是返回探索的唯一出口：先清 `in_battle`；胜利时调用 `mark_battle_won(battleId)` 并立即 `save_game(path)`；失败/撤退时不写存档，返回 `saved=false`。
  - 胜利存档只包含 `battle.<battleId>.won` 与正常探索状态，不写战斗中途的生命/内力/循环步；战斗进度推进仍只由对话 `questEvent` 完成。
  - “再战”不调用 `leave_battle`，保持 `in_battle=true` 并调用 `BattleLogic.restart_from_snapshot()`。
- **代码**：`scripts/autoload/game_state.gd:137-170`（`battle_return_point` / `leave_battle`）；测试 `tests/run_tests.gd` 的 `CH2-FLOW-001..003`。

## 27. step9：DQ 答复落地与对话 v1.1 同步

- **对话**：`data/chapter2-dialogue.json` 与 `/workspace/wuxia-team/plan/chapter2-dialogue.json` v1.1 逐字节一致（33 段 / 103 节点）。`narrator` 按普通台词加载，新增 `DialogueDB.portrait_key()`。`zmo_05` 未改。
- **DQ-05**：结算快照 + `save_game()` 失败自动回滚，详见 be-needs.md。测试 STEP9-DQ05-001..003（成功落盘、失败回滚、失败后重试成功）。
- **DQ-06**：数值不动。BAT-022 守势策略：内力 ≥ 剑技消耗且敌血 ≤ 剑技伤害就放剑技；敌血 ≤ 普攻伤害就普攻；否则看预告守/打。实测守势 8 回合 / 45 血（与纸面一致），硬打 7 回合 / 29 血，测试断言 8/45。
- **DQ-07**：并行。数据层：周伯第二章委托在 `zhou_side_pending_*` 前，新增 `ch2_gate_girl_bc_meet`，M2 已相识版条件放宽到 girlMet / bothMet / ready / completed，不强制 legacyClosed。测试 STEP9-DQ07-001/002（支线停在 accepted / girlMet 时两条线都能完成）。
- **DQ-10 / DQ-12 / 两个新角色定名**：未动，待用户定。

### 同步清单（be-dq-answers.md 附录）
1. 对话同步 v1.1：**已做**。
2. `narrator` 黑屏旁白：**后端已做**（普通台词加载 + `portrait_key()`），黑屏表现**未做**，属于前端/场景（be-needs.md）。
3. 葛三秤离场、林照晚竹林→山门：**后端已做**可见性查询 `is_point_visible()` 和测试 STEP9-VIS-001；场景接线**未做**（scripts/world 不归后端）。
4. DQ-05 后端回滚**已做**，场景“存档成功再弹提示”**未做**（scripts/ui）；DQ-06 BAT-022 策略**已做**。
5. QA 更新 DLG-023 / DLG-025(a)：**未做**，属于 QA 用例文档，不归后端。

## 28. step9 QA 补测（测试回报缺口）

- `SaveManager.test_fail_stage`（仅测试用故障注入，`"readback"` / `"rename"`，单次消费）。正常运行时为空串，不影响存档流程。
- 新增 STEP9-DQ05-004：ch2Spar 失败回滚 + 重试；rename 失败、回读失败两条路径都回滚结算、不改正式存档、不留 `.tmp`，重试可成功。
- BAT-022 补断言硬打 7 回合 / 29 血；DLG-023 补“zmo_05 处取消不提交”；DLG-025(a) 点名断言 bothMet / ready / completed / disabled 不选 `bc_zhou_invite`。
- 策划副本 `/workspace/wuxia-team/dialogue-v1.json` 已同步为后端 `data/dialogue-v1.json`（zmo_05、zmp_01 两处文本），旧版备份为 `dialogue-v1.json.bak-20261116`。master 的 `docs/dialogue-v1.json` 未动，合并 be 时自然更新。

## 29. step10：第三章后端

- **对话**：`data/chapter3-dialogue.json` = 策划 v1.1（28 段 / 79 节点），加入 `DB_PATHS`。合并后总计 84 段 / 230 节点，DLG-001 / CH2-DLG-001/002 的总数断言随之更新（子章节数断言不变）。
- **存档版本 3（Q8 后端定）**：新增三个任务块，读档时 v1/v2 缺块按默认值补齐即迁移；`SaveManager` 校验 ch3 块类型。理由：版本号区分“这份档可能有第三章块”，老版本游戏读到 v3 会明确拒绝而不是静默丢进度。测试 CH3-SAVE-001/002。
- **任务**：`main.ch3Hermitage`（accept / clearStair / holdGate / finish，守卫照策划；ch2 completed 时 locked→available；ch2 unknown 时为 unknown）、`side.ch3Debt`、`side.ch3Herb`（gateHeld 起解锁，holdGate 后立即归并）。奖励只发文本 + 回执，沿用 DQ-05 快照回滚。
- **战斗**：三条档案按 §2.2，循环每拍可选 `log`（§2.5 方案 A），第一、二章档案未改。纸面模拟实测（CH3-BAT-004）：E1 读招 6 回合/68 血、硬打 5/60、旧习惯 6/52；E2 10/33、9/9、10/15；E3 8/52、7/29、8/34，**与策划设计值完全一致**。
- **显隐修正**：第二章 `gate.linzhaowan` 去掉 toldByLiheng（她跟沈砚去了驿亭），保证每个角色同一阶段只在一处。副作用：`ch2_gate_girl_go`（条件 toldByLiheng，只在山门）不会再被看到，待策划决定删除或改到别处。
- **场景侧（未做，归前端）**：地图北扩、NPC 显隐接线、5 处黑屏旁白、奖励提示时机，见 be-needs.md。

## 30. 对话同步 v1.2（删除 ch2_gate_girl_go）

- 策划定：删掉 `ch2_gate_girl_go` / `ch2_gg_01`（导航信息已在 `ch2_lt_07`、`ch2_lp_01` 交代）。`data/chapter2-dialogue.json`、`data/chapter3-dialogue.json` 与 plan 目录 v1.2 逐字节一致；第三章 `gate.linzhaowan` 合并列表同步去掉该 ID。
- 第二章 32 段 / 102 节点，合并总数 83 段 / 229 节点；DLG-001、CH2-DLG-001/002 断言相应更新，CH3-DLG-001 增加“该对话/节点已不存在、列表不引用”的断言。`is_point_visible` 规则不变。

## 31. 存档未知字段与显隐表（测试回报 ad366b1）

- **未知字段**：规则定为“不得静默丢弃”。`apply_dict` 收集各层未知键，`to_dict` 在已知字段之外原样写回（已知字段优先）。测试 STEP10-SAVE-001（顶层 mystery、quests.side.unknown、side.ch2Spar.note、未知任务块 side.ch4Future、player.gold、未知 flag 全部保留；新游戏清空）。
- **迁移断言**：STEP10-SAVE-002：v1 → v3 第三章全部默认值（状态、回执、schema、flag），再存为 v3；v4 被拒绝后文件字节不变、不生成 .bak、内存状态不变。
- **显隐**：选“未列出即隐藏 + 断言数据里每个交互点都已列出”两者都做（最安全）。林照晚 / 厉横改为单一站位函数推导，任何（包括不一致的）状态组合下都只在一处；第三章站位要求第二章 completed。STEP10-VIS-001 改为完整期望表（17 行 × 13 点），拆开 `ch2_gesancheng.won` 与 `ch3_chutie.won`，对 7×7 状态 × 8 种 flag 组合做“一人一处”穷举，去掉 combos>0 弱断言。

## 32. 存档往返细节（测试回报 8e37b4c）

- 写回未知字段时，整数值的浮点数（Godot JSON 读入都是 float）还原成 int，`3` 不会变成 `3.0`；键顺序首次重排可接受。
- STEP10-SAVE-001 改为真正二次、三次存档并比较字节（去掉 saved_at 行），并断言未知整数（gold、note、mystery 内数组）以整数写出。
- `apply_dict()`：player 下 hp / potions / facing / position 类型错误时 `push_warning` 并返回 false（仍用默认值继续），不再静默通过；`load_state()` 的校验拒绝行为不变。
- CH3-DLG-001 标题改为 v1.2，并断言第二、三章 `contentVersion` 为 `chapter2-dialogue-v1.2` / `chapter3-dialogue-v1.2`。
