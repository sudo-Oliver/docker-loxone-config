#!/usr/bin/env bash
set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

print_ok()   { echo -e "${GREEN}✓${NC} $1"; }
print_warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
print_info() { echo -e "${CYAN}→${NC} $1"; }
print_err()  { echo -e "${RED}✗${NC} $1"; }

print_header() {
  echo -e "\n${BOLD}${CYAN}=== Loxone Config Docker Setup ===${NC}\n"
}

# ── detect platform ───────────────────────────────────────────────────────────
rosetta_available() {
  [ -f /usr/libexec/rosetta ]
}

ensure_qemu_binfmt() {
  echo ""
  echo -e "${BOLD}QEMU binfmt setup${NC}"
  echo "ARM64+QEMU mode requires i386 binfmt registered on the host kernel."

  if [ -f /proc/sys/fs/binfmt_misc/qemu-i386 ] || \
     docker run --rm --platform linux/386 alpine echo ok &>/dev/null 2>&1; then
    print_ok "i386 binfmt already registered"
    return 0
  fi

  echo ""
  print_warn "i386 binfmt not detected. Running one-time registration:"
  echo "  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
  echo ""
  read -r -p "Run it now? [Y/n]: " ans
  case "${ans:-Y}" in
    [Yy]*)
      docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
      print_ok "QEMU binfmt registered (survives until host reboot)"
      echo ""
      print_info "Re-run after reboot or add to startup script"
      ;;
    *)
      print_warn "Skipped. Run manually before docker compose up -d --build:"
      echo "  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
      ;;
  esac
}

detect_platform() {
  local arch os
  arch=$(uname -m)
  os=$(uname -s)

  PLATFORM="linux/amd64"
  PLATFORM_CLASS="amd64"     # amd64 | arm64 | 386
  QEMU_BINFMT_NEEDED=false

  case "$arch" in
    arm64|aarch64)
      if [ "$os" = "Darwin" ]; then
        print_ok "Apple Silicon Mac (ARM64)"
        if rosetta_available; then
          PLATFORM="linux/amd64"
          PLATFORM_CLASS="amd64"
          print_ok "Rosetta 2 found → linux/amd64 via Rosetta (primary, fastest)"
        else
          PLATFORM="linux/arm64"
          PLATFORM_CLASS="arm64"
          QEMU_BINFMT_NEEDED=true
          print_warn "Rosetta 2 not found → linux/arm64 + QEMU-user (fallback)"
        fi
      else
        PLATFORM="linux/arm64"
        PLATFORM_CLASS="arm64"
        QEMU_BINFMT_NEEDED=true
        print_ok "Linux ARM64"
      fi
      ;;
    x86_64)
      PLATFORM="linux/amd64"
      PLATFORM_CLASS="amd64"
      print_ok "x86_64 ($os) — native performance"
      ;;
    i386|i686)
      PLATFORM="linux/386"
      PLATFORM_CLASS="386"
      print_ok "32-bit x86 — using original Alpine/386 image"
      ;;
    *)
      print_warn "Unknown arch '$arch' — defaulting to linux/amd64"
      ;;
  esac
}

# ── display backend choice ────────────────────────────────────────────────────
setup_backend() {
  echo ""
  echo -e "${BOLD}Display Backend${NC}"
  echo ""
  echo -e "  ${BOLD}1) KasmVNC${NC} ${GREEN}(recommended)${NC}"
  echo "     WebP/JPEG adaptive streaming, full clipboard, dynamic resolution,"
  echo "     file upload/download, no 8-char password limit"
  echo "     Access: http://localhost:6901"
  echo ""
  echo -e "  ${BOLD}2) Classic noVNC${NC} ${CYAN}(legacy / fallback)${NC}"
  echo "     Original jlesage/baseimage-gui stack (Xvnc + noVNC)"
  echo "     VNC password max 8 chars, static resolution"
  echo "     Access: http://localhost:5800"
  echo ""

  if [ "$PLATFORM_CLASS" = "386" ]; then
    print_warn "32-bit x86: KasmVNC not available — using Classic"
    BACKEND="classic"
    return
  fi

  read -r -p "Choose backend [1/2] (default: 1): " ans
  case "${ans:-1}" in
    2) BACKEND="classic" ;;
    *) BACKEND="kasmvnc" ;;
  esac

  if [ "$BACKEND" = "kasmvnc" ]; then
    print_ok "KasmVNC selected"
    if [ "$QEMU_BINFMT_NEEDED" = "true" ]; then
      ensure_qemu_binfmt
    fi
  else
    print_ok "Classic noVNC selected"
    if [ "$QEMU_BINFMT_NEEDED" = "true" ]; then
      ensure_qemu_binfmt
    fi
  fi
}

