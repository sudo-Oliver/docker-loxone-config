#!/bin/bash
set -e

VNC_PW="${VNC_PW:-changeme}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1920x1080}"
XLANG="${XLANG:-de}"
KEEP_APP_RUNNING="${KEEP_APP_RUNNING:-1}"
DISPLAY_NUM=":1"

# ── VNC auth ──────────────────────────────────────────────────────────────────
mkdir -p ~/.vnc
echo "$VNC_PW" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# ── KasmVNC config ────────────────────────────────────────────────────────────
RES_W="${VNC_RESOLUTION%%x*}"
RES_H="${VNC_RESOLUTION##*x}"

cat > ~/.vnc/kasmvnc.yaml << EOF
desktop:
  resolution:
    width: ${RES_W}
    height: ${RES_H}
  allow_resize: true
  color_depth: 24
network:
  websocket_port: 6901
  ssl:
    require_ssl: false
keyboard:
  remap_keys: {}
logging:
  log_writer_name: all
  log_dest: logfile
  level: 30
EOF

# ── Start KasmVNC ─────────────────────────────────────────────────────────────
# Daemonizes Xvnc + starts built-in web server on port 6901
vncserver "$DISPLAY_NUM" \
  -geometry "$VNC_RESOLUTION" \
  -depth 24 \
  -select-de none \
  -SecurityTypes VncAuth \
  -interface 0.0.0.0

export DISPLAY="$DISPLAY_NUM"

# ── Wait for X display ────────────────────────────────────────────────────────
TIMEOUT=30
for i in $(seq 1 $((TIMEOUT * 2))); do
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
  sleep 0.5
done

if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
  echo "ERROR: KasmVNC display $DISPLAY did not come up within ${TIMEOUT}s"
  exit 1
fi

echo "KasmVNC ready on display $DISPLAY — web UI at http://localhost:6901"

# ── Keyboard layout ───────────────────────────────────────────────────────────
setxkbmap "$XLANG" 2>/dev/null || true

# ── Application loop ──────────────────────────────────────────────────────────
# startapp.sh handles first-run installation and Wine startup.
# 'exec wine' inside startapp.sh replaces the subshell — when wine exits,
# the loop iteration ends and we either restart (KEEP_APP_RUNNING=1) or exit.
while true; do
  /startapp.sh || true
  if [ "$KEEP_APP_RUNNING" != "1" ]; then
    break
  fi
  echo "Loxone Config exited — restarting in 2s (set KEEP_APP_RUNNING=0 to disable)"
  sleep 2
done

# ── Cleanup ───────────────────────────────────────────────────────────────────
vncserver -kill "$DISPLAY_NUM" 2>/dev/null || true
