#!/usr/bin/env bash
set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
info() { echo -e "  ${CYAN}→${NC}  $1"; }
err()  { echo -e "  ${RED}✗${NC}  $1"; }
sep()  { echo -e "\n${DIM}────────────────────────────────────────────${NC}"; }
header() { echo -e "\n${BOLD}$1${NC}"; }

# ── welcome ───────────────────────────────────────────────────────────────────
print_welcome() {
  clear
  echo -e "${BOLD}${CYAN}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║        Loxone Config — Docker Setup          ║"
  echo "  ╚══════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  This setup takes about 2 minutes."
  echo "  Afterwards, Loxone Config runs in your browser —"
  echo "  on this machine or any device on your network."
  echo ""
  echo -e "  ${DIM}(Run this script again anytime to change settings.)${NC}"
  sep
}

# ── prerequisites ────────────────────────────────────────────────────────────
check_prerequisites() {
  header "Before We Start"
  echo ""

  if [ "$(uname -m)" = "arm64" ] && [ "$(uname -s)" = "Darwin" ]; then
    echo -e "  ${BOLD}${CYAN}Apple Silicon Mac (M-chip) detected${NC}"
    echo ""
    echo "  This setup uses FEX-Emu for x86-64 translation — no Rosetta 2 needed."
    echo "  FEX-Emu is a JIT translator that correctly handles all CPU state including"
    echo "  AVX registers, which Rosetta 2 does not fully support for this application."
    echo ""
    echo -e "  ${DIM}(Rosetta 2 causes a crash in LoxoneConfig's embedded Chromium engine.${NC}"
    echo -e "  ${DIM} The Rosetta setting in Docker Desktop → General has no effect here.)${NC}"
    echo ""
  fi

  echo -e "  ${BOLD}Required: Loxone Config installer (.exe)${NC}"
  echo ""
  echo "  Everyone must download this manually before setup can finish."
  echo ""
  echo -e "  Download from: ${BOLD}https://www.loxone.com/enen/support/downloads/${NC}"
  echo "  Look for \"Loxone Config\" → download the Windows .exe installer."
  echo "  Save it to your Downloads folder."
  echo ""
  echo -e "  ${DIM}Setup will find and copy it automatically — no manual cp needed.${NC}"
  sep
}

# ── check docker ──────────────────────────────────────────────────────────────
check_docker() {
  header "Checking Docker"
  echo ""
  if ! command -v docker &>/dev/null; then
    err "Docker is not installed."
    echo ""
    echo "  Install Docker Desktop first:"
    echo "    Mac:   https://www.docker.com/products/docker-desktop/"
    echo "    Linux: https://docs.docker.com/engine/install/"
    echo ""
    exit 1
  fi
  if ! docker info &>/dev/null 2>&1; then
    err "Docker is installed but not running."
    echo ""
    echo "  Please start Docker Desktop, wait for it to finish loading,"
    echo "  then run this setup again."
    echo ""
    exit 1
  fi
  ok "Docker is running"
  sep
}

# ── detect platform (silent, show result) ─────────────────────────────────────
detect_platform() {
  header "Your Computer"
  echo ""

  local arch os
  arch=$(uname -m)
  os=$(uname -s)

  PLATFORM="linux/amd64"
  PLATFORM_CLASS="amd64"

  case "$arch" in
    arm64|aarch64)
      PLATFORM="linux/arm64"
      PLATFORM_CLASS="arm64"
      if [ "$os" = "Darwin" ]; then
        ok "Apple Silicon Mac (M-chip) — using FEX-Emu (native ARM64 + x86-64 JIT)"
        info "FEX-Emu handles AVX xsave correctly; Rosetta 2 does not (crashes LoxoneConfig)."
      else
        ok "Linux on ARM processor (Raspberry Pi / ARM server) — using FEX-Emu"
      fi
      ;;
    x86_64)
      PLATFORM="linux/amd64"
      PLATFORM_CLASS="amd64"
      ok "Intel / AMD Mac or Linux PC"
      ;;
    i386|i686)
      PLATFORM="linux/386"
      PLATFORM_CLASS="386"
      ok "32-bit x86 system"
      ;;
    *)
      PLATFORM="linux/amd64"
      PLATFORM_CLASS="amd64"
      warn "Unknown processor type — defaulting to standard mode."
      ;;
  esac

  sep
}

