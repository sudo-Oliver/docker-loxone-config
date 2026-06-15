#!/usr/bin/env bash
set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

print_header() {
  echo -e "\n${BOLD}${CYAN}=== Loxone Config Docker Setup ===${NC}\n"
}

print_ok()   { echo -e "${GREEN}✓${NC} $1"; }
print_warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
print_info() { echo -e "${CYAN}→${NC} $1"; }
print_err()  { echo -e "${RED}✗${NC} $1"; }

# ── detect platform ───────────────────────────────────────────────────────────
rosetta_available() {
  # /usr/libexec/rosetta exists when Rosetta 2 is installed on macOS ARM
  [ -f /usr/libexec/rosetta ]
}

ensure_qemu_binfmt() {
  echo ""
  echo -e "${BOLD}QEMU binfmt setup${NC}"
  echo "The ARM64+QEMU mode requires i386 binfmt to be registered on the host kernel."

  # Check if i386 binfmt already registered
  if [ -f /proc/sys/fs/binfmt_misc/qemu-i386 ] || \
     (docker run --rm --platform linux/386 alpine echo ok &>/dev/null 2>&1); then
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
      print_info "Re-run after reboot or add to your startup:"
      echo "  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
      ;;
    *)
      print_warn "Skipped. Run manually before 'docker compose up -d --build':"
      echo "  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
      ;;
  esac
}

detect_platform() {
  local arch os
  arch=$(uname -m)
  os=$(uname -s)

  PLATFORM="linux/amd64"
  DOCKERFILE="Dockerfile.amd64"
  QEMU_BINFMT_NEEDED=false

  case "$arch" in
    arm64|aarch64)
      if [ "$os" = "Darwin" ]; then
        print_ok "Apple Silicon Mac (ARM64)"
        if rosetta_available; then
          # Primary path: Rosetta 2 translates linux/amd64 → ARM64 at near-native speed
          PLATFORM="linux/amd64"
          DOCKERFILE="Dockerfile.amd64"
          print_ok "Rosetta 2 found → linux/amd64 via Rosetta (primary, fastest)"
          print_info "Fallback available: Dockerfile.arm64-qemu (QEMU-user, no Rosetta dependency)"
        else
          # Fallback path: native ARM64 container + QEMU-user-mode inside for i386 Wine
          PLATFORM="linux/arm64"
          DOCKERFILE="Dockerfile.arm64-qemu"
          QEMU_BINFMT_NEEDED=true
          print_warn "Rosetta 2 not found → linux/arm64 + QEMU-user mode (fallback)"
          print_info "Performance: ~3-5x slower than Rosetta, but fine for Loxone Config GUI"
        fi
      else
        # Linux ARM64: use QEMU-user fallback (no Rosetta on Linux)
        PLATFORM="linux/arm64"
        DOCKERFILE="Dockerfile.arm64-qemu"
        QEMU_BINFMT_NEEDED=true
        print_ok "Linux ARM64 (Raspberry Pi / ARM server)"
        print_info "Using native arm64 + QEMU-user mode for i386 Wine"
      fi
      ;;
    x86_64)
      print_ok "x86_64 ($os) — native performance"
      ;;
    i386|i686)
      PLATFORM="linux/386"
      DOCKERFILE="Dockerfile"
      print_ok "32-bit x86 — using original Alpine/386 image"
      ;;
    *)
      print_warn "Unknown arch '$arch' — defaulting to linux/amd64"
      ;;
  esac

  if [ "$QEMU_BINFMT_NEEDED" = "true" ]; then
    ensure_qemu_binfmt
  fi

  print_info "Platform: ${BOLD}$PLATFORM${NC}  Dockerfile: ${BOLD}$DOCKERFILE${NC}"
}

