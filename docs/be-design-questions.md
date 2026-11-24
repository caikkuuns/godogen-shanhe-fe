# 需要策划拍板的清单（后端现状）

本文从 `docs/be-decisions.md` 中抽出需要策划/剧情确认的条目。每条先写**当前默认做法**；未拍板前后端按该默认值运行，不阻塞开发。

## DQ-01 第一章支线 `locked` 是否算 `available`

- **step9 状态**：保持（策划同意）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：选段前统一执行 `GameState.normalize()`。第一章主线 `accepted` 且支线 `locked` 时，支线会先被归并为 `available`，于是 `bc_zhou_invite` 会被选中。
- **与验收冲突**：`acceptance-v1.md` 的 DLG-025(a) 把 `accepted + locked` 视为“支线非 available”，期望不选 `bc_zhou_invite`。当前测试按归并后的结果断言。
- **需要拍板**：维持“先归并再选段”（当前默认），还是让 DLG-025 的注入状态绕过归并。
- **位置**：`scripts/autoload/game_state.gd` 的 `normalize()`；`docs/be-decisions.md` §9。

## DQ-02 `zmo_05` 新台词与旧验收文本

- **step9 状态**：保持（策划同意）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：`zmo_05` 使用新文本「他砍两刀便要蓄一回力，见他握紧刀柄，下一刀就是重的。」
- **冲突**：`acceptance-v1.md` DLG-023 仍写旧版（含重复的“见他握紧刀柄就当心”）。
- **需要拍板**：确认新文本，并让 QA 更新验收用例；后端不改 `zmo_05`。
- **位置**：`data/dialogue-v1.json`、`docs/dialogue-v1.json`；`tests/run_tests.gd` DLG-023。

## DQ-03 E1/E2/E3 的战斗文案与敌人显示名

- **step9 状态**：保持（战斗文案同意）；两个新角色定名 待用户定（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**（由后端暂定）：
  - E1 `ch2_thug`：重击「药行打手抡棍横扫！」；开场「药行打手拎着短棍逼上来。」
  - E2 `ch2_gesancheng`：重击「葛三秤抡起秤砣横扫！」；开场「葛三秤把秤砣在掌心掂了掂。」
  - E3 `ch2_liheng_spar`：沿用第一章蓄力/重击文案；开场「厉横横刀一立：‘这回换个砍法。’」
  - 显示名：药行打手、葛三秤、厉横（切磋）。
- **需要拍板**：以上文案是否可用；新角色名是否定为“药行打手”“葛三秤”。
- **位置**：`scripts/battle/battle_data.gd` 的 `BATTLES`。

## DQ-04 支线奖励占位 A/B 的内容与文案

- **step9 状态**：保持（策划同意）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：只做文本/回执，不给数值。
  - `side.ch2Spar/settle` → 回执 `ch2Spar.v1.reward`，提示「再领一刀」。
  - `side.ch2Tea` 完成 → 回执 `ch2Tea.v1.reward`，提示「一碗粗茶」。
- **需要拍板**：奖励是纯文本、道具占位，还是给数值；回执 ID 与提示文案是否沿用。
- **位置**：`scripts/autoload/game_state.gd` 的 `dispatch_quest_event()`。

## DQ-05 奖励提示与一致性保存的先后

- **step9 状态**：已落地（step9：存档成功才算结算，失败回滚、可重试）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：任务状态机在 `ready→completed` / 支线结算时立即设置回执并发 `reward_granted`。存档由场景在对话 `finished` 后调用 `GameState.save_game()`。
- **风险**：如果场景在保存失败前就弹出奖励提示，会出现“提示已发但档没落”的观感。
- **需要拍板**：是否要求 UI 等保存成功后再弹提示（当前后端只能提供 `reward_granted` 与 `finished` 两个信号，顺序由场景决定）。
- **位置**：`scripts/autoload/game_state.gd` 的 `dispatch_quest_event()`；`scripts/dialogue/dialogue_runner.gd` 的 `finished`。

## DQ-06 纸面战斗模拟与实测差异

