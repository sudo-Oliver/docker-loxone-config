#!/bin/sh

echo "startapp: DISPLAY=$DISPLAY WINEARCH=$WINEARCH WINEPREFIX=$WINEPREFIX"

find_loxone_exe() {
  for dir in "Program Files" "Program Files (x86)"; do
    candidate="/config/wine/drive_c/${dir}/Loxone/LoxoneConfig/LoxoneConfig.exe"
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
}

LOXONE_EXE=$(find_loxone_exe)

if [ -z "$LOXONE_EXE" ]; then
  echo "startapp: Loxone not installed — running init-install.sh"
  echo "startapp: Wine installer window will appear in your browser (localhost:6901)"
  echo "startapp: Click through the Loxone Config setup wizard to install"
  /init-install.sh
  echo "startapp: init-install.sh done (exit $?)"
  LOXONE_EXE=$(find_loxone_exe)
fi

if [ -z "$LOXONE_EXE" ]; then
  echo "startapp: Loxone exe not found in Program Files or Program Files (x86)"
  echo "startapp: Check logs above for install errors"
  echo "startapp: Fix errors then run: docker compose restart"
  touch /tmp/install_failed
  exit 1
fi

ensure_vc_redist() {
  local dest_dir="$1" url="$2" label="$3" arch_suffix="$4"
  local tmp; tmp=$(mktemp -d)
  echo "startapp: downloading $label..."
  wget -q -O "$tmp/vc.exe" "$url"
  local offset; offset=$(grep -aob "MSCF" "$tmp/vc.exe" | cut -d: -f1 | sed -n '2p')
  [ -z "$offset" ] && { echo "startapp: ERROR: no payload in $label"; rm -rf "$tmp"; return; }
  mkdir -p "$tmp/raw" "$tmp/dlls"
  dd if="$tmp/vc.exe" bs=1 skip="$offset" of="$tmp/payload.cab" 2>/dev/null
  cabextract -d "$tmp/raw/" "$tmp/payload.cab" 2>&1 || true
  # cabextract each inner CAB directly — DLLs have _amd64/_x86 arch suffix in name
  for f in "$tmp/raw/"*; do
    [ -f "$f" ] || continue
    local magic; magic=$(od -A n -t x1 -N 4 "$f" 2>/dev/null | tr -d ' \n')
    [ "$magic" = "4d534346" ] && cabextract -d "$tmp/dlls/" "$f" 2>/dev/null || true
  done
  mkdir -p "$dest_dir"
  for dll in mfc140u msvcp140 vcruntime140 vcruntime140_1 ucrtbase concrt140; do
    local found; found=$(find "$tmp/dlls" -iname "${dll}.dll_${arch_suffix}" | head -1)
    if [ -n "$found" ]; then
      cp "$found" "$dest_dir/${dll}.dll"
      echo "startapp: installed ${dll}.dll → $dest_dir"
    fi
  done
  rm -rf "$tmp"
}

SYSTEM32="$WINEPREFIX/drive_c/windows/system32"
SYSWOW64="$WINEPREFIX/drive_c/windows/syswow64"

# Qt6WebEngineCore requires Windows 10. Old prefixes default to Win7.
CURRENT_BUILD=$(wine reg query "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
    /v CurrentBuildNumber 2>/dev/null | awk '/CurrentBuildNumber/{print $NF}')
if [ -z "$CURRENT_BUILD" ] || [ "${CURRENT_BUILD:-0}" -lt 10000 ] 2>/dev/null; then
  echo "startapp: upgrading prefix to Windows 10 (was build ${CURRENT_BUILD:-unknown})..."
  wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
      /v CurrentVersion /t REG_SZ /d "10.0" /f 2>/dev/null
  wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
      /v CurrentBuildNumber /t REG_SZ /d "19045" /f 2>/dev/null
  wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
      /v ProductName /t REG_SZ /d "Windows 10 Pro" /f 2>/dev/null
fi
if [ ! -f "$SYSTEM32/mfc140u.dll" ]; then
  echo "startapp: mfc140u.dll missing from system32 — extracting x64 VC redist..."
  ensure_vc_redist "$SYSTEM32" "https://aka.ms/vs/17/release/vc_redist.x64.exe" "vc_redist.x64" "amd64"
fi
if [ ! -f "$SYSWOW64/mfc140u.dll" ]; then
  echo "startapp: mfc140u.dll missing from syswow64 — extracting x86 VC redist..."
  ensure_vc_redist "$SYSWOW64" "https://aka.ms/vs/17/release/vc_redist.x86.exe" "vc_redist.x86" "x86"
fi

echo "startapp: launching $LOXONE_EXE"
export WINEDEBUG=-all
export LIBGL_ALWAYS_SOFTWARE=1
export MESA_GL_VERSION_OVERRIDE=4.5
# Qt6WebEngineCore (embedded Chromium) reads this env var for Chromium flags.
# --no-sandbox: required under FEX-Emu and Wine (Chromium sandbox uses syscalls
# that conflict with FEX's exec interception layer).
export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:---no-sandbox}"
setxkbmap "$XLANG" 2>/dev/null || true
exec wine "$LOXONE_EXE"
