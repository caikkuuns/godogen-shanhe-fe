# 《山河剑行》竖切片对话数据 dialogue-v1 说明

文件：`/workspace/wuxia-team/dialogue-v1.json`（UTF-8，单一 JSON 对象，Godot 4 `JSON.parse_string()` 可直接读）。
状态：**设计提案，未接入、未在 Godot 内实测**。任务 ID、状态名、交互点 ID 都是提议，接入时要和实现对上。仓库 `/workspace/godogen-shanhe` 只读过，没有改。

## 0. 来源与差异
- 内容以仓库 `docs/story-data.md` 为准。和 `/workspace/wuxia-team/story-data.md` 比对过，**两份完全一致**（diff 没有差异）。
- 另外参考了：`BRIEF.md`（对话：半身立绘、打字机、选项）、`docs/gameplay-spec.md` §5（“他每出三刀就要砍一记重的”这句 NPC 提示，规格写明要剧情侧同意）、`docs/battle-v1-godot.md`（胜利只设一个“已胜利”标记，胜利不等于交付）、`docs/godot-ui-plan.md` §7（左右两张立绘，说话方亮，选项按钮）、`docs/ref-characters/characters.json`。
- 工作期间仓库有别人在改：`BRIEF.md` 新增“Update”一段，新增了 `docs/battle-v1-godot.md` 和 `docs/godot-ui-plan.md`。这些改动不是我做的，内容和本数据不冲突。
- story-data **没有**周伯委托接取/交付和厉横战前战后的原台词，这些都按最小需要新写，标为 `"source":"new-pending-review"`（新增待审）。story-data 里原有的台词逐字沿用，标为 `"source":"story-data"`。周伯的提示句标为 `gameplay-spec-5-pending-review`。
- 人名：沈砚是现有名；**林照晚、明澄是拟名**；周伯、厉横沿用 story-data 用名，和“褐衣老人/壮汉”的对应也是拟定的（`nameStatus: tentative`）。蓝衣长者、狼、另一位粉衣女子没有安排（和 story-data 一致）。

## 1. 数量
23 段对话，48 个节点，8 个选项，5 个交互点。台词来源：story-data 16 条，新增待审 31 条，gameplay-spec 提示 1 条。最长一句 31 字，按 ui-spec 每行最多 24 字算不超过 2 行。

| 交互点 | 对话（按顺序匹配，用第一个满足条件的） |
|---|---|
| `village.zhoubo` 周伯 | zhou_main_offer → bc_zhou_invite → zhou_main_deliver → zhou_main_progress → bc_finale → bc_finale_replay → zhou_side_pending_girl → zhou_side_pending_monk → zhou_legacy_closed → zhou_idle（兜底） |
| `bamboo.linzhaowan` 竹林少女 | bc_girl_meet → bc_girl_repeat → bc_girl_after → girl_stranger（兜底） |
| `village.mingcheng` 村口僧人 | bc_monk_join → bc_monk_wait → bc_monk_ready → bc_monk_after → monk_idle（兜底） |
| `bamboo.liheng` 厉横 | liheng_prebattle → liheng_defeated_idle → liheng_idle（兜底） |
| `battle_return.liheng_victory` 战斗胜利回到探索 | liheng_postbattle（只播一次，没有兜底，不匹配就什么都不播） |

## 2. 结构字段表
**顶层**
| 字段 | 说明 |
|---|---|
| schemaVersion | 1。只是对话数据的版本，和存档版本、支线块的 schemaVersion 无关 |
| id / contentVersion / language / status | 标识和说明 |
| evaluation | 求值规则的简短机读说明（以本文第 3 节为准） |
| states | 允许的任务状态值：`main.zhouCommission`、`side.bambooCompanions` |
| flagsRead | 对话会读的标记及来源 |
| effectTypes | 允许的 effect 类型 |
| speakers | 说话人表，key 是 speaker id |
| interactionPoints | `{point: {scene, dialogues:[按优先级排的对话 id]}}` |
| dialogues | 对话段数组 |
| nodes | 节点数组（全局唯一 id，`dialogue` 字段标明属于哪段） |