- **step9 状态**：已落地（step9：数值不动，BAT-022 守势策略加“能击杀先击杀”，实测 8 回合 / 45 血）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：测试 `BAT-022` 实测：
  - 读招守势流：9 回合剩 30 血（策划稿纸面：8 回合剩 45 血）。
  - 不守硬打流：7 回合剩 29 血（与纸面一致）。
- **需要拍板**：是否接受当前数值，或调整 E2/E3/主角数值后重跑；纸面值不作为通过判定。
- **位置**：`scripts/battle/battle_data.gd`；`tests/run_tests.gd` BAT-022。

## DQ-07 第一章支线未收完时第二章是否继续等待

- **step9 状态**：已落地（step9：对话 v1.1 并行，周伯先给第二章委托，新增 ch2_gate_girl_bc_meet，M2 已相识版条件放宽）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：按策划稿 Q6，周伯列表先放 `zhou_side_pending_girl/monk`，第一章支线仍在 `accepted/girlMet/bothMet` 时，第二章委托不在周伯处开启；主线交付后归并才把 `main.ch2Herbs` 置为 `available`。
- **需要拍板**：维持“先收支线”（当前默认），还是接第二章时强制把第一章支线 `legacyClosed`（会丢奖励，不建议）。
- **位置**：`data/chapter2-dialogue.json` 的 `interactionPoints["village.zhoubo"]`；`scripts/autoload/game_state.gd` 的 `normalize()`。

## DQ-08 E3 切磋失败的惩罚

- **step9 状态**：保持（策划同意）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：无惩罚。失败后 `restore_snapshot()` 恢复我方进场生命/药/内力，不设置胜利标记、不推进支线；可再次挑战。
- **需要拍板**：确认“切磋失败无惩罚”；若要有惩罚，需要新增规则与 UI。
- **位置**：`scripts/battle/battle_logic.gd` 的 `restore_snapshot()`；`data/chapter2-dialogue.json` 的 `ch2_spar_offer`。

## DQ-09 胜利自动存档、失败/撤退不存档

- **step9 状态**：保持（策划同意）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**（本轮默认）：
  - 胜利返回探索：`GameState.leave_battle(id, true)` → 写 `battle.<id>.won` 并立即原子存档。
  - 失败/撤退返回：`leave_battle(id, false)` → 清 `in_battle`，**不写存档**；进战前存档内容保持不变。
  - “再战”留在战斗内，不写档。
- **需要拍板**：是否接受“胜利即自动存档”；失败/撤退是否也允许玩家手动存档（当前只禁止战斗中途保存）。
- **位置**：`scripts/autoload/game_state.gd` 的 `leave_battle()`；`docs/be-needs.md` 战斗节。

## DQ-10 `dlg.ch2.lihengVouched` 在第三章的用途

- **step9 状态**：待用户定（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：M4 选择“我替你作保”时在结束节点写 `dlg.ch2.lihengVouched = true`，随存档保存；第二章不读它。
- **需要拍板**：第三章是否据此改变厉横相关分支/台词；若需要别的标记名或额外数据，先定契约。
- **位置**：`data/chapter2-dialogue.json` 的 `ch2_fn_09`；`scripts/autoload/game_state.gd` 的 `default_flags()`。

## DQ-11 第一章主线 `unknown` 时第二章的可见性

- **step9 状态**：保持（策划同意）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：第一章主线不可读时，`main.ch2Herbs` 也返回 `unknown`，相关条件全部按假处理，玩家只会看到兜底对话。
- **需要拍板**：确认“第一章坏档不推测第二章进度”；或改为直接隐藏第二章交互点。
- **位置**：`scripts/autoload/game_state.gd` 的 `get_quest_state()`。

## DQ-12 第二章新台词与角色名审校

- **step9 状态**：待用户定（数据已同步 v1.1；台词审定与定名未动）（依据 `/workspace/wuxia-team/plan/be-dq-answers.md`）

- **现状**：`data/chapter2-dialogue.json` 为策划稿原样复制，32 段 / 96 节点，`source` 标记为待审；新角色名“葛三秤”“药行打手”仍是拟名。
- **需要拍板**：剧情侧审完全部新台词；确定角色名后同步 `speakers`、美术文件名与 UI。
- **位置**：`data/chapter2-dialogue.json`；`scripts/autoload/dialogue_db.gd`。
