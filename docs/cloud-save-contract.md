# 山河剑行：最小云存档接口与验收（纯设计提案）

## 1. 能力与边界

可提供通用服务端存档同步的**协议与验收设计**。未读改仓库，未动服务器/网络/凭证，未另建仓库或调用云代码。现有存档字段、本地原子写、部署入口/数据库、认证平台、奖励与旧档是否已绑定账户均**未核实、未实现、未测试**。下文路径、字段、状态码、TTL、体积与保留条数均为**提议**，不是线上事实。

本轮只交付本文，供统筹交原开发在原仓库接续。当前范围是**按玩家身份隔离的云备份**，不是服务端权威经济或反作弊：`payload` 不透明，服务端不解释货币、背包、奖励，也不裁决数值合法性。不扩钱包、校验或反作弊系统。

只读沿用 `story-data.md`：同步不得拆改主线、钱包、背包、战斗结果及 `storyExtras.bambooCompanions`；`completed` 与 `rewardReceipt` 须在同一次本地一致性保存中出现后再入队；未知版本/状态、类型错误、矛盾回执或损坏块原样留存并停用无法安全解释的部分，不得当缺失初始化或降级覆盖后上传。扩展 `schemaVersion` ≠ 信封 `saveSchemaVersion`。整体存档不受支持时遵循原加载保护。无归属旧档可继续纯本地游玩，**须玩家明确绑定**当前已认证账户后才能上传或与云端对账，禁止设备码自动绑死或跨账号合并。

待核实：本地字段/编码/迁移；本地是否已有事务或 WAL；基址与存储；认证 SDK 与令牌校验；HTTPS 终止。同目录其他设计稿无云接口，其中的版本线索不能当作已核实 schema。

原则：认证后取本人最新云档；关键进度异步保存（任务/战斗结算/交付与回执/切场景/进后台/退出），禁止逐帧请求；单槽 `current`；修订乐观锁（创建基线 `expectedRevision=0`）；冲突不按客户端时间静默覆盖；HTTPS；令牌派生 `ownerId`，忽略客户端 `playerId`。

## 2. 身份与资源

客户端只带正规认证令牌（提议：`Authorization: Bearer <token>`）。服务端校验签发者、签名、audience 与过期，从主题派生 `ownerId`。body/query/路径中的 `playerId`/`ownerId`/设备号一律忽略。主键提议 `(ownerId, slot)`，`slot` 固定 `"current"`。A 只能读写 A 的档与备份；B 夹带 A 的 ID 仍只操作 B。他人资源与“无此备份”同样返回 `404`，不泄露是否存在。令牌不写入 payload、不进普通日志。

认证不可用（令牌无法通过服务端验证、无法刷新或认证服务不可达）时：不把本地缓存身份当作已认证，不发起云读写。仅允许加载**已经关联 owner** 的本地档离线游玩。切账号必须取消旧账号在途网络任务并丢弃其迟到响应，不得把旧 ACK 写入新账号的确认修订或队列。