# ── display mode ──────────────────────────────────────────────────────────────
choose_display_mode() {
  header "Display Quality"
  echo ""
  echo "  Loxone Config's window is streamed to your browser — similar to"
  echo "  remote desktop. There are two options:"
  echo ""
  echo -e "  ${BOLD}[1] High-Quality${NC} ${GREEN}← recommended${NC}"
  echo "      Sharp display that adapts to your browser window size."
  echo "      Full copy/paste between your computer and Loxone Config."
  echo "      Files can be transferred directly in the browser."
  echo ""
  echo -e "  ${BOLD}[2] Standard${NC}"
  echo "      Older technology. Use only if High-Quality causes problems."
  echo "      Copy/paste may not work reliably. Fixed window size."
  echo ""

  if [ "$PLATFORM_CLASS" = "386" ]; then
    BACKEND="classic"
    info "32-bit system: Standard mode only (High-Quality not available here)."
    sep
    return
  fi

  read -r -p "  Choose [1/2] (just press Enter for High-Quality): " ans
  echo ""
  case "${ans:-1}" in
    2)
      BACKEND="classic"
      ok "Standard mode selected."
      warn "If you change your mind, re-run this setup."
      ;;
    *)
      BACKEND="kasmvnc"
      ok "High-Quality mode selected."
      ;;
  esac
  sep
}

# ── resolve dockerfile + compose ──────────────────────────────────────────────
resolve_dockerfile() {
  case "${BACKEND}:${PLATFORM_CLASS}" in
    kasmvnc:amd64) DOCKERFILE="Dockerfile.kasmvnc";     COMPOSE_FILE="docker-compose.yml:docker-compose.kasmvnc.yml" ;;
    kasmvnc:arm64) DOCKERFILE="Dockerfile.arm64-fex";   COMPOSE_FILE="docker-compose.yml:docker-compose.kasmvnc.yml" ;;
    classic:amd64) DOCKERFILE="Dockerfile.amd64";       COMPOSE_FILE="docker-compose.yml:docker-compose.classic.yml" ;;
    classic:arm64) DOCKERFILE="Dockerfile.arm64-fex";   COMPOSE_FILE="docker-compose.yml:docker-compose.classic.yml" ;;
    *:386)         DOCKERFILE="Dockerfile";               COMPOSE_FILE="docker-compose.yml:docker-compose.classic.yml" ;;
    *)             DOCKERFILE="Dockerfile.kasmvnc";       COMPOSE_FILE="docker-compose.yml:docker-compose.kasmvnc.yml" ;;
  esac
  DEFAULT_PORT=5800
  [ "$BACKEND" = "kasmvnc" ] && DEFAULT_PORT=6901
}