# ── resolve dockerfile + compose files ───────────────────────────────────────
resolve_dockerfile() {
  case "${BACKEND}:${PLATFORM_CLASS}" in
    kasmvnc:amd64) DOCKERFILE="Dockerfile.kasmvnc";      COMPOSE_FILE="docker-compose.yml:docker-compose.kasmvnc.yml" ;;
    kasmvnc:arm64) DOCKERFILE="Dockerfile.arm64-kasmvnc"; COMPOSE_FILE="docker-compose.yml:docker-compose.kasmvnc.yml" ;;
    classic:amd64) DOCKERFILE="Dockerfile.amd64";         COMPOSE_FILE="docker-compose.yml" ;;
    classic:arm64) DOCKERFILE="Dockerfile.arm64-qemu";    COMPOSE_FILE="docker-compose.yml" ;;
    *:386)         DOCKERFILE="Dockerfile";               COMPOSE_FILE="docker-compose.yml" ;;
    *)             DOCKERFILE="Dockerfile.kasmvnc";       COMPOSE_FILE="docker-compose.yml:docker-compose.kasmvnc.yml" ;;
  esac

  print_info "Platform: ${BOLD}$PLATFORM${NC}  Dockerfile: ${BOLD}$DOCKERFILE${NC}  Backend: ${BOLD}$BACKEND${NC}"
}

# ── security setup ────────────────────────────────────────────────────────────
setup_security() {
  echo ""
  echo -e "${BOLD}Security${NC}"
  echo "By default the web interface is open on the configured port."
  echo "Recommended: set a password."
  echo ""

  VNC_PASSWORD=""
  SECURE_CONNECTION=0

  read -r -p "Set VNC password? (strongly recommended) [Y/n]: " ans
  case "${ans:-Y}" in
    [Yy]*)
      while true; do
        if [ "$BACKEND" = "kasmvnc" ]; then
          read -r -s -p "Password (any length): " pw
        else
          read -r -s -p "VNC password (6-8 characters): " pw
        fi
        echo ""
        if [ ${#pw} -lt 6 ]; then
          print_err "Password too short (minimum 6 characters)"
          continue
        fi
        if [ "$BACKEND" = "classic" ] && [ ${#pw} -gt 8 ]; then
          print_warn "Classic noVNC: password truncated to 8 chars (RFC 6143 limit) — switch to KasmVNC for longer passwords"
          pw="${pw:0:8}"
        fi
        VNC_PASSWORD="$pw"
        print_ok "Password set"
        break
      done
      ;;
    *)
      print_warn "No password — bind to localhost only or use SSH tunnel"
      ;;
  esac

  if [ "$BACKEND" = "classic" ]; then
    echo ""
    read -r -p "Enable HTTPS/SSL (jlesage SECURE_CONNECTION, self-signed cert)? [y/N]: " ans
    case "${ans:-N}" in
      [Yy]*) SECURE_CONNECTION=1; print_ok "HTTPS enabled" ;;
      *)     SECURE_CONNECTION=0 ;;
    esac
  fi

  local tunnel_port="${HTTP_PORT:-6901}"
  [ "$BACKEND" = "classic" ] && tunnel_port="${HTTP_PORT:-5800}"
  echo ""
  echo -e "${CYAN}SSH tunnel tip:${NC} ssh -L ${tunnel_port}:localhost:${tunnel_port} user@server → http://localhost:${tunnel_port}"
}

