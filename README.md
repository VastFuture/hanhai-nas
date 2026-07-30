# 瀚海未来 · Hanhai NAS Control Hub

> 为飞牛 NAS 打造的深海科幻风 Web 控制台，一站式管理 `opencode-web` AI 编程服务与 `sshx` 远程终端。

深海星空视觉 · 玻璃拟态卡片 · 发光状态球 · Canvas 粒子背景 · 零第三方依赖后端。

---

## ⚡ 一键安装（推荐）

只需一行命令，跑完即可通过网页启停 sshx 远程终端：

```bash
curl -fsSL https://raw.githubusercontent.com/VastFuture/hanhai-nas/main/install.sh | bash
```

> 需要 root 权限（`sudo`）与 systemd 环境。脚本会自动检测并安装缺失的 `curl` / `python3` / `sshx`。

### 安装选项

| 参数 | 说明 |
|------|------|
| `--with-opencode` | 同时安装 opencode（AI 编程服务） |
| `--no-opencode` | 明确跳过 opencode（sshx 控制不受影响） |
| `--install-dir DIR` | 安装目录（默认 `/opt/hanhai-nas`） |
| `--port N` | 控制台端口（默认 `3211`） |
| `--opencode-port N` | opencode 服务端口（默认 `3210`） |

**opencode 的选择逻辑：**
- 不带参数 + 交互终端：会询问 `[y/N]`
- 不带参数 + `curl|bash` 非交互模式：**默认不装**（仅装控制台 + sshx）
- 系统已装 opencode：自动纳入管理（可用 `--no-opencode` 强制排除）

下载到本地再运行（便于传参 / 查看源码）：

```bash
curl -fsSL https://raw.githubusercontent.com/VastFuture/hanhai-nas/main/install.sh -o install.sh
bash install.sh --no-opencode --port 3211
```

### 安装后

1. 浏览器打开脚本输出的地址（如 `http://<NAS-IP>:3211/`）
2. 在 **sshx 区** 点「启动」→ 生成端到端加密的终端地址
3. 点「直达」在新窗口进入终端，或「复制地址」分享

