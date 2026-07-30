#!/usr/bin/env python3
"""
瀚海未来 · Hanhai Future Service Control Hub
零依赖 systemd 服务控制面板后端(Python 标准库,无需 pip install)
启动: python3 server.py
"""
import http.server
import socketserver
import subprocess
import json
import os
import re
import threading
import time
import urllib.parse
from pathlib import Path

PORT = int(os.environ.get("HANHAI_PORT", "3211"))
SERVICE = os.environ.get("OPENCODE_SERVICE", "opencode-web")
PUBLIC_DIR = Path(__file__).resolve().parent / "public"

# sshx 远程终端服务
SSHX_SERVICE = os.environ.get("SSHX_SERVICE", "sshx")
SSHX_URL_FILE = Path(os.environ.get("SSHX_URL_FILE", "/run/sshx-url"))

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
}


def run(cmd, timeout=15):
    try:
        p = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return {
            "ok": p.returncode == 0,
            "stdout": p.stdout or "",
            "stderr": p.stderr or "",
            "code": p.returncode,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "stdout": "", "stderr": "timeout", "code": -1}


def get_status():
    state = run(f"systemctl is-active {SERVICE}")
    is_active = (state["stdout"] or "").strip() == "active"

    show = run(
        f"systemctl show {SERVICE} "
        "--property=MainPID,Description,LoadState,SubState,ActiveState,ActiveEnterTimestamp"
    )
    props = {}
    for line in (show["stdout"] or "").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()

    active_enter_sec = None
    ts = props.get("ActiveEnterTimestamp", "")
    if ts:
        d = run(f'date -d "{ts}" +%s 2>/dev/null')
        v = (d["stdout"] or "").strip()
        if re.fullmatch(r"\d+", v):
            active_enter_sec = int(v)

    detail = run(f"systemctl status {SERVICE} --no-pager -l 2>&1")

    return {
        "service": SERVICE,
        "port": PORT,
        "active": is_active,
        "state": (state["stdout"] or "").strip()
        or ("unknown" if state["code"] != 0 else "inactive"),
        "pid": props.get("MainPID")
        if props.get("MainPID") not in (None, "0")
        else None,
        "description": props.get("Description", ""),
        "loadState": props.get("LoadState", ""),
        "subState": props.get("SubState", ""),
        "activeState": props.get("ActiveState", ""),
        "activeEnterSec": active_enter_sec,
        "detail": (detail["stdout"] or "").strip(),
        "lastAction": dict(_last_action),
    }


ACTIONS = {"start": "启动", "stop": "停止", "restart": "重启"}

# 最近一次操作的执行结果(供前端轮询反馈真实成败)
_last_action = {"op": None, "ok": None, "ts": 0, "message": ""}


def _exec_action(op):
    """后台线程执行 systemctl,避免 stop/restart 阻塞 HTTP 响应。

    systemctl stop 会阻塞至服务真正停止(opencode 优雅关闭可能耗时数十秒)。
    若同步等待,前端会在 12s 超时并误报"请求失败",而服务其实正在停止中。
    故改为异步:HTTP 立即返回"已提交",真实成败写入 _last_action 供轮询读取。
    """
    cmd = f"systemctl {op} {SERVICE}"
    ok, msg = False, ""
    try:
        p = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=180
        )
        if p.returncode == 0:
            ok = True
        else:
            p2 = subprocess.run(
                f"sudo -n {cmd}", shell=True, capture_output=True, text=True, timeout=180
            )
            ok = p2.returncode == 0
            msg = (p2.stderr or p.stderr or "").strip()
    except subprocess.TimeoutExpired:
        ok, msg = False, "操作超时(服务仍在处理,请观察状态变化)"
    except Exception as e:
        ok, msg = False, str(e)
    name = ACTIONS.get(op, op)
    _last_action.update(
        {
            "op": op,
            "ok": ok,
            "ts": time.time(),
            "message": msg or (f"{name}完成" if ok else f"{name}失败"),
        }
    )


def do_action(op):
    if op not in ACTIONS:
        return {"ok": False, "message": "非法操作"}
    name = ACTIONS[op]
    threading.Thread(target=_exec_action, args=(op,), daemon=True).start()
    return {"ok": True, "message": f"{name}指令已提交,状态正在更新…"}


# ===== sshx 远程终端 =====
_sshx_last_action = {"op": None, "ok": None, "ts": 0, "message": ""}