**speakers[id]**：`displayName`、`nameStatus`（existing/tentative）、`appearance`、`panelSide`（left/right，立绘放哪边）、`portraits{expression: {key, sourceFile, resPath}}`。
- `key`：立绘/表情的逻辑 key，比如 `portrait.shenyan.default`。
- `sourceFile`：只填仓库里**确认存在**的文件（相对仓库根目录）。目前只有 `docs/ref-characters/shenyan_portrait.png` 和 `docs/ref-characters/linzhaowan_portrait.png`。
- `resPath`：全部是 null，等接入时填（见第 6 节）。

**dialogues[]**：`id`、`trigger{scene, point}`、`entry`（入口节点 id）、`conditions`（条件数组）、`replayable`（只是标注能不能重复播；完全没有 effect 的对话本来就可以重播）、`note`。

**nodes[]**
| 字段 | 说明 |
|---|---|
| id, dialogue | 节点 id，所属对话 |
| speaker | speakers 里的 id |
| expression | portraits 里的 key；找不到就退回 `default`；default 也没有文件，就只显示名字不显示立绘 |
| nameOverride | 可选，临时显示名（少女自报姓名前显示“背剑少女”） |
| text / locKey | 中文正文 / 本地化 key（`dlg.<节点id>`） |
| source | story-data / new-pending-review / gameplay-spec-5-pending-review |
| conditions | 节点守卫，v1 全部为空（见 3.4） |
| next / choices / end | **三选一**。`choices[]` = `{id, text, locKey, next, conditions, source}` |
| setFlags | `{flag: value}`，只能写 `dlg.*` 命名空间 |
| effects | `[{type:"questEvent", quest, event}]` 或 `[{type:"startBattle", battleId}]` |
v1 里 setFlags 和 effects 只出现在 `end` 节点上，校验脚本会检查这一点。

## 3. 条件和标记的求值规则
### 3.1 条件格式
- `{"flag":"battle.liheng.won","equals":true}`：标记不存在时取 null。
- `{"quest":"side.bambooCompanions","equals":"accepted"}`，或 `{"quest":..., "in":["girlMet","bothMet"]}`。
- `{"all":[...]}`、`{"any":[...]}`、`{"not":{...}}`。
- `conditions` 数组里的条件是“并且”的关系；空数组为真。

### 3.2 三值逻辑（不明就不放行）
- 主线读不到时状态为 `unknown`，支线块损坏、版本不认识或回执矛盾时状态为 `disabled`。只要条件引用到这两种状态，结果就是 **unknown**。
- all：有一个假就是假；否则有 unknown 就是 unknown；否则为真。any：有一个真就是真；否则有 unknown 就是 unknown；否则为假。not(unknown) = unknown。
- 最后结果是 unknown 时按**假**处理。所以主线不明时只会落到无条件的兜底对话，不会因为 `not` 误放行。
- 条件格式不认识时按假处理，并记错误日志。

### 3.3 选对话
1. 交互前，运行时先做 story-data 的归并：读权威主线状态，处理 `locked→available`、`未接支线+已交付→legacyClosed`、`bothMet+已交付→ready`。
2. 按 `interactionPoints[point].dialogues` 的顺序取第一个条件为真的对话；都不满足就不播。
3. 一次交互只播一段对话，从 `entry` 开始。

### 3.4 提交语义（关键）
- 走过的节点和选中选项的 `setFlags/effects` 先放进待提交列表，**只有完整到达 `end:true` 节点并且玩家关掉最后一句后才一次性提交**。中途取消、退出、切后台被杀，全部丢弃，不推进。
- 节点 `conditions` 为假时（v1 没有用到）按取消处理。
- 提交顺序：① setFlags（只允许 `dlg.*`）→ ② questEvent 依次交给任务状态机 → ③ startBattle。
- **对话数据不能直接写任务状态**，只能发事件（accept/deliver/talkZhou/talkGirl/talkMonk）。守卫由状态机在提交时重新检查：主线是否已接/已交付、真实交付记录和回执。守卫不过时事件作废、状态不变，不报错给玩家。所以伪造的 UI 参数或“胜利”标记都不能直接完成交付。
- 奖励提示**不写在对话里**。只有状态机报告 `ready→completed` 的结算（completed + 回执 `bambooCompanions.v1.promise`）在同一次一致性保存里成功后，运行时才显示“同行之约”。保存失败就保持 ready，可以重试。