提议前缀 `/v1/saves/current`：

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/v1/saves/current` | 最新云档；无档 `404` |
| PUT | `/v1/saves/current` | 匹配修订后写入；创建用 `0` |
| GET | `/v1/saves/current/backups` | 仅本人备份元数据 |
| POST | `/v1/saves/current/restore` | 将本人某次备份写成新修订 |

写请求必须带 `Idempotency-Key`（提议 UUIDv4）。可选 `If-Match` 若出现必须等于体内 `expectedRevision`，否则 `422`。提议：payload 上限 512KiB（超限 `413`）；幂等记录保留 72 小时；备份保留最近 10 个成功修订。

`revision` 由服务端从 1 起单调递增，客户端不得用时间戳充当。无云档时逻辑修订为 `0`。两设备同时以 `0` 创建：一者 `200` 得 `revision=1`，另一者 `409`。`updatedAt` 仅展示。成功写入后修订为 `当前+1`，并备份上一版。

## 3. 幂等、指纹与写入顺序

指纹必须包含 **method + path + body**，防止同一键把 PUT 成功响应误回放到 restore（或相反）。采用最简单一致方案：客户端把首次请求的 method、path 与 body 的 **exact bytes** 连同键一并持久冻结，重试原样重放，不重新序列化 JSON。服务端指纹 = 上述三项的字节拼接哈希（分隔符为实现细节）。不额外引入 RFC8785；若未来有中间层改写 JSON，须另定单一规范化后再启用，当前未核实、不采用。

可选 checksum 须先规定 payload 编码与哈希算法再启用；本文示例不含该字段，不提供未计算的摘要。服务端现阶段不校验 checksum。

在 `(ownerId, slot)` 事务内顺序固定：

1. 校验令牌并派生 `ownerId`，失败 `401`。
2. 只能访问自己的 `current`。
3. 校验信封类型、必填字段与体积。
4. **先**查 `(ownerId, Idempotency-Key)`（键必须带 owner）：指纹相同则直接返回当初完整响应，不再次写入或递增；指纹不同（含 method/path/body 任一不同）则 `409` `IDEMPOTENCY_KEY_REUSE`，原档不变；无记录则继续。
5. **再**比 `expectedRevision`：不等（含无档但期望值不为 `0`）则 `409` `REVISION_CONFLICT`，带回服务端**当时**完整副本（不回显客户端 payload），并记录该最终响应；相等则同一事务写入 payload、修订 +1、备份上一版并记录成功响应。任一步失败全部回滚。

并发：同用户同键同指纹必须串行并得到同一结果，修订只加一次；同键不同指纹稳定得到 `IDEMPOTENCY_KEY_REUSE`；同键跨用户隔离。不同键同一期望修订：一成功一冲突。

未确认请求必须冻结**原键 + 原体字节**做结果收回，可按退避多次重试。`5xx`、超时、断连都可能已经提交，**不可断言失败**，也不可换新键改发 T2。新键只用于：已确认最终失败后的新请求，或 T1 已 ACK 之后的续传 T2（新写操作）。可判定未提交的明确拒绝示例：`422`/`413`。`409` 进入保留双方与玩家选择，不是自动换键覆盖。幂等 TTL 到期或无法判断记录是否仍在：先 GET 对账，禁止盲目重放冻结核；能按第 6 节安全判定则执行，否则原样保留双方。

## 4. JSON 示例（字段均为提议）

载荷只演示与 `story-data.md` 一致的扩展片段，不是完整存档，不能用来证明主线已交付。PUT 成功响应与 GET 200 相同形状，可省略 `payload`。

GET 200：

```json
{
  "slot": "current",
  "revision": 4,
  "saveSchemaVersion": 1,
  "updatedAt": "2026-11-08T03:40:00+08:00",
  "payload": {
    "storyExtras": {
      "bambooCompanions": {
        "schemaVersion": 1,
        "state": "completed",
        "rewardReceipt": "bambooCompanions.v1.promise"
      }
    }
  }
}
```

GET 404：

```json
{
  "error": "SAVE_NOT_FOUND",
  "slot": "current"
}
```

PUT 创建（基线 0；头：`Authorization`、`Idempotency-Key`、`Content-Type: application/json`）：

```json
{
  "expectedRevision": 0,
  "saveSchemaVersion": 1,
  "payload": {
    "storyExtras": {
      "bambooCompanions": {
        "schemaVersion": 1,
        "state": "bothMet",
        "rewardReceipt": null
      }
    }
  }
}
```

PUT `409`（保留双方，不自动覆盖；`server` 是该次冲突时的快照，确认前须重新 GET）：

```json
{
  "error": "REVISION_CONFLICT",
  "message": "存档修订冲突，已保留双方，须由玩家明确选择",
  "clientExpectedRevision": 3,
  "server": {
    "slot": "current",
    "revision": 5,
    "saveSchemaVersion": 1,
    "updatedAt": "2026-11-08T03:42:00+08:00",
    "payload": {
      "storyExtras": {
        "bambooCompanions": {
          "schemaVersion": 1,
          "state": "completed",
          "rewardReceipt": "bambooCompanions.v1.promise"
        }
      }
    }
  }
}
```

同键不同指纹：

```json
{
  "error": "IDEMPOTENCY_KEY_REUSE",
  "message": "同一幂等键不能搭配不同的 method、path 或 body"
}
```

恢复请求：

```json
{
  "sourceRevision": 2,
  "expectedRevision": 5
}
```

恢复成功时新 `revision` 为 `6`（示例），内容等于本人修订 `2` 的备份，修订号不回到 `2`。

## 5. 本地事务、隔离与冻结续传

本地原子能力待核实。崩溃不得留下半份结算。存档正文与 dirty/队列（及在途冻结核）必须在**同一持久事务**中提交；若存储层做不到，须有 write-ahead 日志或按本地 `generation` 扫描恢复。禁止“save 已落盘、队列尚未写”且无恢复路径——重启后会漏传。每个本地快照有单调 `generation`。启动或恢复时若发现存档 `generation` 大于已入队/已确认的 generation，则从存档重建待传并视为 dirty。

单槽：至多一个在途冻结核 `{key, method, path, bodyBytes, generation, expectedRevision}`，外加“最新本地快照”本身，不按事件无限堆积。关键进度先与 dirty/队列同事务落盘，再异步发送。位移与动画不上传。短时间多次变化合并为最新 generation。

在途 T1/`generation=G1`/键 K1 之后本地又写入 T2/`G2`：K1 继续用冻结的原体字节退避重试以收回结果，不得把 T2 塞进 K1。T1 的 ACK **不得覆盖**本地 T2（不回滚 payload、不把 T2 改成 T1）。ACK 只按 generation 清理：确认 G1 仅清除 G1 的在途项与其待确认标记；若当前 generation 仍大于 G1，dirty 与 T2 保留，随后用**新键**续传 T2，`expectedRevision` 为刚确认的云端修订。禁止在 T1 未得到最终结果时用新键发 T2。网络 pending 时继续本地游玩，不丢进度。

本地文件与队列按已关联 `ownerId` 分目录（或等价隔离）。无归属旧档不自动进入任何账号的队列。

## 6. 启动矩阵

定义：无云档 = 在线 GET 得 `SAVE_NOT_FOUND`。本地无档 = 该 owner 下没有可加载存档。本地脏 = 存在未确认的本地 `generation`（相对 `lastAckedRevision`）；无确认记录但已有进度也视为脏。队列 = 持久化在途冻结或待传。离线/GET 非 404 失败 ≠ 无云档，禁止因此用 `expectedRevision=0` 去创建。`dirty=false` 但存在队列：视为不一致，先按 WAL/`generation` 恢复并当作 dirty，再进入下表，不得忽略队列。

先认证，再 GET（仅在已通过服务端认证时）。GET 期间玩家继续游玩：记下发起时的本地 `generation`；返回后若 generation 已变，不得自动用云端替换本地，改按 dirty/冲突处理。任何分支都不用客户端时间选边。

| 条件 | 行为 |
|---|---|
| 离线或 GET 非 404 失败 | 按原规则加载本地（不受支持则不强行玩）；保留队列；继续游玩；不创建、不覆盖云端 |
| 在线无云档，本地无档且不脏、无队列 | 新开局；无进度不上传 |
| 在线无云档，本地有进度且从未确认过云档（`lastAcked` 未设置或为 0） | 明确旧档归属后保留本地；无未决冻结请求时异步用最新快照以 `expectedRevision=0` 创建 |
| 在线无云档，但 `lastAcked > 0` 或存在未决冻结请求 | 异常/结果待收回：保留本地，不自动按 0 重建；先收回请求结果或明确处理云档缺失 |
| 在线有云档，本地无档，发起 GET 后 generation 未变 | schema 可加载则自动拉取云端；不可加载则云端原样留存、不强行玩、不上传降级档 |
| 在线有云档，schema 不可加载 | 云端原样留存；不覆盖本地；不上传降级档；队列不可自动发送 |
| 可加载，不脏无队列，`lastAcked == 云端 revision` | 已同步，用本地 |
| 可加载，不脏无队列，`lastAcked < 云端 revision`，且 GET 期间 generation 未变 | 用云端替换本地并更新确认修订 |
| 可加载，脏，`lastAcked == 云端 revision` | 本地领先，冻结/续传最新快照 |
| 可加载，脏，`lastAcked != 云端 revision` | 多设备冲突，保留双方，停发，交玩家选择 |
| `lastAcked > 云端 revision` | 异常保护：保留双方，不自动推送或拉取 |
| GET 期间 generation 变化，且云端修订 ≠ `lastAcked` | 不得自动替换，按冲突保留双方 |
| GET 期间 generation 变化，且云端修订 = `lastAcked` | 不得用本次 GET 覆盖本地；视为脏，稍后上传最新快照 |

本地扩展块损坏或未知：按 `story-data.md` 整块留存，停用无法解释的部分并暂停自动上传；经原有兼容规则确认可安全保留后，上传也必须带未改写的原块。

## 7. 冲突选择、schema 与恢复

多次 `409` 以及幂等回放的旧 `409` 都只反映当时快照，不是确认时的最新云档。玩家确认前必须重新 GET 并再次校对 revision；若与展示给玩家的版本不同，刷新双方摘要并重新征求选择，不能把旧确认套到新版本。双方原样保留（不用过期 `server` 覆盖本地）。选云端：仅当**新 GET** 的 schema 可加载时，用新 GET 结果原子替换本地并更新 `lastAckedRevision`。选本地：保留本地，用新键 PUT 最新快照，`expectedRevision` 为**新 GET** 的修订。禁止：把旧 409 当最新、自动重发原 PUT、按时间戳选边、pending 时丢本地新进度。

信封 `saveSchemaVersion` 为正整数并原样保存；服务端不迁移游戏字段。不认识的版本、损坏信封：原样留存，不当无档创建，不降级写回。较旧但受支持的云端版本只允许按原游戏已有规则在本地升级；仅当 `lastAcked` 仍等于升级前的云端修订时，才可作为脏数据上传。

备份仅 owner 可列举；期待保留最近 10 个成功修订（非已上线值），无公开 URL。`sourceRevision` 只在该 owner 的该 slot 内解析：B 使用数字 `N` 只可能指向 B 自己的备份。恢复是一次写入，需正规认证、owner 归属、`expectedRevision` 与新幂等键。当前为 Y 时恢复 X，则新建 `Y+1`（内容为 X 的副本），禁止把指针改回 X，以免持有 `expectedRevision=X` 的客户端误写（ABA）。非本人或无此备份：`404`，且不得返回他人 payload。

## 8. 精简可执行验收

下列均为设计验收，不是已测通过项。

1. **跨账号：** A 写入可见 payload 后，B 的 GET `/current` 只能是 B 的 404 或 B 自己的档，不得出现 A 的字段；B 夹带 A 的 playerId 仍只操作 B。`sourceRevision` 数字不能指向 A 的备份：B 恢复同一数字时，若 B 自己有该修订备份则成功且只恢复 B 的内容；若 B 没有，才 `404`。两种结果都不得返回 A 的 payload，也不能因为“A 存在该号备份”而要求 B 一定 `404`。
2. **断网重启：** 离线写入关键进度（含支线回执）后杀进程再离线启动：本地与队列仍在，可继续游玩。save 与队列同事务或经 WAL/`generation` 恢复后不得漏传。恢复网络后按矩阵处理，不得把离线误判成无云档并以 `0` 覆盖。
3. **响应丢失与 5xx：** 服务端已接受使修订变为 N 但响应丢失（或先回 5xx）：客户端用冻结原键原体退避重试，得到同一成功且修订仍为 N。本地若已是 T2，T1 的 ACK 不得覆盖 T2，随后续传 T2。在未确认最终失败前不得换新键发 T2。
4. **并发冲突：** 两设备同一修订、不同 payload 与不同键：一次 `200`、一次 `REVISION_CONFLICT`。不自动重发；时间戳相反也不改变胜负。确认前重新 GET；选本地后以新 GET 的修订为期望值再 PUT。
5. **同键指纹 / 跨用户同键：** 同一用户同键但 method/path/body 任一不同，得 `IDEMPOTENCY_KEY_REUSE` 且档不变。用同一键先 PUT 再 restore 不得回放 PUT 结果。A 与 B 使用字面相同的键互不串档。
6. **创建基线：** 无云档两设备同时 `expectedRevision=0`：一个成功，另一个 `409`。
7. **未知 schema：** 未知或非法 `saveSchemaVersion`、扩展块矛盾/损坏：原样保留，不初始化为空，不降级覆盖，不强行加载；自动上传关闭。
8. **恢复防 ABA：** 当前 5 恢复本人的 2，得到 6 且内容等于 2；仍持 `expectedRevision=2` 的 PUT 必须 `409`。无令牌 `401`。非 owner 得不到他人备份内容。
9. **队列与 ACK 清理：** T1 在途时发展到 T2：pending 期间不丢 T2；ACK G1 不得清掉 G2。`dirty=false` 但有队列时按不一致恢复。TTL 过期须先 GET，不得盲目重放。
10. **启动补齐：** 本地无档但云档存在且 GET 期间无新本地进度：自动拉取（schema 可加载时）。`lastAcked > 云端 revision`：保留双方，不自动覆盖。GET 期间 generation 变化：不自动替换。
11. **切账号与认证：** 切账号后旧 ACK 不得写入新账号。认证不可用时不发起云请求，只允许已关联 owner 离线游玩。过期或伪造令牌不得读写云档。
12. **服务端事务：** 写入中断后修订、payload、备份与幂等记录一致，只可能是旧完整档或新完整档。本协议不验收服务端经济防作弊（不提供该能力）。

## 9. 移交

路径：`/workspace/wuxia-team/cloud-save-contract.md`。未改其他文件。阻塞：现有 schema、本地事务能力、认证平台与部署入口、旧档/奖励绑定均未知；不阻止审协议，但阻止宣称已可上线。本轮无实现。