# ── password ──────────────────────────────────────────────────────────────────
setup_security() {
  header "Access Protection"
  echo ""
  echo "  Anyone on your local network who knows this device's IP address"
  echo "  could open Loxone Config in their browser without a password."
  echo ""
  echo "  Setting a password is strongly recommended — especially if you're"
  echo "  on a shared network (apartment building, office, etc.)."
  echo ""

  VNC_PASSWORD=""
  SECURE_CONNECTION=0

  read -r -p "  Set a password? [Y/n]: " ans
  echo ""
  case "${ans:-Y}" in
    [Nn]*)
      warn "No password set."
      info "Make sure only trusted devices can reach port ${DEFAULT_PORT}."
      ;;
    *)
      while true; do
        if [ "$BACKEND" = "kasmvnc" ]; then
          read -r -s -p "  Password (any length, min. 6 characters): " pw
        else
          read -r -s -p "  Password (6-8 characters — Standard mode limit): " pw
        fi
        echo ""

        if [ ${#pw} -lt 6 ]; then
          err "Too short — minimum 6 characters. Try again."
          continue
        fi

        if [ "$BACKEND" = "classic" ] && [ ${#pw} -gt 8 ]; then
          warn "Standard mode limits passwords to 8 characters — truncating."
          pw="${pw:0:8}"
        fi

        read -r -s -p "  Confirm password: " pw2
        echo ""
        if [ "$pw" != "$pw2" ]; then
          err "Passwords don't match. Try again."
          echo ""
          continue
        fi

        VNC_PASSWORD="$pw"
        ok "Password saved."
        break
      done
      ;;
  esac
  sep
}

# ── config path ───────────────────────────────────────────────────────────────
setup_paths() {
  header "Where to Store Your Data"
  echo ""
  echo "  Loxone Config saves your projects and settings in a folder."
  echo "  This folder is preserved when the container is updated or restarted."
  echo ""

  local default_path
  default_path="$(pwd)/config"

  echo -e "  Default location: ${BOLD}${default_path}${NC}"
  echo ""
  echo "  Press Enter to use the default, or type a custom path."
  echo -e "  ${DIM}Example for a NAS: /mnt/nas/loxone-data${NC}"
  echo ""
  read -r -p "  Data folder [${default_path}]: " custom_path
  echo ""

  if [ -z "$custom_path" ]; then
    CONFIG_PATH="./config"
    LOXONE_PATH="./config/Loxone"
    ok "Using default: ${default_path}"
  else
    CONFIG_PATH="$custom_path"
    LOXONE_PATH="$custom_path/Loxone"
    ok "Using: ${custom_path}"
  fi

  mkdir -p "${CONFIG_PATH}" "${LOXONE_PATH}" 2>/dev/null || {
    warn "Could not create ${CONFIG_PATH} — make sure the path is valid and you have write permission."
  }
  sep
}

# ── port ──────────────────────────────────────────────────────────────────────
setup_port() {
  header "Browser Access Port"
  echo ""
  echo "  You'll open Loxone Config in your browser at:"
  echo -e "  ${BOLD}http://localhost:${DEFAULT_PORT}${NC}"
  echo ""
  echo "  This port needs to be free on your computer."
  echo "  If another application already uses port ${DEFAULT_PORT}, enter a different number."
  echo ""
  read -r -p "  Port [${DEFAULT_PORT}]: " custom_port
  echo ""

  HTTP_PORT="${custom_port:-$DEFAULT_PORT}"

  if [ "$BACKEND" = "kasmvnc" ]; then
    VNC_PORT=5901
  else
    VNC_PORT=5900
  fi

  ok "Access URL: http://localhost:${HTTP_PORT}"
  sep
}

# ── keyboard ──────────────────────────────────────────────────────────────────
setup_keyboard() {
  header "Keyboard Layout"
  echo ""
  echo "  What keyboard layout do you use?"
  echo "  (This affects how keys are recognized inside Loxone Config.)"
  echo ""
  echo "  de = German  |  at = Austrian  |  ch = Swiss"
  echo "  us = US English  |  en = English  |  fr = French"
  echo ""
  read -r -p "  Layout [de]: " lang
  XLANG="${lang:-de}"
  ok "Keyboard: ${XLANG}"
  sep
}

# ── write .env ────────────────────────────────────────────────────────────────
write_env() {
  VNC_RESOLUTION="1920x1080"
  DISPLAY_WIDTH=1920
  DISPLAY_HEIGHT=1080

  cat > .env << EOF
# Loxone Config Docker — configuration
# Generated by setup.sh. Edit manually or re-run: ./setup.sh

# ── Compose setup ─────────────────────────────────────────────────────────────
COMPOSE_FILE=${COMPOSE_FILE}

# ── Platform (auto-detected) ──────────────────────────────────────────────────
PLATFORM=${PLATFORM}
DOCKERFILE=${DOCKERFILE}
BACKEND=${BACKEND}

# ── Security ──────────────────────────────────────────────────────────────────
VNC_PASSWORD=${VNC_PASSWORD}
SECURE_CONNECTION=${SECURE_CONNECTION}

# ── Data paths ────────────────────────────────────────────────────────────────
CONFIG_PATH=${CONFIG_PATH}
LOXONE_PATH=${LOXONE_PATH}

# ── Display ───────────────────────────────────────────────────────────────────
VNC_RESOLUTION=${VNC_RESOLUTION}
DISPLAY_WIDTH=${DISPLAY_WIDTH}
DISPLAY_HEIGHT=${DISPLAY_HEIGHT}
XLANG=${XLANG}

# ── Ports ─────────────────────────────────────────────────────────────────────
HTTP_PORT=${HTTP_PORT}
VNC_PORT=${VNC_PORT}

# ── Process ───────────────────────────────────────────────────────────────────
USER_ID=$(id -u)
GROUP_ID=$(id -g)
KEEP_APP_RUNNING=1
EOF
}

# ── generate loxone.sh helper ─────────────────────────────────────────────────
write_helper() {
  cat > loxone.sh << HELPER
#!/usr/bin/env bash
# Loxone Config — quick control script
# Generated by setup.sh

ACCESS_URL="http://localhost:${HTTP_PORT}"

case "\${1:-help}" in
  start)
    echo "Starting Loxone Config..."
    docker compose up -d
    echo ""
    echo "  Open in browser: \${ACCESS_URL}"
    if [ "${BACKEND}" = "kasmvnc" ]; then
      echo "  Login — username: kasm_user  password: ${VNC_PASSWORD:-changeme}"
    fi
    echo "  (First launch takes 10-15 min to install Wine + Loxone Config)"
    ;;
  stop)
    echo "Stopping Loxone Config..."
    docker compose down
    echo "Stopped."
    ;;
  restart)
    echo "Restarting Loxone Config..."
    docker compose restart
    sleep 2
    echo ""
    echo "  Open in browser: \${ACCESS_URL}"
    ;;
  update)
    echo "Rebuilding Loxone Config image with latest Wine (this takes a few minutes)..."
    docker compose up -d --build
    echo ""
    echo "  Open in browser: \${ACCESS_URL}"
    ;;
  status)
    docker compose ps
    echo ""
    IS_RUNNING=\$(docker compose ps --services --filter status=running 2>/dev/null | grep -c loxone-config || true)
    if [ "\$IS_RUNNING" -gt 0 ]; then
      echo "  ✓ Loxone Config is running → \${ACCESS_URL}"
    else
      echo "  ✗ Loxone Config is NOT running"
      echo "    Start it with: ./loxone.sh start"
    fi
    ;;
  logs)
    echo "Showing live logs (Ctrl+C to stop)..."
    docker compose logs -f
    ;;
  open)
    echo "Opening \${ACCESS_URL} ..."
    if command -v open &>/dev/null; then
      open "\${ACCESS_URL}"
    elif command -v xdg-open &>/dev/null; then
      xdg-open "\${ACCESS_URL}"
    else
      echo "Open manually: \${ACCESS_URL}"
    fi
    ;;
  report)
    echo ""
    echo "  Collecting system info for bug report..."
    echo ""
    ARCH=\$(uname -m)
    OS=\$(uname -s)
    OS_VER=\$(sw_vers -productVersion 2>/dev/null || uname -r)
    DOCKER_VER=\$(docker --version 2>/dev/null || echo "not found")
    CONTAINER_STATUS=\$(docker compose ps --format "table {{.Service}}\t{{.Status}}" 2>/dev/null || echo "unavailable")
    LAST_LOGS=\$(docker compose logs --tail=30 2>/dev/null || echo "unavailable")

    REPORT=\$(cat <<INFO
**System:**
- OS: \${OS} \${OS_VER} (\${ARCH})
- Docker: \${DOCKER_VER}
- Backend: ${BACKEND}
- Platform: ${PLATFORM}
- Dockerfile: ${DOCKERFILE}

**Container status:**
\`\`\`
\${CONTAINER_STATUS}
\`\`\`

**Last 30 log lines:**
\`\`\`
\${LAST_LOGS}
\`\`\`

**What I expected:**


**What happened instead:**

INFO
)

    echo "─────────────────────────────────────────────────────"
    echo "\${REPORT}"
    echo "─────────────────────────────────────────────────────"
    echo ""
    echo "  Copy the text above into a new GitHub issue:"
    echo "  https://github.com/sudo-Oliver/docker-loxone-config/issues/new"
    echo ""
    ISSUE_URL="https://github.com/sudo-Oliver/docker-loxone-config/issues/new?labels=bug&template=bug_report.md"
    if command -v open &>/dev/null; then
      read -r -p "  Open GitHub Issues in browser? [Y/n]: " ans
      case "\${ans:-Y}" in
        [Nn]*) ;;
        *) open "\${ISSUE_URL}" ;;
      esac
    else
      echo "  Open: \${ISSUE_URL}"
    fi
    echo ""
    ;;
  help|--help|-h|*)
    echo ""
    echo "  Loxone Config — control commands"
    echo "  ─────────────────────────────────"
    echo "  ./loxone.sh start    → Start (or resume after stop)"
    echo "  ./loxone.sh stop     → Stop the container"
    echo "  ./loxone.sh restart  → Restart (fixes most issues)"
    echo "  ./loxone.sh status   → Check if running"
    echo "  ./loxone.sh logs     → Show live logs"
    echo "  ./loxone.sh update   → Rebuild image (gets latest Wine + security patches)"
    echo "  ./loxone.sh open     → Open in browser"
    echo "  ./loxone.sh report   → Collect system info + open GitHub Issues"
    echo ""
    echo "  Browser access: \${ACCESS_URL}"
    echo ""
    echo "  Not working? Try in order:"
    echo "    1. ./loxone.sh restart"
    echo "    2. ./loxone.sh logs    (look for error messages)"
    echo "    3. ./loxone.sh stop && ./loxone.sh start"
    echo "    4. ./loxone.sh report  (file a bug with logs pre-filled)"
    echo ""
    ;;
esac
HELPER
  chmod +x loxone.sh
}

# ── summary + build offer ─────────────────────────────────────────────────────
show_summary() {
  clear
  echo -e "${BOLD}${GREEN}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║           Setup Complete!                    ║"
  echo "  ╚══════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BOLD}Your Loxone Config:${NC}"
  echo ""

  local mode_label="High-Quality (KasmVNC)"
  [ "$BACKEND" = "classic" ] && mode_label="Standard (noVNC)"
  ok "Display mode:  ${mode_label}"
  ok "Browser URL:   ${BOLD}http://localhost:${HTTP_PORT}${NC}"
  ok "Data folder:   ${CONFIG_PATH}"
  ok "Keyboard:      ${XLANG}"

  if [ -n "$VNC_PASSWORD" ]; then
    ok "Browser login: username ${BOLD}kasm_user${NC}  password ${BOLD}${VNC_PASSWORD}${NC}"
  else
    warn "No password set — anyone on your network can access"
    if [ "$BACKEND" = "kasmvnc" ]; then
      ok "Browser login: username ${BOLD}kasm_user${NC}  password ${BOLD}changeme${NC}"
    fi
  fi

  echo ""
  echo -e "  ${BOLD}Quick reference (save this):${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
  echo -e "  Start:    ${BOLD}./loxone.sh start${NC}"
  echo -e "  Stop:     ${BOLD}./loxone.sh stop${NC}"
  echo -e "  Restart:  ${BOLD}./loxone.sh restart${NC}    ${DIM}← if something seems stuck${NC}"
  echo -e "  Status:   ${BOLD}./loxone.sh status${NC}"
  echo -e "  Open:     ${BOLD}./loxone.sh open${NC}       ${DIM}← opens browser directly${NC}"
  echo ""
  echo -e "  ${BOLD}What happens on first start:${NC}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
  echo -e "  1. Docker builds the image (${BOLD}5-10 min${NC} — only once)"
  echo -e "  2. Open ${BOLD}http://localhost:${HTTP_PORT}${NC} in your browser"
  if [ "$BACKEND" = "kasmvnc" ]; then
    if [ -n "$VNC_PASSWORD" ]; then
      echo -e "  3. Login: username ${BOLD}kasm_user${NC}  password ${BOLD}${VNC_PASSWORD}${NC}"
    else
      echo -e "  3. Login: username ${BOLD}kasm_user${NC}  password ${BOLD}changeme${NC}"
    fi
  fi
  echo -e "  4. Loxone Config installer wizard opens — click through it (${BOLD}~10 min${NC})"
  echo -e "  5. Done — Loxone Config opens automatically on every future start"
  echo ""
  echo -e "  ${DIM}loxone.sh was saved in this folder for convenience.${NC}"
  sep

  header "Start Now?"
  echo ""
  echo "  First start builds the Docker image and installs Wine + Loxone Config."
  echo -e "  ${BOLD}This takes 10-15 minutes${NC} — only once. Subsequent starts take seconds."
  echo ""
  read -r -p "  Build and start now? [Y/n]: " ans
  echo ""
  case "${ans:-Y}" in
    [Nn]*)
      echo ""
      info "When you're ready:"
      echo -e "    ${BOLD}./loxone.sh start${NC}"
      echo ""
      echo -e "  Then open: ${BOLD}http://localhost:${HTTP_PORT}${NC}"
      if [ "$BACKEND" = "kasmvnc" ]; then
        if [ -n "$VNC_PASSWORD" ]; then
          echo -e "  Login:     username ${BOLD}kasm_user${NC}  password ${BOLD}${VNC_PASSWORD}${NC}"
        else
          echo -e "  Login:     username ${BOLD}kasm_user${NC}  password ${BOLD}changeme${NC}"
        fi
      fi
      echo ""
      ;;
    *)
      echo "  Building image... (this will take a few minutes)"
      echo -e "  ${DIM}You can follow the progress below.${NC}"
      echo ""
      docker compose up -d --build
      echo ""
      printf "  Waiting for Loxone Config web UI"
      READY=false
      for i in $(seq 1 60); do
        if nc -z localhost "${HTTP_PORT}" 2>/dev/null; then
          READY=true
          break
        fi
        printf "."
        sleep 1
      done
      echo ""
      echo ""
      if [ "$READY" = "false" ]; then
        err "Web UI did not come up within 60 seconds."
        echo ""
        echo "  Check what went wrong:"
        echo -e "    ${BOLD}./loxone.sh logs${NC}"
        echo ""
        echo "  Then try restarting:"
        echo -e "    ${BOLD}./loxone.sh restart${NC}"
        echo ""
      else
        ok "Loxone Config is ready!"
        echo ""
        echo -e "  ${BOLD}Open in your browser: http://localhost:${HTTP_PORT}${NC}"
        echo ""
        if [ "$BACKEND" = "kasmvnc" ]; then
          echo -e "  ${BOLD}Browser login:${NC}"
          echo -e "    Username: ${BOLD}kasm_user${NC}"
          if [ -n "$VNC_PASSWORD" ]; then
            echo -e "    Password: ${BOLD}${VNC_PASSWORD}${NC}"
          else
            echo -e "    Password: ${BOLD}changeme${NC}  ${DIM}← set one later with ./setup.sh${NC}"
          fi
          echo ""
        fi
        echo -e "  ${DIM}Loxone Config installer wizard will open in your browser."
        echo -e "  Click through it to install (~10 min). After that, Loxone Config"
        echo -e "  opens automatically on every start — no wizard again.${NC}"
        echo ""
        if command -v open &>/dev/null; then
          read -r -p "  Open browser now? [Y/n]: " open_ans
          case "${open_ans:-Y}" in
            [Nn]*) ;;
            *) open "http://localhost:${HTTP_PORT}" ;;
          esac
        fi
      fi
      ;;
  esac
}

# ── installer copy step ──────────────────────────────────────────────────────
_find_installer() {
  local f
  for f in \
    "$HOME/Downloads/LoxoneConfigSetup.exe" \
    "$HOME/Downloads/"LoxoneConfigSetup*.exe \
    "$HOME/Desktop/LoxoneConfigSetup.exe" \
    "$HOME/Desktop/"LoxoneConfigSetup*.exe; do
    [ -f "$f" ] && echo "$f" && return
  done
}

setup_installer() {
  header "Loxone Config Installer"
  echo ""

  if [ -f "${CONFIG_PATH}/LoxoneConfigSetup.exe" ]; then
    ok "Installer ready: ${CONFIG_PATH}/LoxoneConfigSetup.exe"
    sep
    return
  fi

  local found_at
  found_at=$(_find_installer)

  if [ -n "$found_at" ]; then
    info "Found: $found_at"
    cp "$found_at" "${CONFIG_PATH}/LoxoneConfigSetup.exe"
    ok "Copied to ${CONFIG_PATH}/LoxoneConfigSetup.exe"
    sep
    return
  fi

  warn "Installer not found in Downloads or Desktop."
  echo ""
  echo "  Download from:"
  echo -e "  ${BOLD}https://www.loxone.com/enen/support/downloads/${NC}"
  echo "  (look for \"Loxone Config\" → Windows .exe)"
  echo ""
  echo "  Save to your Downloads folder, then press Enter."
  echo ""

  while true; do
    read -r -p "  Press Enter once downloaded (or type 'skip' to do later): " ans
    [ "$ans" = "skip" ] && break

    found_at=$(_find_installer)
    if [ -n "$found_at" ]; then
      info "Found: $found_at"
      cp "$found_at" "${CONFIG_PATH}/LoxoneConfigSetup.exe"
      ok "Copied to ${CONFIG_PATH}/LoxoneConfigSetup.exe"
      break
    fi

    warn "Still not found — check that the file is in ~/Downloads"
    echo ""
  done

  if [ ! -f "${CONFIG_PATH}/LoxoneConfigSetup.exe" ]; then
    warn "Installer missing — before first launch run:"
    echo -e "    ${BOLD}cp ~/Downloads/LoxoneConfigSetup*.exe ${CONFIG_PATH}/LoxoneConfigSetup.exe${NC}"
    echo -e "  Then: ${BOLD}./loxone.sh restart${NC}"
  fi
  sep
}

# ── shell alias ───────────────────────────────────────────────────────────────
setup_alias() {
  local loxone_abs
  loxone_abs="$(cd "$(dirname "$0")" && pwd)/loxone.sh"

  # detect shell config file
  local shell_rc=""
  case "${SHELL:-}" in
    */zsh)  shell_rc="$HOME/.zshrc" ;;
    */bash) shell_rc="$HOME/.bashrc" ;;
    *)      shell_rc="$HOME/.profile" ;;
  esac
  # macOS bash uses .bash_profile
  [ "$(uname -s)" = "Darwin" ] && [ "${SHELL:-}" != */zsh ] && shell_rc="$HOME/.bash_profile"

  # skip if alias already set
  if grep -q "alias loxone=" "$shell_rc" 2>/dev/null; then
    ok "Shell alias already set: type ${BOLD}loxone start${NC} anywhere"
    sep
    return
  fi

  header "Shell Shortcut (Optional)"
  echo ""
  echo "  Add a global 'loxone' command so you can type:"
  echo ""
  echo -e "    ${BOLD}loxone start${NC}    ${DIM}instead of  ./loxone.sh start${NC}"
  echo -e "    ${BOLD}loxone stop${NC}"
  echo -e "    ${BOLD}loxone open${NC}"
  echo -e "    ${BOLD}loxone logs${NC}"
  echo -e "    ${BOLD}loxone report${NC}"
  echo ""
  echo -e "  This adds one line to ${BOLD}${shell_rc}${NC}."
  echo -e "  ${DIM}(If you move this folder later, re-run setup.sh to update it.)${NC}"
  echo ""

  read -r -p "  Add 'loxone' shortcut? [Y/n]: " ans
  echo ""
  case "${ans:-Y}" in
    [Nn]*)
      info "Skipped. You can always use: ./loxone.sh start"
      sep
      return
      ;;
  esac

  printf '\n# Loxone Config shortcut (added by setup.sh)\nalias loxone="%s"\n' "$loxone_abs" >> "$shell_rc"
  ok "Added alias to ${shell_rc}"
  echo ""
  echo -e "  Activate now by running:"
  echo -e "    ${BOLD}source ${shell_rc}${NC}"
  echo -e "  ${DIM}Or just open a new terminal tab — it loads automatically.${NC}"
  sep
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  print_welcome
  check_prerequisites
  check_docker
  detect_platform
  choose_display_mode
  resolve_dockerfile
  setup_security
  setup_paths
  setup_installer
  setup_port
  setup_keyboard
  write_env
  write_helper
  setup_alias
  show_summary
}

main "$@"
