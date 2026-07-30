#!/usr/bin/env bash
#
# 瀚海未来 · Hanhai NAS 控制台 一键安装脚本
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/VastFuture/hanhai-nas/main/install.sh | bash
#
#   下载后运行(支持参数):
#     bash install.sh [--with-opencode|--no-opencode] [--install-dir DIR] [--port N]
#
# 说明:
#   - 自动检测并安装依赖: curl / python3 / sshx
#   - opencode 为可选项: 交互式询问, 或用 --with-opencode / --no-opencode 指定
#     (curl|bash 管道模式下, 默认不安装 opencode)
#   - 安装完成后, 打开 http://<本机IP>:<端口>/ 即可在网页启停 sshx 远程终端
#

set -Eeo pipefail

# ==================== 默认配置 ====================
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/VastFuture/hanhai-nas/main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/hanhai-nas}"
HANHAI_PORT="${HANHAI_PORT:-3211}"
OPENCODE_PORT="${OPENCODE_PORT:-3210}"
RUNNER_DST="${RUNNER_DST:-/usr/local/bin/sshx-hanhai.sh}"
UNITS_DIR="${UNITS_DIR:-/etc/systemd/system}"
SSHX_URL_FILE="${SSHX_URL_FILE:-/run/sshx-url}"
WITH_OPENCODE="ask"   # ask | yes | no

# ==================== 颜色与日志 ====================
if [[ -t 1 ]]; then
  C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_C=$'\e[36m'; C_B=$'\e[1m'; C_0=$'\e[0m'
else
  C_R=""; C_G=""; C_Y=""; C_C=""; C_B=""; C_0=""
fi
log()  { printf "%s▶%s %s\n" "$C_C" "$C_0" "$*"; }
ok()   { printf "%s✓%s %s\n" "$C_G" "$C_0" "$*"; }
warn() { printf "%s!%s %s\n" "$C_Y" "$C_0" "$*" >&2; }
die()  { printf "%s✗%s %s\n" "$C_R" "$C_0" "$*" >&2; exit 1; }
trap 'die "安装中断 (脚本第 $LINENO 行)"' ERR

# ==================== 参数解析 ====================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-opencode) WITH_OPENCODE="yes"; shift;;
    --no-opencode)   WITH_OPENCODE="no";  shift;;
    --install-dir)   INSTALL_DIR="${2:?--install-dir 需要值}"; shift 2;;
    --port)          HANHAI_PORT="${2:?--port 需要值}"; shift 2;;
    --opencode-port) OPENCODE_PORT="${2:?--opencode-port 需要值}"; shift 2;;
    -h|--help)       sed -n '3,18p' "$0"; exit 0;;
    *) die "未知参数: $1 (用 --help 查看用法)";;
  esac
done

# ==================== 前置检查 ====================
[[ $EUID -eq 0 ]] || die "请以 root 运行: sudo bash install.sh"
command -v systemctl >/dev/null 2>&1 || die "未检测到 systemctl, 本脚本需要 systemd 环境"
[[ -d /run/systemd/system ]] || warn "systemd 似乎未以 PID 1 运行 (容器/WSL?), 服务可能无法启动"

printf "\n%s%s 瀚海未来 · Hanhai NAS 控制台 安装程序 %s\n\n" "$C_B" "$C_C" "$C_0"

# ==================== 包管理器探测 ====================
detect_pm() {
  if   command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf     >/dev/null 2>&1; then echo dnf
  elif command -v yum     >/dev/null 2>&1; then echo yum
  elif command -v pacman  >/dev/null 2>&1; then echo pacman
  elif command -v apk     >/dev/null 2>&1; then echo apk
  else echo none; fi
}
PM="$(detect_pm)"
pkg_install() {
  case "$PM" in
    apt)    apt-get update -qq >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$@";;
    dnf)    dnf install -y "$@";;
    yum)    yum install -y "$@";;
    pacman) pacman -S --noconfirm --needed "$@";;
    apk)    apk add --no-cache "$@";;
    *)      die "不支持的发行版, 请手动安装: $*";;
  esac
}

# ==================== 依赖: curl ====================
log "检查依赖..."
command -v curl >/dev/null 2>&1 || { log "未检测到 curl, 正在安装..."; pkg_install curl; }

