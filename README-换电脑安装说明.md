# ChatGPT Web 访问本地电脑：换机傻瓜安装包

这个目录用于在新的 Windows 电脑上快速恢复两条本地访问工作流：

- ChatGPT Web → Remote Desktop Commander → 本机文件 / 终端
- ChatGPT Web → 自定义 MCP → Cloudflare 临时 HTTPS Tunnel → coding-tools-mcp → 指定 Workspace

## 平时只需要记住 4 个文件

1. `01-安装.cmd`：新电脑第一次运行，安装/检查依赖并准备 Workspace。
2. `02-启动Web访问.cmd`：启动 coding-tools + Cloudflare 临时 Tunnel。
3. `03-检查环境.cmd`：出问题时检查本地依赖和 Workspace。
4. `04-启动Remote Desktop Commander.cmd`：注册/启动当前电脑为 Remote Desktop Commander 设备。

## 新电脑第一次安装

把整个 `ChatGPT-LocalAccess-Setup` 文件夹复制到新电脑桌面，然后双击 `01-安装.cmd`。

安装器会检查/安装：

- Python 3.11+
- uv / uvx
- coding-tools-mcp
- Node.js 18+
- cloudflared 官方 Windows x64 MSI

如果没有手动指定 Workspace，安装器会自动创建当前用户桌面的 `CodingTool` 文件夹，并写入 `workspace.txt`。

如果要让 coding-tools 操作其他项目：

- 把需要操作的内容放进 `桌面\CodingTool`；或
- 直接把 `workspace.txt` 改成目标项目的绝对路径。

## Remote Desktop Commander：多电脑用法

Remote Desktop Commander 不是“一次只能连接一台电脑”。

同一个 ChatGPT / Remote Desktop Commander 账号可以注册多台电脑；每台电脑都会拥有独立的设备名和 `deviceId`。ChatGPT 在调用工具时可以指定设备，因此不会因为多电脑而必须创建多个插件。

新电脑首次注册：

1. 先运行 `01-安装.cmd`，确保 Node.js 18+ 可用。
2. 双击 `04-启动Remote Desktop Commander.cmd`。
3. 脚本会运行：`npx -y @wonderwhy-er/desktop-commander@latest remote`。
4. 首次运行时，按终端/浏览器提示完成设备授权。
5. 必须登录和其他电脑相同的 Remote Desktop Commander 账号，才能让设备出现在同一个列表里。
6. 授权完成后保持该窗口开启；窗口关闭后，这台电脑会离线。

在第二、第三台电脑重复以上流程即可。不要为每台电脑分别创建一个 ChatGPT MCP 插件。

验证方法：在 ChatGPT 中让它“列出 Remote Desktop Commander 当前设备”，应能同时看到多台 `online` 设备。

## coding-tools + Cloudflare 临时 Tunnel

双击 `02-启动Web访问.cmd` 后会自动：

1. 读取 `workspace.txt`。
2. 启动 `coding-tools-mcp`，仅绑定 `127.0.0.1:8000`。
3. 开启 OAuth。
4. 启动 cloudflared 临时 Tunnel。
5. 等待 `https://xxxx.trycloudflare.com` 地址。
6. 自动生成最终 `https://xxxx.trycloudflare.com/mcp`。
7. 自动复制 MCP URL 到剪贴板。
8. 同时显示本次 OAuth 授权密码。

## ChatGPT 浏览器中的 coding-tools 设置

1. 打开 ChatGPT Web。
2. 确认开发者模式已启用。
3. 新建或刷新自定义 MCP。
4. 粘贴脚本复制的 `https://xxxx.trycloudflare.com/mcp`。
5. 扫描工具。
6. 如果出现 OAuth 授权页，输入启动窗口显示的授权密码。
7. 创建/启用 MCP 后，在聊天中选择它使用。

临时 Tunnel 每次重启通常都会得到新的 `trycloudflare.com` 地址，因此需要在 ChatGPT 中刷新/更新 MCP 地址。

## 安全规则

- coding-tools 本地服务只绑定 `127.0.0.1`。
- Web 访问必须经过 HTTPS Tunnel。
- 脚本默认使用 `safe` 权限模式。
- 不要把 `dangerous` 模式用于普通开发电脑。
- 临时 Tunnel 用完后，在启动窗口按 Enter，脚本会停止 MCP 和 Tunnel。
- `CURRENT_CONNECTION.txt` 包含当次临时 OAuth 密码，不要上传到 Git 或公开分享。
- Remote Desktop Commander 只应在你自己的受信任电脑上注册，并使用自己的账号授权。

## 默认 Workspace

默认值不是任何人的项目路径，而是当前 Windows 用户自己的：

`%USERPROFILE%\Desktop\CodingTool`

安装器会根据当前 Windows 用户自动解析真正的桌面路径并创建该文件夹。

需要切换项目时，只改 `workspace.txt` 为新的绝对路径即可；其他脚本不需要修改。

## 推荐换机顺序

`01-安装.cmd` → `04-启动Remote Desktop Commander.cmd` 完成同账号设备注册 → 需要 coding-tools 时再运行 `02-启动Web访问.cmd` → 有问题运行 `03-检查环境.cmd`。

## 正常退出

- `04-启动Remote Desktop Commander.cmd`：可以直接关闭窗口；设备会变为离线，下次重新运行即可上线。
- `02-启动Web访问.cmd`：建议在窗口中按 Enter 正常退出，脚本会停止 coding-tools-mcp 和 cloudflared。
- `02` 正常退出时会删除 `CURRENT_CONNECTION.txt`，避免临时 OAuth 密码继续留在磁盘上。
- 不建议直接关闭 `02` 的窗口，因为其子进程可能继续运行；如误关，可用 `03-检查环境.cmd` 或任务管理器确认残留进程。
