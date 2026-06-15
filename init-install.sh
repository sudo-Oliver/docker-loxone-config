#!/bin/sh
echo
echo
echo
echo
echo
echo "Installing CLEAN LoxoneConfig into ./config/wine directory"
echo
read -p "Press enter to continue" || true
echo

if [ ! -f "/config/LoxoneConfigSetup.exe" ]; then
  cd /config
  echo "Trying to auto-download Loxone Config installer..."
  DOWNLOAD_URL=$(wget -q -O - https://www.loxone.com/enen/support/downloads/ \
    | sed -r 's~(href="|src=")([^"]+).*~\n\1\2~g' \
    | awk -F"=\"" '{print $2}' \
    | grep -i 'LoxoneConfigSetup_' \
    | head -1) || true

  if [ -n "$DOWNLOAD_URL" ]; then
    wget -O i.zip "$DOWNLOAD_URL" && unzip i.zip && rm -f i.zip || true
  fi

  if [ ! -f "/config/LoxoneConfigSetup.exe" ]; then
    echo ""
    echo "ERROR: auto-download failed or LoxoneConfigSetup.exe not found."
    echo ""
    echo "Manual fix: download LoxoneConfigSetup_*.exe from https://www.loxone.com/enen/support/downloads/"
    echo "and place it at: ./config/LoxoneConfigSetup.exe"
    echo ""
    exit 1
  fi
fi

export WINEDEBUG=-all

echo Installing winetricks helper for fonts and sharper rendering..
/usr/bin/winetricks fontsmooth-rgb
#/usr/bin/winetricks corefonts
/usr/bin/winetricks gdiplus
echo Installing LoxoneConfig..
wine "/config/LoxoneConfigSetup.exe"
echo Install finished. yay!
exit 0
