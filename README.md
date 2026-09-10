# ChatGPT Web 访问本地电脑：换机傻瓜安装说明

这个目录用于在新的 Windows 电脑上快速恢复两条本地访问工作流：

- **代码 / Unity 项目**：ChatGPT Web → HTTPS Tunnel → `coding-tools-mcp-desktop` 官方 GUI → 本地 Workspace。
- **整台电脑远程操作**：ChatGPT Web → Remote Desktop Commander → 已注册设备。

> 当前标准方案只使用 `coding-tools-mcp-desktop` 官方 GUI 管理 MCP Runtime、OAuth 和 Cloudflare Tunnel。旧版脚本自己再启动一个 `:8000` MCP 的方案已经删除，不要恢复或混用。

## 1. 平时只需要记住 5 个入口

1. `01-安装.cmd`：换电脑后第一次运行；安装/升级依赖、创建默认 Workspace，并打开官方 GUI。
2. `02-启动Coding Tools MCP.cmd`：日常启动官方 Coding Tools MCP Desktop GUI。
3. `03-检查环境.cmd`：检查 Python、Node.js、cloudflared、Desktop GUI 和默认 Workspace。
4. `04-启动Remote Desktop Commander.cmd`：注册/启动当前电脑为 Remote Desktop Commander 设备。
5. `05-使用记录.cmd`：查看本地 MCP 使用记录，并可首次填写当前 ChatGPT 模型标签。

## 2. 新电脑第一次安装

把整个 `ChatGPT-LocalAccess-Setup` 文件夹复制到新电脑，然后双击：

`01-安装.cmd`

安装器会自动检查或安装：

- Python 3.11+
- `coding-tools-mcp[desktop]`（包含官方 `coding-tools-mcp-desktop` GUI）
- Cloudflare `cloudflared`
- Node.js LTS（Remote Desktop Commander 需要）

并自动创建：

`%USERPROFILE%\Desktop\CodingTool`

这是通用默认 Workspace，不绑定任何 Unity 项目。安装完成后会直接打开官方 Coding Tools MCP Desktop GUI。

## 3. 第一次配置 Coding Tools MCP Desktop

在官方 GUI 中点击 **Add workspace**，第一次可以直接粘贴安装器已经复制到剪贴板的默认路径：

`%USERPROFILE%\Desktop\CodingTool`

也可以直接选择真正要操作的项目，例如某个 Unity 工程根目录。推荐配置：

| 项目 | 推荐值 |
| --- | --- |
| Workspace | 你的项目根目录 |
| Local port | `28766` |
| Permission mode | `trusted` |
| Authentication | `OAuth` |
| Tunnel type | `Cloudflare` |
| Cloudflare mode | `Quick tunnel` |

`trusted` 适合你自己的开发电脑；它允许正常的本地开发命令和网络访问，但仍保留 Workspace 文件边界。除非你明确知道风险，否则不要使用 unrestricted/dangerous 类权限。

配置保存后点击 **Start**。官方 GUI 会：

1. 启动当前 Workspace 的 `coding-tools-mcp` Runtime。
2. 仅在本机回环地址监听，例如 `127.0.0.1:28766`。
3. 启用 OAuth。
4. 启动 Cloudflare Quick Tunnel。
5. 得到随机的 `https://xxxx.trycloudflare.com` 地址。
6. 显示最终 MCP Endpoint：`https://xxxx.trycloudflare.com/mcp`。

Quick Tunnel 不要求 Cloudflare 账号，适合开发和临时访问；它的域名是临时随机域名，重新启动 tunnel 后通常会改变。

Cloudflare 官方说明：<https://developers.cloudflare.com/tunnel/setup/#quick-tunnels-for-development>

## 4. ChatGPT Web 中创建 MCP

ChatGPT 不能直接连接 `127.0.0.1` 上的 MCP，因此必须使用远程 HTTPS 地址。OpenAI 当前的 MCP / Developer Mode 说明见：

<https://help.openai.com/en/articles/12584461-developer-mode-apps-and-full-mcp-connectors-in-chatgpt-beta>

操作流程：

1. 保持 Coding Tools MCP Desktop 中该 Workspace 为 **Running**。
2. 复制 GUI 显示的 `https://xxxx.trycloudflare.com/mcp`。
3. 打开 ChatGPT Web 的 Developer Mode / Apps（具体菜单名称可能随版本变化）。
4. 创建新的自定义 MCP / App，并填入上面的 HTTPS MCP URL。
5. ChatGPT 打开 OAuth 授权页面时，输入 Coding Tools MCP Desktop 中该 Workspace 的 **Authorization password**。
6. 完成连接并确认 `coding_tool` 工具已经出现。

