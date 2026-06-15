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
echo "init-install: running winetricks fontsmooth-rgb..."
/usr/bin/winetricks -q fontsmooth-rgb 2>&1
echo "init-install: running winetricks gdiplus..."
/usr/bin/winetricks -q gdiplus 2>&1

echo "init-install: extracting MSVC DLLs from vc_redist (no Wine process needed)..."
VC_TMP=$(mktemp -d)
wget -q -O "$VC_TMP/vc_redist.x86.exe" "https://aka.ms/vs/17/release/vc_redist.x86.exe"
7z e "$VC_TMP/vc_redist.x86.exe" -o"$VC_TMP/cabs/" -y 2>/dev/null || true
mkdir -p "$VC_TMP/dlls"
for f in "$VC_TMP/cabs/"*; do
    [ -f "$f" ] && cabextract -q -d "$VC_TMP/dlls/" "$f" 2>/dev/null || true
done
SYSWOW64="$WINEPREFIX/drive_c/windows/syswow64"
mkdir -p "$SYSWOW64"
for dll in mfc140u msvcp140 vcruntime140 vcruntime140_1 ucrtbase concrt140; do
    src=$(find "$VC_TMP/dlls" -iname "${dll}.dll" | head -1)
    if [ -n "$src" ]; then
        cp "$src" "$SYSWOW64/${dll}.dll"
        echo "init-install: installed ${dll}.dll"
    else
        echo "init-install: WARNING: ${dll}.dll not found in vc_redist"
    fi
done
rm -rf "$VC_TMP"

echo "init-install: launching installer — GUI window appears in your browser"
wine "/config/LoxoneConfigSetup.exe" 2>&1
echo "init-install: installer exited with $?"
exit 0
