# Grok Bot 接入说明（服务器侧）

## 入口（临时公网隧道）
- 公网地址：`https://symbol-archive-charleston-featuring.trycloudflare.com`
- 由 `cloudflared tunnel --url http://127.0.0.1:9000` 提供（服务器 `~/tools/cloudflared`）
- 上游：`shanhe-git.service`（127.0.0.1:9000），Basic Auth 用户名 `shanhe`
- 口令：见服务器 `~/.shanhe-git-pass`（不要写进仓库）
- 隧道重启后地址会变；若 Tailscale Funnel 启用则改用固定域名

## 收到的第一条接入指令（已发给 奶蛙）
1. `git clone <入口>/shanhe.git shanhe-shared`
2. `git checkout -b grokbot/main`
3. 把它自己的项目文件整体复制进去（不删仓库已有文件；同名冲突放 `incoming/grokbot/`）
4. `git add -A && git commit -m "import: Grok Bot 项目文件" && git push origin grokbot/main`
5. 回执：commit hash + 新增/冲突目录

## 班次
| 班次 | 时间窗（Asia/Shanghai） |
|---|---|
| dsh（DSH / Claude Code） | 07:00 – 23:59 |
| grokbot（Grok Bot） | 00:01 – 06:50 |

- 接班：`bash scripts/shift-start.sh grokbot`
- 交班：`bash scripts/shift-end.sh grokbot "做了什么" "未完成" "下一位先做什么"`
- 看班：`bash scripts/shift-status.sh`
- 规则在 `.shift/policy.json`，脚本会拒绝时间窗外/抢班

## 合并策略
Grok Bot 推到 `grokbot/main` 后，由 dsh 班次执行：
```bash
git fetch origin grokbot/main
git merge --no-ff origin/grokbot/main   # 冲突时优先保留双方，再人工裁决
bash tests/run_all.sh                    # 必须全绿
```
