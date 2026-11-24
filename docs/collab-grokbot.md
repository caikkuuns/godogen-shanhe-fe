# 多人/多 Bot 协作与交班

## 1. 共享项目文件

服务器上已建**共享裸仓库**：

```
/DATA/GameDev/repos/shanhe.git      # 63MB，master 分支
```

工作副本：`~/games/godogen-shanhe-fe`（origin 已指向裸仓库）。

### Bot 侧怎么拿到同一份文件（二选一）

**A. 公网 Git 地址（推荐，无需第三方账号）**
把裸仓库用 Tailscale Funnel 暴露成 HTTPS + Basic Auth：

```bash
# 在服务器执行（待确认）
tailscale funnel --bg --https=9443 http://127.0.0.1:9000   # 由 git HTTP 服务承载
```

Bot 侧：
```bash
git clone https://用户名:口令@<funnel-host>:9443/shanhe.git
```

**B. 第三方私有仓库**
把本仓库推一份到 GitHub / Gitee 私有库，Bot 用它的 token 克隆；
我们这边再加一个 `public` remote，交班时 push 两次。

> 为什么不能直接用现在的 Tailscale IP：Bot 的云端电脑不在我们 tailnet 里。

## 2. 分时段交班

```bash
# 接班（会检查是否有人占班）
bash scripts/shift-start.sh <名字>

# 干活……改代码/模型

# 交班（自动跑测试 → 提交 → 写交班条目 → 释放班次 → push）
bash scripts/shift-end.sh <名字> "做了什么" "未完成/坑" "下一位先做什么"
```

状态文件：`.shift/state.json`（owner / since）
日志文件：`.shift/handover.md`（最新条目在最上面）

### 铁律
1. 同一时刻只有一个 owner；`shift-start` 会拒绝抢班。
2. 交班必须 `git push`，没推送不算交班。
3. 交班条目必须包含测试结果（145/145、UI 3/3、WORLD 10/10）。
4. 大文件/资产走仓库，不走聊天。
5. 接手先读 `.shift/handover.md` 最新条目 + `git log -5`。

## 3. Grok Bot 接入

插件已装在服务器：`~/tools/grokbot/plugin`（MCP 服务，`node lib/codex-mcp.js`）。

需要登录凭据（二选一）：
- `~/.dsh/grok-bot.json`：`{"accessToken":"…","machineId":"…"}`
- 环境变量：`GROK_BOT_ACCESS_TOKEN` / `GROK_BOT_MACHINE_ID`

凭据来源：Mac/Windows 版 Grok Bot 的 `sand-secrets.json`（插件能自动读），
或从已登录设备的应用数据里导出。**不要提交到仓库、不要写进聊天记录。**
