# FE 需要的接口 / 资源

更新：2026-11-16（fe 已合并 be `8f68830`）。已解决的旧条目已删除：战斗启动钩子（`DialogueRunner.battle_requested` + `GameState.leave_battle()` 已接线，见下）、shader/影子贴图（FE 已用内置材质与代码生成软阴影，不再需要）。

## FE 已接线（step9）

- **旁白黑屏**：`DialogueDB.portrait_key(node) == "transition.fade_black"` 时，`DialoguePanel` 淡入全屏黑底 + 居中旁白，点击后先淡出再发 `line_done`（转场播完才提交 `main.ch2Herbs/accept`）。取消时立即撤黑屏。
- **NPC 显隐**：`WorldBuilder.apply_state()` 按 `GameState.is_point_visible()` 显隐；启动、`GameState.changed`、对话结束、战斗返回后都会重新查询。新增 NPC 节点：`gate.liheng`、`gate.linzhaowan`（山门前）、`yiting.gesancheng`、`yiting.linzhaowan`（竹径北端新建「驿亭」）。第一章竹林厉横在 `battle.liheng.won` 或山门厉横出现后隐藏。隐藏的 NPC 同时关闭碰撞、退出交互组。
- **奖励与存档（DQ-05）**：HUD 缓存 `reward_granted` 文本；对话 `finished` 后 `GameState.save_game()`；`ok` 才弹「奖励 · …」，失败丢弃缓存并提示「存档失败，奖励未发放，可再次对话重试」。
- **战斗**：`battle_requested` 先记下，对话结束存档后再进战斗（`set_in_battle(true)`）。`BattlePanel`（`scripts/ui/battle_panel.gd`）驱动 `BattleLogic`：胜利 → 回写药数 → `leave_battle(id, true)` → 自动播放 `battle_return.<id>_victory` 对话；失败可「再战」（`restart_from_snapshot`）或「撤退」（`restore_snapshot` + `leave_battle(id, false)`）。

## FE 已接线（step10 / 第三章）

- **地图北扩**：北界碰撞墙从 z≈−39 移到 z≈−66。驿亭以北沿竹径铺了可走的后山石阶（约 z −37→−50，升高 1.5 m），顶端是清溪庵（白墙、黛瓦、木门，z≈−56）。
- **NPC 显隐**：新增 `stair.dashou`、`stair.linzhaowan`、`hermitage.chutie`、`hermitage.linzhaowan`、`hermitage.wensu`，一律查 `GameState.is_point_visible()`。药行打手用已有 TripoSR 模型；褚铁、闻素暂用调色后的厉横 / 周伯立绘占位。
- **旁白黑场 / 战斗 / 奖励**：沿用 step9 的通用接线。第三章 5 处 `transition.fade_black`、三场战斗 `ch3_stair` / `ch3_chutie` / `ch3_herb_thief`，以及支线「另一半账」「雪见草」的 `reward_granted`，都走现有全屏黑场、战斗面板和「存档成功才弹提示」流程，无需另开通道。

## 仍需他方提供

1. **立绘资源路径**：`dialogue_db.gd` 的 `PORTRAITS` 指向 `res://assets/portraits/*.png`，目录不存在（且被 `.gitignore` 忽略）。FE 回退到 `docs/ref-characters-v3/`。需要：改到实际路径或由资源管线生成。
2. **正文字体**：`res://assets/fonts/shanhe_serif.otf` 不存在，回退 `ThemeDB.fallback_font`。需要：字体文件或可用路径。
3. **第二章新角色美术**：葛三秤、药行打手的探索 3D 模型已接入，仍缺对话立绘。需要：立绘（或确认继续只用名字）。
4. **第三章新角色美术**：褚铁、闻素没有立绘和探索模型。探索中暂用厉横 / 周伯 idle 帧调色占位。需要：立绘 + 探索模型或 4 向 idle 帧。
5. **驿亭 / 石阶 / 清溪庵**：目前都是 FE 用方块搭建的简易场景（驿亭 z≈-33.5，石阶 z −37→−50，清溪庵 z≈-56）。如策划对位置/样式有要求请给出。
6. **战斗表现**：BattlePanel 是功能性面板（数值、预告、日志、四个动作），没有战斗场景、角色动作或特效；`ch2_*` / `ch3_*` 战斗的入场/胜利演出待美术与策划定稿。
7. **NPC 行走帧**：NPC 只有 idle 帧；若需要在场景中走动，需补 walk 帧。