## 4. 和 story-data 状态的映射
| 支线状态 | 周伯 | 少女 | 僧人 | 推进事件（在哪个对话的 end） |
|---|---|---|---|---|
| locked（主线未接） | zhou_main_offer（接主线：`main accept`） | girl_stranger | monk_idle | — |
| available | bc_zhou_invite | girl_stranger | monk_idle | talkZhou → accepted |
| accepted | 主线进行中：zhou_main_progress/deliver；已交付：zhou_side_pending_girl | **bc_girl_meet** | monk_idle | talkGirl → girlMet |
| girlMet | 进行中/交付；已交付：zhou_side_pending_monk | bc_girl_repeat | **bc_monk_join** | talkMonk → bothMet |
| bothMet | 进行中/交付 | bc_girl_repeat | bc_monk_wait | 主线交付后由归并转 ready |
| ready | **bc_finale** | bc_girl_repeat | bc_monk_ready | talkZhou → completed（唯一结算） |
| completed | bc_finale_replay（可重播，没有 effect） | bc_girl_after | bc_monk_after | 不变，不授奖 |
| legacyClosed | zhou_legacy_closed（“旧事已结”） | girl_stranger | monk_idle | 不变，不补奖 |
| disabled / 主线 unknown | zhou_idle | girl_stranger | monk_idle | 不推进 |

主线：`notAccepted` → zhou_main_offer（end 时发 `accept`）→ `accepted` → liheng_prebattle（end 时 `startBattle liheng`）→ 战斗系统设置 `battle.liheng.won` → liheng_postbattle（只播一次，设 `dlg.liheng.postSeen`）→ zhou_main_deliver（end 时发 `deliver`，状态机核对胜利后转 `delivered`；原任务奖励由原流程发）。

**关键决策**
1. 周伯处 `bc_zhou_invite` 排在 `zhou_main_deliver` 前面。这样玩家先打赢厉横再回来时，也会先接到支线，不会因为先交付而落进 legacyClosed。代价是交付要多和周伯说一次话。
2. 每个选项最多 2 个，最后都汇合到同一节点，不影响主线结果，也不引入新系统。
3. 林照晚在僧人对话（bc_monk_join）和结尾里只是在对话中说话，表示叙事上的同行；不生成跟随角色。
4. 没有循环。bc_finale_replay 是明确可重播的结尾，每次都从入口重新开始，节点之间不成环。
5. 战败没有对话，按 battle-v1 回到快照，回到竹林可以再触发 liheng_prebattle。

