# 存档服务已就绪（Lead 已部署并实测通过，直接对接即可，不要自己重写服务端）

## 服务地址
- 根：`https://ubuntu.tail7a8897.ts.net:8444`
- 密钥：`Ue75wVkreSf7l9zVxwySts3A`（请求头 `X-Save-Key`）
- 落盘：服务器 `/DATA/GameSaves/云端/<player_id>/slot<N>.json`

## 接口（全部 JSON，请求头必须带 `X-Save-Key`）
1. `GET /health` → `{"ok":true,"version":"1.0.0"}`
2. `GET /saves/<player_id>` → `{"ok":true,"slots":[{"slot":1,"saved_at":"...","bytes":117,"label":"..."}]}`
3. `GET /save/<player_id>/<slot>` → `{"ok":true,"data":{...存档内容...}}`（不存在返回 404）
4. `PUT /save/<player_id>/<slot>` body `{"data":{...},"label":"村口-手动"}` → `{"ok":true,"slot":1,"bytes":117,"saved_at":"..."}`
5. `DELETE /save/<player_id>/<slot>`

约束：`player_id` 只允许 `[A-Za-z0-9_-]{8,64}`；`slot` 为 1-9；单存档 ≤4MB。

## 客户端要求（Godot 4.7）
- 用 `HTTPRequest` 节点（异步，不要阻塞主线程）
- `player_id`：首次启动生成 UUID，存 `user://player_id.txt`
- 密钥写进 `project.godot` 的自定义设置或常量子类（这是 tailnet 内弱鉴权，不是账号系统）
- 设置面板加三个按钮：**上传到存档位 1/2/3**、**从存档位读取**、**查看云端存档列表**
- 上传内容 = 现有 `SaveManager` 序列化的同一个字典（复用，不要另造格式）
- 失败要提示（无网络/密钥错/超时），不要把游戏卡死
- 本地存档保持原样，云端是额外备份，**不要破坏现有 save/load 逻辑**