# ==================== 依赖: python3 ====================
if ! command -v python3 >/dev/null 2>&1; then
  log "未检测到 python3, 正在安装..."
  pkg_install python3
fi
PYTHON_BIN="$(command -v python3)"
PYVER="$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
ok "python3 $PYVER ($PYTHON_BIN)"

# ==================== 依赖: sshx (必需) ====================
install_sshx() {
  log "安装 sshx (https://sshx.io)..."
  curl -sSf https://sshx.io/get | sh
}
if command -v sshx >/dev/null 2>&1; then
  ok "sshx 已安装 ($(sshx --version 2>/dev/null || echo))"
else
  install_sshx
  command -v sshx >/dev/null 2>&1 || die "sshx 安装失败, 请手动执行: curl -sSf https://sshx.io/get | sh"
  ok "sshx 安装完成"
fi
SSHX_BIN="$(command -v sshx)"

# ==================== 可选: opencode ====================
locate_opencode() {
  if command -v opencode >/dev/null 2>&1; then command -v opencode; return 0; fi
  for p in /usr/local/bin/opencode /usr/bin/opencode "$HOME/.opencode/bin/opencode" /root/.opencode/bin/opencode; do
    if [[ -x "$p" ]]; then echo "$p"; return 0; fi
  done
  return 1
}
try_install_opencode() {
  log "安装 opencode (https://opencode.ai)..."
  local found=""
  if bash -c 'curl -fsSL https://opencode.ai/install | bash' && found="$(locate_opencode 2>/dev/null)"; then
    OPENCODE_BIN="$found"; HAS_OPENCODE="yes"; ok "opencode 安装完成: $OPENCODE_BIN"
  else
    warn "opencode 安装失败 (控制台 opencode 区将显示未运行, sshx 不受影响)"
  fi
}

HAS_OPENCODE="no"; OPENCODE_BIN=""
if [[ "$WITH_OPENCODE" == "no" ]]; then
  warn "已指定 --no-opencode, 跳过 opencode"
else
  found="$(locate_opencode 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    OPENCODE_BIN="$found"; HAS_OPENCODE="yes"
    ok "检测到已安装 opencode: $OPENCODE_BIN"
  elif [[ "$WITH_OPENCODE" == "yes" ]]; then
    try_install_opencode
  else  # ask 模式且未安装
    do_install="no"
    if [[ -t 0 ]] || [[ -e /dev/tty ]]; then
      printf "%s?%s 是否同时安装 opencode (AI 编程服务)? [y/N] " "$C_Y" "$C_0"
      ans=""; read -r ans < /dev/tty 2>/dev/null || ans=""
      [[ "$ans" =~ ^[Yy]$ ]] && do_install="yes"
    else
      warn "非交互模式, 默认不安装 opencode (可用 --with-opencode 强制安装)"
    fi
    [[ "$do_install" == "yes" ]] && try_install_opencode
  fi
fi

# ==================== 下载项目文件 ====================
log "安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/public"
dl() { curl -fsSL "$1" -o "$2" || die "下载失败: $1"; }
dl "$REPO_RAW/server.py"         "$INSTALL_DIR/server.py"
dl "$REPO_RAW/public/index.html" "$INSTALL_DIR/public/index.html"
# 同步页面端口显示
sed -i "s/服务端口 : 3211/服务端口 : $HANHAI_PORT/" "$INSTALL_DIR/public/index.html" 2>/dev/null || true
ok "项目文件就位"

# ==================== 生成 sshx 启动包装器 (路径自适应) ====================
HOST_SHORT="$(hostname -s 2>/dev/null || echo hanhai-nas)"
cat > "$RUNNER_DST" <<EOF
#!/bin/bash
# 由 hanhai-nas 安装脚本生成; 把 sshx 会话地址写入 $SSHX_URL_FILE
set -u
URL_FILE=$SSHX_URL_FILE
ERR_FILE=$SSHX_URL_FILE.err
: > "\$URL_FILE"
: > "\$ERR_FILE"
$SSHX_BIN --quiet --shell /bin/bash --name "$HOST_SHORT" >"\$URL_FILE" 2>"\$ERR_FILE"
RC=\$?
: > "\$URL_FILE"
: > "\$ERR_FILE"
exit \$RC
EOF
chmod +x "$RUNNER_DST"
ok "sshx 包装器: $RUNNER_DST"