### 非常重要：Quick Tunnel 换地址后的实测规则

Cloudflare Quick Tunnel 重启后可能得到新的 `trycloudflare.com` 地址。此时：

1. 在 ChatGPT 中创建新的 MCP，或者把原 MCP 更新到新的 URL。
2. OAuth 重新完成后，**新开一个 ChatGPT 对话再使用**。
3. 在新对话中先测试：`@coding tool 检查当前 Workspace`。

“新开对话”是本项目在 ChatGPT Web 上的兼容性实测规则，不是 MCP 协议本身的要求。旧对话可能仍缓存旧 MCP 工具句柄，从而出现 `disabled`，即使新 Tunnel 已经连接成功。

## 5. 日常使用

以后通常只需要双击：

`02-启动Coding Tools MCP.cmd`

它不会再创建第二个 MCP，也不会占用旧版的 `:8000` 端口。它只负责：

- 检查官方 GUI 和 cloudflared 是否存在。
- 创建/确认默认 `Desktop\CodingTool` Workspace。
- 收集上一次已经结束的本地 MCP 使用摘要。
- 让官方 GUI 的匿名 telemetry 进入本地 `debug` 输出，便于生成自己的使用记录，而不是由这个启动器再实现一套 MCP。
- 启动 `coding-tools-mcp-desktop` 官方 GUI。

真正的 Runtime、OAuth、Cloudflare Tunnel、端口和 Workspace 生命周期全部由官方 GUI 管理。

## 6. 想要固定 URL：优先使用 Cloudflare Fixed domain / Named Tunnel

如果你长期使用，不想每次 Quick Tunnel 重启后重新改 ChatGPT MCP 地址，推荐使用 **Cloudflare Named Tunnel + 自己的域名**，而不是为了 MCP 专门购买固定公网 IP。

基本结构：

`ChatGPT → https://mcp.example.com/mcp → Cloudflare Named Tunnel → 127.0.0.1:28766 → coding-tools-mcp`

步骤：

1. 在 Cloudflare 中创建 Named Tunnel。
2. 给 Tunnel 配置一个 Public Hostname，例如 `mcp.example.com`。
3. Origin Service 指向本机 Runtime，例如 `http://localhost:28766`。
4. 取得该 Tunnel 的 Token。
5. Coding Tools MCP Desktop 中选择：`Cloudflare` → `Fixed domain`。
6. 填入 Tunnel Token。
7. Public URL 填：`https://mcp.example.com`（不要在这里重复写 `/mcp`）。
8. 启动后 ChatGPT MCP Endpoint 使用：`https://mcp.example.com/mcp`。

Cloudflare Named Tunnel 的 URL 可以长期保持稳定。官方 Tunnel 设置文档：

<https://developers.cloudflare.com/tunnel/setup/>

## 7. 如果你有固定 IP，应该怎么做

先区分两种“固定 IP”。

### 只有局域网固定 IP

例如 `192.168.1.100`、`10.0.0.20`。这不能让 ChatGPT Web 直接访问你的电脑，仍然应该使用 Cloudflare Tunnel。

不要把下面这种地址填给 ChatGPT：

`http://192.168.1.100:28766/mcp`

### 真正的公网固定 IP

即使有公网固定 IP，也**不建议直接把 28766 暴露到公网**。官方 GUI 的 Runtime 默认绑定本机回环地址，这正是安全边界的一部分。

如果已经有 VPS / 固定公网 IP / 域名 / HTTPS 基础设施，可采用高级方案：

`ChatGPT → HTTPS 域名 → 反向代理或 FRP Server → FRP Client / 本机代理 → 127.0.0.1:28766`

要求至少包括：

- 使用域名和有效 HTTPS 证书。
- 公网入口只开放反向代理需要的端口，避免直接裸露 MCP Runtime。
- OAuth 保持开启。
- 如果使用 Coding Tools MCP Desktop 的 `FRP (externally managed)` 模式，FRP Client/Server 生命周期由你自己管理，GUI 不会替你启动 FRP。

如果你并没有现成的公网服务器基础设施，**Cloudflare Named Tunnel 通常比固定 IP + 端口转发 + TLS + FRP 更简单**。

## 8. 本地使用记录、模型和 Token

双击：

`05-使用记录.cmd`

记录保存在：