# ── paths setup ───────────────────────────────────────────────────────────────
setup_paths() {
  echo ""
  echo -e "${BOLD}Data Paths${NC}"
  echo "Default: ./config"
  echo ""

  CONFIG_PATH="./config"
  LOXONE_PATH="./config/Loxone"

  read -r -p "Custom config path? (leave empty for default): " custom_path
  if [ -n "$custom_path" ]; then
    CONFIG_PATH="$custom_path"
    LOXONE_PATH="$custom_path/Loxone"
    print_ok "Config path: $CONFIG_PATH"
  fi

  mkdir -p "${CONFIG_PATH}" "${LOXONE_PATH}"
  print_ok "Directories ready"
}

# ── display / ports ───────────────────────────────────────────────────────────
setup_display() {
  echo ""
  echo -e "${BOLD}Display & Ports${NC}"

  XLANG=de
  VNC_RESOLUTION="1920x1080"
  DISPLAY_WIDTH=1920
  DISPLAY_HEIGHT=1080
  VNC_PORT=5900

  read -r -p "Keyboard layout [de/at/ch/us/en/fr] (default: de): " lang
  XLANG="${lang:-de}"

  if [ "$BACKEND" = "kasmvnc" ]; then
    HTTP_PORT=6901
    VNC_PORT=5901
    read -r -p "Web UI port (default: 6901): " port
    HTTP_PORT="${port:-6901}"
    read -r -p "Starting resolution (KasmVNC resizes dynamically, default: 1920x1080): " res
    VNC_RESOLUTION="${res:-1920x1080}"
    DISPLAY_WIDTH="${VNC_RESOLUTION%%x*}"
    DISPLAY_HEIGHT="${VNC_RESOLUTION##*x}"
  else
    HTTP_PORT=5800
    read -r -p "Web UI port (default: 5800): " port
    HTTP_PORT="${port:-5800}"
    read -r -p "Display resolution (default: 1920x1080): " res
    if [ -n "$res" ]; then
      DISPLAY_WIDTH="${res%%x*}"
      DISPLAY_HEIGHT="${res##*x}"
      VNC_RESOLUTION="${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}"
    fi
  fi
}

# ── write .env ────────────────────────────────────────────────────────────────
write_env() {
  cat > .env << EOF
# Generated by setup.sh — edit manually or re-run setup.sh

# Compose files (Docker Compose reads this automatically)
COMPOSE_FILE=${COMPOSE_FILE}

# Platform (auto-detected)
PLATFORM=${PLATFORM}
DOCKERFILE=${DOCKERFILE}

# Display backend: kasmvnc | classic
BACKEND=${BACKEND}

# Security
VNC_PASSWORD=${VNC_PASSWORD}
SECURE_CONNECTION=${SECURE_CONNECTION}

# Paths
CONFIG_PATH=${CONFIG_PATH}
LOXONE_PATH=${LOXONE_PATH}

# Display
VNC_RESOLUTION=${VNC_RESOLUTION}
DISPLAY_WIDTH=${DISPLAY_WIDTH}
DISPLAY_HEIGHT=${DISPLAY_HEIGHT}
XLANG=${XLANG}

# Ports
HTTP_PORT=${HTTP_PORT}
VNC_PORT=${VNC_PORT}

# User (match host user to avoid permission issues — classic mode only)
USER_ID=$(id -u)
GROUP_ID=$(id -g)

# Behaviour
KEEP_APP_RUNNING=1
EOF
  print_ok ".env written"
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  print_header

  if ! command -v docker &>/dev/null; then
    print_err "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
  fi

  detect_platform
  setup_backend
  resolve_dockerfile
  setup_paths
  setup_display
  setup_security
  write_env

  echo ""
  echo -e "${BOLD}${GREEN}Setup complete!${NC}"
  echo ""
  echo "Next steps:"
  echo -e "  ${BOLD}docker compose up -d --build${NC}   # first run (builds image, ~5-10 min)"
  echo -e "  ${BOLD}docker compose up -d${NC}           # subsequent starts (fast)"
  echo ""
  echo -e "  Then open: ${BOLD}http://localhost:${HTTP_PORT}${NC}"
  echo ""
  if [ -z "$VNC_PASSWORD" ]; then
    echo -e "  ${YELLOW}⚠  No password set — bind to localhost only or use SSH tunnel${NC}"
  fi
  echo ""
  echo "First launch installs Wine + Loxone Config (~10-15 min in browser)."
  echo "Subsequent launches are fast (cached in ${CONFIG_PATH}/wine)."
  echo ""
}

main "$@"