def _read_sshx_url():
    try:
        if SSHX_URL_FILE.is_file():
            txt = SSHX_URL_FILE.read_text(encoding="utf-8", errors="ignore").strip()
            if txt.startswith("http"):
                return txt
    except Exception:
        pass
    return ""


def get_sshx_status():
    state = run(f"systemctl is-active {SSHX_SERVICE}")
    is_active = (state["stdout"] or "").strip() == "active"
    show = run(
        f"systemctl show {SSHX_SERVICE} "
        "--property=MainPID,LoadState,SubState,ActiveState"
    )
    props = {}
    for line in (show["stdout"] or "").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    detail = run(f"systemctl status {SSHX_SERVICE} --no-pager -l 2>&1")
    return {
        "service": SSHX_SERVICE,
        "active": is_active,
        "state": (state["stdout"] or "").strip()
        or ("unknown" if state["code"] != 0 else "inactive"),
        "pid": props.get("MainPID")
        if props.get("MainPID") not in (None, "0")
        else None,
        "url": _read_sshx_url(),
        "detail": (detail["stdout"] or "").strip(),
        "lastAction": dict(_sshx_last_action),
    }


def _exec_sshx_action(op):
    cmd = f"systemctl {op} {SSHX_SERVICE}"
    ok, msg = False, ""
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        if p.returncode == 0:
            ok = True
        else:
            p2 = subprocess.run(
                f"sudo -n {cmd}", shell=True, capture_output=True, text=True, timeout=60
            )
            ok = p2.returncode == 0
            msg = (p2.stderr or p.stderr or "").strip()
    except subprocess.TimeoutExpired:
        ok, msg = False, "操作超时"
    except Exception as e:
        ok, msg = False, str(e)
    name = ACTIONS.get(op, op)
    _sshx_last_action.update(
        {
            "op": op,
            "ok": ok,
            "ts": time.time(),
            "message": msg or (f"{name}完成" if ok else f"{name}失败"),
        }
    )


def do_sshx_action(op):
    if op not in ACTIONS:
        return {"ok": False, "message": "非法操作"}
    name = ACTIONS[op]
    threading.Thread(target=_exec_sshx_action, args=(op,), daemon=True).start()
    return {"ok": True, "message": f"sshx {name}指令已提交,状态正在更新…"}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, body=b"", ctype="application/json; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = urllib.parse.unquote(parsed.path)
        if path == "/api/status":
            return self._send(200, json.dumps(get_status(), ensure_ascii=False))
        if path == "/api/sshx/status":
            return self._send(200, json.dumps(get_sshx_status(), ensure_ascii=False))
        if path == "/api/health":
            return self._send(
                200,
                json.dumps(
                    {"ok": True, "service": SERVICE, "ts": int(time.time() * 1000)},
                    ensure_ascii=False,
                ),
            )
        rel = "/index.html" if path == "/" else path
        full = (PUBLIC_DIR / rel.lstrip("/")).resolve()
        try:
            full.relative_to(PUBLIC_DIR.resolve())
        except ValueError:
            return self._send(403, "Forbidden", "text/plain; charset=utf-8")
        if full.is_file():
            data = full.read_bytes()
            ctype = MIME.get(full.suffix, "application/octet-stream")
            return self._send(200, data, ctype)
        return self._send(404, "404 Not Found", "text/plain; charset=utf-8")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length:
            self.rfile.read(length)
        parsed = urllib.parse.urlparse(self.path)
        path = urllib.parse.unquote(parsed.path)
        m = re.match(r"^/api/(start|stop|restart)$", path)
        if m:
            res = do_action(m.group(1))
            return self._send(
                200 if res["ok"] else 500, json.dumps(res, ensure_ascii=False)
            )
        m2 = re.match(r"^/api/sshx/(start|stop|restart)$", path)
        if m2:
            res = do_sshx_action(m2.group(1))
            return self._send(
                200 if res["ok"] else 500, json.dumps(res, ensure_ascii=False)
            )
        return self._send(404, json.dumps({"ok": False, "message": "not found"}))


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    print("\n  瀚海未来 · Hanhai Future")
    print(f"  控制台已启动 → http://localhost:{PORT}")
    print(f"  管理服务: {SERVICE}\n")
    try:
        Server(("0.0.0.0", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\n  已停止。再见。")
