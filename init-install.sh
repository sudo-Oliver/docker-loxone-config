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
export WINE_NEW_WOW64=1
export WINE=/usr/local/bin/wine

echo "init-install: wine=$(which wine) version=$(wine --version 2>&1)"
echo "init-install: WINEARCH=$WINEARCH WINEPREFIX=$WINEPREFIX"
echo "init-install: running winetricks fontsmooth-rgb..."
/usr/bin/winetricks -q fontsmooth-rgb 2>&1
echo "init-install: running winetricks gdiplus..."
/usr/bin/winetricks -q gdiplus 2>&1
echo "init-install: running winetricks vcrun2015..."
/usr/bin/winetricks -q vcrun2015 2>&1
echo "init-install: launching installer — GUI window appears in your browser"
wine "/config/LoxoneConfigSetup.exe" 2>&1
echo "init-install: installer exited with $?"
exit 0