# ── security setup ────────────────────────────────────────────────────────────
setup_security() {
  echo ""
  echo -e "${BOLD}Security${NC}"
  echo "By default the web interface is unencrypted and open on the configured port."
  echo "Recommended: set a VNC password (protects the noVNC web UI and VNC protocol)."
  echo ""

  VNC_PASSWORD=""
  SECURE_CONNECTION=0

  read -r -p "Set VNC password? (strongly recommended) [Y/n]: " ans
  case "${ans:-Y}" in
    [Yy]*)
      while true; do
        read -r -s -p "VNC password (6-8 characters): " pw
        echo ""
        if [ ${#pw} -lt 6 ]; then
          print_err "Password too short (minimum 6 characters)"
          continue
        fi
        if [ ${#pw} -gt 8 ]; then
          print_warn "Password truncated to 8 characters (RFC 6143 limit)"
          pw="${pw:0:8}"
        fi
        VNC_PASSWORD="$pw"
        print_ok "VNC password set"
        break
      done
      ;;
    *)
      print_warn "No VNC password — interface will be open to anyone who can reach port ${HTTP_PORT:-5800}"
      ;;
  esac

  echo ""
  read -r -p "Enable HTTPS/SSL (generates self-signed cert)? [y/N]: " ans
  case "${ans:-N}" in
    [Yy]*) SECURE_CONNECTION=1; print_ok "HTTPS enabled" ;;
    *)     SECURE_CONNECTION=0 ;;
  esac

  echo ""
  echo -e "${CYAN}SSH tunnel tip:${NC} For remote access without opening ports:"
  echo "  ssh -L 5800:localhost:5800 user@your-server"
  echo "  Then open: http://localhost:5800"
}

# ── paths setup ───────────────────────────────────────────────────────────────
setup_paths() {
  echo ""
  echo -e "${BOLD}Data Paths${NC}"
  echo "Default: ./config (relative to this directory)"
  echo ""

  CONFIG_PATH="./config"
  LOXONE_PATH="./config/Loxone"

  read -r -p "Custom config path? (leave empty for default ./config): " custom_path
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

  DISPLAY_WIDTH=1920
  DISPLAY_HEIGHT=1080
  HTTP_PORT=5800
  VNC_PORT=5900
  XLANG=de

  read -r -p "Keyboard layout [de/at/ch/us/en/fr] (default: de): " lang
  XLANG="${lang:-de}"

  read -r -p "Web UI port (default: 5800): " port
  HTTP_PORT="${port:-5800}"

  read -r -p "Display resolution (default: 1920x1080): " res
  if [ -n "$res" ]; then
    DISPLAY_WIDTH="${res%%x*}"
    DISPLAY_HEIGHT="${res##*x}"
  fi
}

# ── write .env ────────────────────────────────────────────────────────────────
write_env() {
  cat > .env << EOF
# Generated by setup.sh — edit manually or re-run setup.sh

# Platform (auto-detected)
PLATFORM=${PLATFORM}
DOCKERFILE=${DOCKERFILE}

# Security
VNC_PASSWORD=${VNC_PASSWORD}
SECURE_CONNECTION=${SECURE_CONNECTION}

# Paths
CONFIG_PATH=${CONFIG_PATH}
LOXONE_PATH=${LOXONE_PATH}

# Display
DISPLAY_WIDTH=${DISPLAY_WIDTH}
DISPLAY_HEIGHT=${DISPLAY_HEIGHT}
XLANG=${XLANG}

# Ports
HTTP_PORT=${HTTP_PORT}
VNC_PORT=${VNC_PORT}

# User (match host user to avoid permission issues)
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

  # Verify docker is available
  if ! command -v docker &>/dev/null; then
    print_err "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
  fi

  detect_platform
  setup_security
  setup_paths
  setup_display
  write_env

  echo ""
  echo -e "${BOLD}${GREEN}Setup complete!${NC}"
  echo ""
  echo "Next steps:"
  echo -e "  ${BOLD}docker compose up -d --build${NC}   # first run (builds image, ~5 min)"
  echo -e "  ${BOLD}docker compose up -d${NC}           # subsequent starts (fast)"
  echo ""
  echo -e "  Then open: ${BOLD}http://localhost:${HTTP_PORT}${NC}"
  echo ""
  if [ "$SECURE_CONNECTION" = "1" ]; then
    echo -e "  HTTPS: ${BOLD}https://localhost:${HTTP_PORT}${NC}"
  fi
  if [ -z "$VNC_PASSWORD" ]; then
    echo -e "  ${YELLOW}⚠  No VNC password set — bind to localhost only or use SSH tunnel${NC}"
  fi
  echo ""
  echo "First launch installs Wine + Loxone Config inside the container (~10-15 min)."
  echo "Subsequent launches are fast (installation cached in $CONFIG_PATH/wine)."
  echo ""
}

main "$@"
