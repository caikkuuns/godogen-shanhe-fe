# Grok Bot（服务器侧）安装说明

## 已安装
| 项 | 位置 |
|---|---|
| 插件源码 | `~/tools/grokbot/plugin`（MCP 服务，Node，无需额外依赖） |
| 启动器 | `~/tools/grokbot/run.sh`（读取令牌后 exec MCP） |
| 令牌文件 | `~/.dsh/grok-bot.json`（`accessToken` + `machineId`，600，当前为空占位） |
| 项目 MCP 配置 | `~/games/godogen-shanhe-fe/.mcp.json` → `grok-bot` |

## 已提供的工具（12 个）
`grok_bot_status` `grok_bot_list` `grok_bot_ask` `grok_bot_ask_team` `grok_bot_wait`
`grok_bot_history` `grok_bot_computer`
`grok_bot_memory_recall` `grok_bot_memory_list` `grok_bot_memory_write` `grok_bot_memory_forget`
`grok_bot_jailbreak`

## 还差一步：登录凭据
```bash
# 编辑，填入从 Mac/Windows 版 Grok Bot 的 sand-secrets.json 里取到的值
nano ~/.dsh/grok-bot.json
# {"accessToken": "xxx", "machineId": "yyy"}
```
填好后验证：
```bash
cd ~/tools/grokbot/plugin && node lib/codex-mcp.js   # 手动发 tools/call grok_bot_status
```
或在 Claude Code 里让它调用 `grok_bot_status`。

## 共享项目文件给 Bot（Funnel）
git smart-HTTP 已在本机 9000 端口跑起来（`shanhe-git.service`，带 Basic Auth，
口令在 `~/.shanhe-git-pass`），但 **Funnel 未启用**，需要先打开：

https://login.tailscale.com/f/funnel?node=nmt2oYzAEf11CNTRL

启用后在服务器执行：
```bash
sudo tailscale funnel --bg --https=9443 http://127.0.0.1:9000
```
Bot 侧克隆：
```bash
git clone https://shanhe:<口令>@ubuntu.tail7a8897.ts.net:9443/shanhe.git
```
