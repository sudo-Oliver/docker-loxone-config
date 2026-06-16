#!/bin/bash
set -e

VNC_PW="${VNC_PW:-changeme}"
VNC_USER="${VNC_USER:-kasm_user}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1920x1080}"
XLANG="${XLANG:-de}"
KEEP_APP_RUNNING="${KEEP_APP_RUNNING:-1}"
DISPLAY_NUM=":1"

# ── VNC auth ──────────────────────────────────────────────────────────────────
# KasmVNC uses username-based auth — vncpasswd -u <user> -w -r, password via stdin
# Format: "password\npassword\n" (set password; empty 3rd line = no view-only password)
mkdir -p ~/.vnc
printf '%s\n%s\n\n' "$VNC_PW" "$VNC_PW" | vncpasswd -u "$VNC_USER" -w -r
# KasmVNC writes to /etc/kasmvnc/kasmvnc_users.cfg, not ~/.vnc/passwd
[ -f ~/.vnc/passwd ] && chmod 600 ~/.vnc/passwd || true

# ── KasmVNC config ────────────────────────────────────────────────────────────
RES_W="${VNC_RESOLUTION%%x*}"
RES_H="${VNC_RESOLUTION##*x}"

cat > ~/.vnc/kasmvnc.yaml << EOF
desktop:
  resolution:
    width: ${RES_W}
    height: ${RES_H}
  allow_resize: true
network:
  websocket_port: 6901
  ssl:
    require_ssl: false
logging:
  log_writer_name: all
  log_dest: logfile
  level: 30
EOF

# ── Start KasmVNC ─────────────────────────────────────────────────────────────
# -noxstartup skips select-de.sh entirely — we start openbox ourselves below.
# kasmvncserver daemonizes by default; web UI on port 6901 via kasmvnc.yaml.
kasmvncserver "$DISPLAY_NUM" \
  -geometry "$VNC_RESOLUTION" \
  -depth 24 \
  -noxstartup

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

# ── Window manager + keyboard ─────────────────────────────────────────────────
openbox &
setxkbmap "$XLANG" 2>/dev/null || true

# ── FEX-Emu rootfs config (ARM64 containers only) ────────────────────────────
# HOME=/config is set at runtime by KasmVNC — build-time /root/.fex-emu is wrong dir.
# FEX needs: $HOME/.fex-emu/Config.json with {"Config":{"RootFS":"wine"}}
#            $HOME/.fex-emu/RootFS/wine  →  /opt/fex-rootfs (symlink)
if [ -d /opt/fex-rootfs ] && command -v FEXInterpreter >/dev/null 2>&1; then
  mkdir -p "$HOME/.fex-emu/RootFS"
  ln -sfn /opt/fex-rootfs "$HOME/.fex-emu/RootFS/wine"
  printf '{"Config":{"RootFS":"wine"}}\n' > "$HOME/.fex-emu/Config.json"
  echo "FEX: configured rootfs → /opt/fex-rootfs"
fi

# ── Application loop ──────────────────────────────────────────────────────────
# startapp.sh handles first-run installation and Wine startup.
# 'exec wine' inside startapp.sh replaces the subshell — when wine exits,
# the loop iteration ends and we either restart (KEEP_APP_RUNNING=1) or exit.
while true; do
  /startapp.sh || true
  if [ -f /tmp/install_failed ]; then
    echo "Installation failed — container idle. Fix errors and run: docker compose restart"
    sleep infinity
  fi
  if [ "$KEEP_APP_RUNNING" != "1" ]; then
    break
  fi
  echo "Loxone Config exited — restarting in 2s (set KEEP_APP_RUNNING=0 to disable)"
  sleep 2
done

# ── Cleanup ───────────────────────────────────────────────────────────────────
kasmvncserver -kill "$DISPLAY_NUM" 2>/dev/null || true