> sshx 默认**不开机自启**，需在网页手动启动；如需开机自启：`sudo systemctl enable sshx`。
> 卸载见文末 [卸载](#-卸载) 章节。

---

## ✨ 功能特性

### 控制台核心
- **双服务管控**：同时管理 `opencode-web`（AI 编程服务）与 `sshx`（远程终端）
- **发光状态球**：随服务状态实时变色（运行中绿 / 已停止灰 / 已失败红 / 切换中金 / 连接中青）
- **一键启停**：启动 / 重启 / 停止，按钮 loading + Toast 反馈
- **实时状态输出**：可展开面板，显示完整 `systemctl status` 文本，定时轮询刷新
- **运行指标**：PID、Uptime、Load 状态
- **页脚时钟**：实时系统时间

### opencode-web 区
- 查看状态、PID、运行时长、Load 状态
- 异步动作 + `lastAction` 轮询反馈（解决 stop/restart 阻塞导致的「报失败却实际成功」假象）
- 完整 `systemctl status` 输出

### sshx 远程终端区
- 实时显示端到端加密的会话地址 `https://sshx.io/s/{id}#{key}`
- **复制地址**：一键复制到剪贴板（带 `execCommand` 回退）
- **直达**：`window.open(url, '_blank', 'noopener')` 新窗口直接打开终端
- 启动 / 重启 / 停止 控制
- 在线 / 离线 徽标
- 可展开实时状态输出

---

## 🏗 系统架构

```
                         ┌───────────────────────────────┐
   浏览器 ──HTTP:3211──▶ │  控制面板 hanhai.service        │
                         │  (Python stdlib http.server)   │
                         └───────────────┬───────────────┘
                                         │ systemctl {status,start,stop,restart}
                          ┌──────────────┴──────────────┐
                          ▼                             ▼
              ┌────────────────────┐      ┌─────────────────────┐
              │ opencode-web       │      │ sshx.service        │
              │ :3210 AI 编程服务  │      │ → sshx.io 全球 mesh │
              └────────────────────┘      │ → 写出会话 URL       │
                                          │   /run/sshx-url     │
                                          └─────────────────────┘
```

### 端口与服务关系（重要）

| 服务 | 端口 | 说明 |
|------|------|------|
| 控制面板 `hanhai` | **3211** | 本落地页，浏览器访问入口 |
| `opencode-web` | **3210** | 被管理的 AI 编程业务服务 |
| `sshx` | — | 出站连接 sshx.io，不在本地监听端口 |

三者相互独立：控制面板自身崩溃不会影响业务服务，反之亦然。

---

## 📁 目录结构

```
hanhai-nas/
├── install.sh                # ⚡ 一键安装脚本（推荐入口）
├── server.py                 # Python 后端（标准库，零依赖）
├── public/
│   └── index.html            # 前端单页（内嵌 CSS/JS/Canvas/SVG）
├── deploy/                   # systemd 部署件（参考）
│   ├── hanhai.service        # 控制面板 unit
│   ├── opencode-web.service  # 被管理业务服务 unit
│   ├── sshx.service          # sshx 远程终端 unit
│   └── sshx-hanhai.sh        # sshx 启动包装器（捕获会话地址）
└── README.md
```

---

## 🛠 手动安装（进阶）

> 大多数用户请直接使用 [⚡ 一键安装](#-一键安装推荐)。本节供希望手工控制每一步、或在无外网环境下离线部署的用户参考。

### 1. 前置条件

- Linux + systemd（开发/运行环境为飞牛 NAS / `FE-NAS`）
- Python 3.8+（无需 pip，纯标准库）
- root 权限（控制 systemd 服务所需）
- `curl`、`sshx`（见下）
- 联网（sshx 需出站连接 `sshx.io`）

### 2. 安装 sshx

```bash
curl -sSf https://sshx.io/get | sh
```

### 3. 部署控制面板

```bash
# 拉取代码
git clone https://github.com/VastFuture/hanhai-nas.git
cd hanhai-nas

# 安装到 /opt/hanhai-nas（或自定义路径，需同步修改 unit 的 WorkingDirectory）
sudo mkdir -p /opt/hanhai-nas
sudo cp server.py public/ -r /opt/hanhai-nas/

# 安装 sshx 包装器
sudo cp deploy/sshx-hanhai.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/sshx-hanhai.sh

# 安装 systemd units
sudo cp deploy/*.service /etc/systemd/system/
sudo systemctl daemon-reload

# 启用控制面板（开机自启）
sudo systemctl enable --now hanhai

# sshx 按需启动（默认不开机自启，在落地页手动启动）
sudo systemctl enable sshx    # 如希望开机自启，取消注释
```

打开浏览器访问 `http://<NAS-IP>:3211/`。

### 4. 业务服务 opencode-web（可选）

`opencode-web.service` 是被管理的 AI 编程服务。若需联网代理（如 mihomo），请在 unit 的 `[Service]` 段补充 `Environment=HTTPS_PROXY=...`；按需调整 `ExecStart` 路径后启用：

```bash
sudo systemctl enable --now opencode-web
```

---

## ⚙️ 配置说明

### 环境变量（控制面板 `hanhai.service`）

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HANHAI_PORT` | `3211` | 控制面板监听端口 |
| `OPENCODE_SERVICE` | `opencode-web` | 被管理的业务 systemd 服务名 |
| `SSHX_SERVICE` | `sshx` | sshx 的 systemd 服务名 |
| `SSHX_URL_FILE` | `/run/sshx-url` | sshx 会话地址写入文件 |

修改后执行 `systemctl restart hanhai` 生效。

### sshx 会话地址机制

`sshx-hanhai.sh` 以 `--quiet` 模式运行 sshx，将其 stdout（仅一行 URL）重定向到 `/run/sshx-url`：

- 服务启动后，落地页通过 `/api/sshx/status` 读取该文件获得实时地址
- 服务停止（`ExecStopPost`）或自然退出时，脚本清空该文件，避免落地页展示失效链接
- **每次启动 / 重启都会生成全新地址**（旧会话随之失效）

---

## 🔌 HTTP API

### opencode-web

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/status` | 返回 opencode-web 状态 JSON |
| POST | `/api/start` | 启动 opencode-web |
| POST | `/api/stop` | 停止 opencode-web |
| POST | `/api/restart` | 重启 opencode-web |
| GET | `/api/health` | 健康检查 |

### sshx

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/sshx/status` | 返回 sshx 状态 + 实时会话地址 |
| POST | `/api/sshx/start` | 启动 sshx |
| POST | `/api/sshx/stop` | 停止 sshx |
| POST | `/api/sshx/restart` | 重启 sshx（生成新地址） |

### `/api/sshx/status` 返回示例

```json
{
  "service": "sshx",
  "active": true,
  "state": "active",
  "pid": "3039796",
  "url": "https://sshx.io/s/pjte6YfBBI#ML08ly1jcymqXV",
  "detail": "● sshx.service - sshx Web Terminal ...",
  "lastAction": { "op": null, "ok": null, "ts": 0, "message": "" }
}
```

---

## 🖱 页面操作说明

- **状态球颜色**：绿=运行中，灰=已停止，红=已失败，金=切换中，青=连接中
- **opencode-web 区**：启动 / 重启 / 停止 + 可展开实时状态
- **sshx 区**：
  - 地址栏（点击亦可跳转）
  - **复制地址** → 写入剪贴板
  - **直达** → 新窗口打开 sshx 终端
  - 启动 / 重启 / 停止 + 可展开实时状态

---

## ⚠️ 重要提醒

1. **opencode-web 即当前 AI 对话所依赖的服务**。在控制台点击「停止 / 重启」会**立即中断当前会话**（重启后可恢复）。
2. **sshx 地址即访问凭证**。URL 中的 `#key` 片段是端到端加密密钥，**持有者拥有该 shell 的完全控制权**，请仅分享给可信对象。重启会生成新地址，旧地址立即失效。
3. 控制面板须以 **root** 运行方能通过 systemctl 控制系统服务；否则需为运行账号配置 sudo 免密。
4. sshx 默认**不开机自启**，需在落地页手动启动；如需开机自启执行 `systemctl enable sshx`。

---

## 🔧 故障排查

### 打不开页面

```bash
systemctl is-active hanhai            # 应为 active
ss -tlnp | grep 3211                  # 应见 0.0.0.0:3211
journalctl -u hanhai -n 30            # 查看报错
```

### 局域网打不开（防火墙）

```bash
# firewalld（飞牛 NAS / CentOS / RHEL）
firewall-cmd --add-port=3211/tcp --permanent && firewall-cmd --reload
# ufw（Ubuntu / Debian）
ufw allow 3211/tcp
```

### sshx 地址不出现

```bash
systemctl status sshx                 # 是否 active
cat /run/sshx-url                     # 地址文件是否存在
journalctl -u sshx -n 30              # 排查：多为无法连接 sshx.io
# 若需代理（如 GFW 环境），在 sshx.service 增加 Environment=HTTPS_PROXY=...
```

### 按钮操作失败（权限不足）

```bash
# 确认 hanhai.service 中 User=root，或配置 sudo 免密
echo "hanhai ALL=(ALL) NOPASSWD: /bin/systemctl" >> /etc/sudoers.d/hanhai
```

---

## 🛠 技术栈

| 层 | 技术 |
|----|------|
| 后端 | Python 3 · 标准库 `http.server` + `subprocess` + `threading` |
| 前端 | 原生 HTML / CSS / JS · Canvas 2D 粒子 · SVG · CSS 玻璃拟态 |
| 远程终端 | [sshx](https://github.com/ekzhang/sshx) v0.4.x（sshx.io 全球 mesh） |
| 部署 | systemd |
| 依赖 | **无**（零第三方包） |

---

## 💡 设计要点

- **异步动作 + 轮询反馈**：`systemctl stop/restart` 可能阻塞数十秒（opencode 优雅关闭）。后端在后台线程执行，HTTP 立即返回「已提交」，真实成败写入 `lastAction`，前端轮询状态时比对时间戳，仅真实失败才二次提示——避免「报失败却实际停止」的假象。
- **地址生命周期管理**：sshx 会话地址仅在服务运行时有效；停止时通过 `ExecStopPost` + 脚本退出钩子双重清理，保证落地页永不展示失效链接。
- **零依赖**：后端纯 Python 标准库，NAS 上无需 `pip install` 即可运行。

---

## 📝 运维速查

```bash
# 控制面板
systemctl {status,restart,stop} hanhai
journalctl -u hanhai -f

# 业务服务
systemctl {status,restart,start,stop} opencode-web

# sshx 远程终端
systemctl {status,restart,start,stop} sshx
systemctl enable sshx          # 恢复开机自启
systemctl disable sshx         # 关闭开机自启
cat /run/sshx-url              # 查看当前会话地址
```

---

## 🧹 卸载

```bash
# 停止并禁用服务
sudo systemctl disable --now hanhai sshx opencode-web 2>/dev/null

# 删除安装产物（路径以实际安装为准，默认如下）
sudo rm -rf /opt/hanhai-nas /usr/local/bin/sshx-hanhai.sh
sudo rm -f /etc/systemd/system/{hanhai,sshx,opencode-web}.service
sudo systemctl daemon-reload
```

> 卸载不会移除 `sshx` / `opencode` 二进制本身（它们由各自的官方安装器安装）。如需一并删除，请参考其官方文档。

---

## 📜 License

MIT
