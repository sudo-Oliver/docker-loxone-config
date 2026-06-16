#!/bin/sh

if [ ! -f "/config/LoxoneConfigSetup.exe" ]; then
  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────────┐"
  echo "  │  Loxone Config installer not found                              │"
  echo "  └─────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "  Download LoxoneConfig from:"
  echo "    https://www.loxone.com/enen/support/downloads/"
  echo ""
  echo "  Then place the installer in your config folder:"
  echo "    cp ~/Downloads/LoxoneConfigSetup*.exe ./config/LoxoneConfigSetup.exe"
  echo ""
  echo "  Then restart:"
  echo "    ./loxone.sh restart"
  echo ""
  exit 1
fi

export WINEDEBUG=err
export WINE=/usr/bin/wine

echo "init-install: wine=$(which wine) version=$(wine --version 2>&1)"
echo "init-install: WINEARCH=$WINEARCH WINEPREFIX=$WINEPREFIX"

# Clear wrong-arch prefix. drive_c/users/ can't be rm'd (bind-mount is busy),
# so delete only the registry hives and non-users drive_c subdirs explicitly.
if [ -f "$WINEPREFIX/system.reg" ]; then
    PREFIX_ARCH=$(grep "^#arch=" "$WINEPREFIX/system.reg" | cut -d= -f2)
    if [ -n "$PREFIX_ARCH" ] && [ "$PREFIX_ARCH" != "$WINEARCH" ]; then
        echo "init-install: stale $PREFIX_ARCH prefix — clearing registry + C: drive"
        rm -f "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg" \
              "$WINEPREFIX/userdef.reg" "$WINEPREFIX/.update-timestamp"
        find "$WINEPREFIX/drive_c" -mindepth 1 -maxdepth 1 ! -name "users" \
            -exec rm -rf {} \; 2>/dev/null || true
    fi
fi

# Initialize prefix before winetricks runs — prevents winetricks from
# creating the wrong arch prefix for certain verbs.
echo "init-install: initializing $WINEARCH Wine prefix..."
DISPLAY="" wine wineboot --init 2>&1

# Qt6WebEngineCore requires Windows 10 (Chromium checks OS version during DLL init).
echo "init-install: setting Windows 10 in prefix..."
wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
    /v CurrentVersion /t REG_SZ /d "10.0" /f 2>&1
wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
    /v CurrentBuildNumber /t REG_SZ /d "19045" /f 2>&1
wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
    /v ProductName /t REG_SZ /d "Windows 10 Pro" /f 2>&1

echo "init-install: running winetricks fontsmooth-rgb..."
/usr/bin/winetricks -q fontsmooth-rgb 2>&1
echo "init-install: running winetricks gdiplus..."
/usr/bin/winetricks -q gdiplus 2>&1

# Extract DLLs from a WiX Burn vc_redist bundle into $2.
# Strategy: find second MSCF (payload CAB), cabextract, pair each MSI with
# the immediately following CAB by magic bytes, run msiextract, copy DLLs.
extract_vc_redist() {
    local url="$1"
    local dest_dir="$2"
    local label="$3"
    local arch_suffix="$4"
    local tmp
    tmp=$(mktemp -d)

    echo "init-install: downloading $label..."
    wget -q -O "$tmp/vc_redist.exe" "$url"

    # WiX Burn: first MSCF = small bootstrapper CAB, second = payload container CAB
    local payload_offset
    payload_offset=$(grep -aob "MSCF" "$tmp/vc_redist.exe" | cut -d: -f1 | sed -n '2p')
    if [ -z "$payload_offset" ]; then
        echo "init-install: ERROR: no payload CAB found in $label"
        rm -rf "$tmp"
        return 1
    fi

    echo "init-install: $label payload CAB at offset $payload_offset"
    mkdir -p "$tmp/raw" "$tmp/dlls"
    dd if="$tmp/vc_redist.exe" bs=1 skip="$payload_offset" of="$tmp/payload.cab" 2>/dev/null
    cabextract -d "$tmp/raw/" "$tmp/payload.cab" 2>&1 || true

    # cabextract each inner CAB — DLLs are named with arch suffix (_amd64/_x86/_arm64)
    for f in "$tmp/raw/"*; do
        [ -f "$f" ] || continue
        local magic
        magic=$(od -A n -t x1 -N 4 "$f" 2>/dev/null | tr -d ' \n')
        [ "$magic" = "4d534346" ] && cabextract -d "$tmp/dlls/" "$f" 2>/dev/null || true
    done

    mkdir -p "$dest_dir"
    local dll found
    for dll in mfc140u msvcp140 vcruntime140 vcruntime140_1 ucrtbase concrt140; do
        found=$(find "$tmp/dlls" -iname "${dll}.dll_${arch_suffix}" | head -1)
        if [ -n "$found" ]; then
            cp "$found" "$dest_dir/${dll}.dll"
            echo "init-install: installed ${dll}.dll → $dest_dir"
        else
            echo "init-install: WARNING: ${dll}.dll not found in $label (suffix: _${arch_suffix})"
        fi
    done

    rm -rf "$tmp"
}

echo "init-install: extracting MSVC DLLs from vc_redist packages..."

SYSWOW64="$WINEPREFIX/drive_c/windows/syswow64"
SYSTEM32="$WINEPREFIX/drive_c/windows/system32"

# x86 DLLs → syswow64 (for any 32-bit components wine loads via WoW64)
extract_vc_redist \
    "https://aka.ms/vs/17/release/vc_redist.x86.exe" \
    "$SYSWOW64" \
    "vc_redist.x86" \
    "x86"

# x64 DLLs → system32 (LoxoneConfig.exe is AMD64; needs 64-bit runtime DLLs)
extract_vc_redist \
    "https://aka.ms/vs/17/release/vc_redist.x64.exe" \
    "$SYSTEM32" \
    "vc_redist.x64" \
    "amd64"

echo "init-install: launching installer — GUI window appears in your browser"
wine "/config/LoxoneConfigSetup.exe" 2>&1
echo "init-install: installer exited with $?"
exit 0