# ==================== 生成 systemd units ====================
log "写入 systemd units..."

cat > "$UNITS_DIR/hanhai.service" <<EOF
[Unit]
Description=Hanhai NAS Control Hub
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$PYTHON_BIN -u $INSTALL_DIR/server.py
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=3
Environment=HANHAI_PORT=$HANHAI_PORT
Environment=OPENCODE_SERVICE=opencode-web
Environment=SSHX_SERVICE=sshx
Environment=SSHX_URL_FILE=$SSHX_URL_FILE

[Install]
WantedBy=multi-user.target
EOF

cat > "$UNITS_DIR/sshx.service" <<EOF
[Unit]
Description=sshx Web Terminal (collaborative shell via sshx.io)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/rm -f $SSHX_URL_FILE ${SSHX_URL_FILE}.err
ExecStart=$RUNNER_DST
ExecStopPost=/bin/rm -f $SSHX_URL_FILE ${SSHX_URL_FILE}.err
Restart=on-failure
RestartSec=5
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF

if [[ "$HAS_OPENCODE" == "yes" ]]; then
cat > "$UNITS_DIR/opencode-web.service" <<EOF
[Unit]
Description=OpenCode Web Interface
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$OPENCODE_BIN serve --port $OPENCODE_PORT --hostname 0.0.0.0
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
else
  # 未装 opencode 时清理可能残留的旧 unit, 避免幽灵服务
  rm -f "$UNITS_DIR/opencode-web.service" 2>/dev/null || true
fi

# ==================== 启用服务 ====================
systemctl daemon-reload
log "启动控制面板 hanhai..."
systemctl enable hanhai.service >/dev/null 2>&1
systemctl restart hanhai.service

# sshx: 不开机自启, 按需在网页启动
systemctl disable sshx.service >/dev/null 2>&1 || true

if [[ "$HAS_OPENCODE" == "yes" ]]; then
  log "启动 opencode-web..."
  if systemctl enable --now opencode-web.service >/dev/null 2>&1; then
    ok "opencode-web 已启用"
  else
    warn "opencode-web 启动失败 (可能需要 API key 等配置); 控制台与 sshx 不受影响"
  fi
fi

# ==================== 健康检查 ====================
log "等待控制台响应..."
healthy=0
for _ in $(seq 1 15); do
  if curl -fsS "http://127.0.0.1:$HANHAI_PORT/api/health" >/dev/null 2>&1; then healthy=1; break; fi
  sleep 0.5
done
[[ $healthy -eq 1 ]] && ok "控制台已就绪 (HTTP $HANHAI_PORT)" || warn "控制台未在预期时间内响应, 请查: journalctl -u hanhai -n 30"

# ==================== 摘要 ====================
LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$LAN_IP" ]] || LAN_IP="<本机IP>"

cat <<EOF

${C_G}${C_B}╔══════════════════════════════════════════════════╗${C_0}
${C_G}${C_B}║   ✓ 瀚海未来 · Hanhai NAS 控制台 安装完成        ║${C_0}
${C_G}${C_B}╚══════════════════════════════════════════════════╝${C_0}

  控制台地址 :  ${C_C}http://${LAN_IP}:${HANHAI_PORT}/${C_0}
  安装目录   :  $INSTALL_DIR
  sshx 包装  :  $RUNNER_DST

  服务状态   :
    hanhai (控制台)   ${C_G}已启动 + 开机自启${C_0}
    sshx  (远程终端)  ${C_Y}未启动${C_0}  ← 请在网页点「启动」, 再点「直达」进入终端
EOF
if [[ "$HAS_OPENCODE" == "yes" ]]; then
  echo "    opencode-web      已安装  ($(systemctl is-active opencode-web 2>/dev/null || echo unknown))"
else
  echo "    opencode-web      未安装 (可选)"
fi
cat <<EOF

  常用命令   :
    systemctl status hanhai          # 控制台状态
    systemctl restart hanhai         # 重启控制台
    journalctl -u hanhai -f          # 实时日志
    systemctl enable sshx            # (可选) 让 sshx 开机自启

  卸载       :
    systemctl disable --now hanhai sshx
    rm -rf $INSTALL_DIR $RUNNER_DST $UNITS_DIR/{hanhai,sshx,opencode-web}.service
    systemctl daemon-reload

EOF