`%LOCALAPPDATA%\ChatGPT-LocalAccess-Setup\Usage\`

主要文件：

- `sessions.jsonl`：完整机器可读记录。
- `sessions.csv`：方便 Excel 查看。
- `active-sessions.json`：正在运行的 MCP Runtime 跟踪状态；Stop 后会自动转成完成记录。
- `model-history.jsonl`：你手动填写的模型标签历史。

通过新版 `02` 启动 GUI 时，会同时启动一个极轻量的本地 watcher。它只读取 Coding Tools MCP Desktop 自己的 `runtime.json` 和运行日志，不代理网络、不创建第二个 MCP，也不占用额外端口。

即使 Windows 下官方 Runtime 被直接 terminate、来不及写 `session_end`，watcher 仍能根据 Runtime 生命周期保存 Workspace、开始/结束时间、Tunnel 模式和 **`POST /mcp` 请求次数**。如果官方 debug telemetry 正常写出了 `tool_summary/session_end`，记录还会额外补充 MCP Tool Calls 和工具错误明细。

### 为什么模型需要手动填写一次

当前 `coding-tools-mcp` 收到的 MCP 请求元数据可以包含 MCP Client 信息，但**不会告诉本地 MCP 当前 ChatGPT 正在使用 GPT-5.6 Sol、其他模型，或模型的 reasoning 配置**。

因此 `05-使用记录.cmd` 第一次会允许你填写当前模型标签；以后切换模型时再运行一次并更新即可。记录会根据时间关联模型历史，而不会凭空猜模型。

### 为什么 Web Token 显示 N/A

ChatGPT Web 当前没有通过 MCP 请求把该对话的 `input_tokens / output_tokens / reasoning_tokens / total_tokens` 发送给本地 MCP。仅凭 `coding-tools-mcp` 无法得到网页端真正的 Token 账单。

因此记录字段会明确写：

- `web_tokens_exact: null`
- `web_token_status: unavailable_to_mcp`

本项目**不会用字符数、日志大小或“每次工具调用固定多少 Token”去伪造精确 Token 数**。如果未来 ChatGPT/MCP 正式暴露可信的 usage 字段，再升级为真实 Token 统计。

这仍然可以准确回答“是否通过这套本地 MCP 工作过、用了哪个 Workspace、产生了多少次 MCP HTTP 请求、会话持续多久”；在官方 summary 可用时还能看到具体 Tool Calls，并把模型标签一并留档。

## 9. Remote Desktop Commander：多电脑

同一个 Remote Desktop Commander 账号可以注册多台电脑。每台电脑是独立设备，不需要为每台电脑创建不同的 ChatGPT MCP。

新电脑首次注册：

1. 先运行 `01-安装.cmd`，确保 Node.js 可用。
2. 双击 `04-启动Remote Desktop Commander.cmd`。
3. 按浏览器/终端提示，用和其他电脑相同的账号授权。
4. 保持该窗口运行时，这台电脑保持在线。

## 10. 正常退出与排错

- Coding Tools MCP：优先在官方 GUI 里对 Workspace 点击 **Stop**，确认 Runtime/Tunnel 停止后再关 GUI。
- Remote Desktop Commander：直接关闭其终端窗口即可离线。
- 出问题先运行 `03-检查环境.cmd`。
- 如果 Quick Tunnel 已经换 URL，但新对话仍看不到工具，先确认 ChatGPT 中连接的是**新 URL 对应的新 MCP**，再检查 OAuth。
- 不要再启动任何历史 `:8000` MCP 脚本。

## 11. 安全边界

- Runtime 保持 `127.0.0.1` 回环绑定。
- 公网访问只通过 HTTPS Tunnel / 受控反向代理。
- 默认推荐 OAuth。
- `trusted` 仍然不等于可以跨 Workspace 随意读写；Workspace 文件边界应该保留。
- Cloudflare Token、OAuth Password 等不要写进 Git 仓库或公开分享。
- 使用记录默认只放 `%LOCALAPPDATA%`，不会提交到项目 Git。

## 12. 教程与相关项目

- 教程地址：<https://www.bilibili.com/video/BV1H38y6BEk3/>
- Coding MCP：<https://github.com/xyTom/coding-tools-mcp/tree/main>
- Cloudflare Tunnel：<https://github.com/cloudflare/cloudflared/releases>
- Remote Desktop Commander：进入 ChatGPT 网页端的插件 / Apps 搜索 **Remote Desktop Commander** 并安装。
