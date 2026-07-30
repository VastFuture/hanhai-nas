#!/bin/bash
# sshx 服务包装器: 把 sshx --quiet 输出的会话地址写入 /run/sshx-url
# 进程退出(含被 systemd 杀掉)时清空地址文件, 避免落地页读到失效链接。
set -u
URL_FILE=/run/sshx-url
ERR_FILE=/run/sshx-url.err
: > "$URL_FILE"
: > "$ERR_FILE"
# sshx --quiet 仅把 URL 打到 stdout, 之后保持会话存活。
/usr/local/bin/sshx --quiet --shell /bin/bash --name "Hanhai NAS" >"$URL_FILE" 2>"$ERR_FILE"
RC=$?
: > "$URL_FILE"
: > "$ERR_FILE"
exit $RC