## 5. Godot 加载建议（伪代码）
```gdscript
var db := {}; var nodes := {}; var dialogues := {}
func load_db(path := "res://data/dialogue-v1.json") -> bool:   # 路径待定
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null: return false
    var d = JSON.parse_string(f.get_as_text())
    if typeof(d) != TYPE_DICTIONARY or int(d.get("schemaVersion", 0)) != 1: return false
    db = d
    for n in d.nodes: nodes[n.id] = n
    for x in d.dialogues: dialogues[x.id] = x
    return true

enum T { FALSE, TRUE, UNKNOWN }
func ev(c: Dictionary) -> int:
    if c.has("all"):
        var r := T.TRUE
        for s in c.all:
            var v := ev(s)
            if v == T.FALSE: return T.FALSE
            if v == T.UNKNOWN: r = T.UNKNOWN
        return r
    if c.has("any"):
        var r := T.FALSE
        for s in c.any:
            var v := ev(s)
            if v == T.TRUE: return T.TRUE
            if v == T.UNKNOWN: r = T.UNKNOWN
        return r
    if c.has("not"):
        var v := ev(c["not"]); return v if v == T.UNKNOWN else (T.TRUE if v == T.FALSE else T.FALSE)
    if c.has("quest"):
        var s: String = Quests.get_state(c.quest)          # 'unknown' / 'disabled' 视为不明
        if s in ["unknown", "disabled"]: return T.UNKNOWN
        if c.has("equals"): return T.TRUE if s == c.equals else T.FALSE
        if c.has("in"): return T.TRUE if s in c["in"] else T.FALSE
    if c.has("flag") and c.has("equals"):
        return T.TRUE if Flags.get(c.flag, null) == c.equals else T.FALSE
    push_error("bad condition"); return T.FALSE

func ok(list: Array) -> bool: return ev({"all": list}) == T.TRUE

func pick(point: String):
    Quests.normalize()                                   # story-data 归并
    for id in db.interactionPoints.get(point, {}).get("dialogues", []):
        if ok(dialogues[id].conditions): return dialogues[id]
    return null

# 运行：pending 累积，end 才提交；取消直接丢掉 pending
func run(dlg) -> void:
    var pending_flags := {}; var pending_fx := []
    var n = nodes[dlg.entry]
    while true:
        if not ok(n.conditions): return                  # 视同取消
        pending_flags.merge(n.setFlags, true); pending_fx.append_array(n.effects)
        var cancelled := await panel.show_line(n)        # 立绘/打字机/点击
        if cancelled: return
        if n.get("end", false): break
        if n.has("choices"):
            var opts = n.choices.filter(func(c): return ok(c.conditions))
            var c = await panel.choose(opts)
            if c == null: return
            n = nodes[c.next]
        else:
            n = nodes[n.next]
    for k in pending_flags: if k.begins_with("dlg."): Flags.set(k, pending_flags[k])
    for fx in pending_fx:
        if fx.type == "questEvent": Quests.dispatch(fx.quest, fx.event)  # 状态机重验守卫/原子保存/奖励提示
    for fx in pending_fx:
        if fx.type == "startBattle": Battle.start(fx.battleId)
```
建议 `tests/run_tests.gd` 加对话解析测试：能解析、引用都存在、每个交互点最后一段是无条件兜底，取消对话后状态不变。

## 6. 待核实项
1. **立绘资源**：只有沈砚、林照晚各一张 default 半身像（`docs/ref-characters/*_portrait.png`，仓库里确认存在）。是否作为 `res://docs/ref-characters/...` 导入，取决于 project.godot 放在哪，所以 resPath 留空。周伯、明澄、厉横**没有任何立绘**，表情 key（smile/serious/angry）全部**只是逻辑 key，等美术对接**。没有图时只显示名字，或者退回 default。
2. **任务 ID 和状态映射**：`main.zhouCommission`（notAccepted/accepted/delivered/unknown）、`side.bambooCompanions`、`battle.liheng.won`、`battleId: liheng` 都是提议，要和实际的任务/存档/战斗标记对上。支线状态机、归并和原子保存要另外实现（见 story-data）。
3. **交互点和场景 ID**：`village.zhoubo`、`village.mingcheng`、`bamboo.linzhaowan`、`bamboo.liheng`、`battle_return.liheng_victory` 是提议。BRIEF 写的是“村庄+山门”，story-data 写的是“村口/竹林”，场景名要以实现为准。厉横打完是否离场，决定 liheng_defeated_idle 用不用得上。少女和僧人什么时候出现在场景里，也要定。
4. **台词审定**：31 条新增台词，加上 gameplay-spec 那句提示，都要剧情侧审。委托具体内容（“赶走拦路的厉横，回来说一声”）是最小假设，不涉及物品。
5. **本地化**：v1 只有 zh-Hans，`locKey = dlg.<id>` 已经预留。以后可以导出 Godot CSV/PO 翻译表，用 `tr(locKey)`，取不到时用 text。
6. 奖励提示文案（“同行之约”）、获奖弹窗的 UI，归任务状态机和 UI 负责，不在本对话数据里。
