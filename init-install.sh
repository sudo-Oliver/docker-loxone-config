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

  # Fix relative URLs from the Loxone website
  case "$DOWNLOAD_URL" in
    http://*|https://*) ;;
    /*) DOWNLOAD_URL="https://www.loxone.com${DOWNLOAD_URL}" ;;
    ?*) DOWNLOAD_URL="https://www.loxone.com/${DOWNLOAD_URL}" ;;
  esac

  if [ -n "$DOWNLOAD_URL" ]; then
    echo "Downloading: $DOWNLOAD_URL"
    case "$DOWNLOAD_URL" in
      *.zip|*.ZIP)
        # Installer packaged as zip — extract the .exe
        wget -O /config/_setup.zip "$DOWNLOAD_URL" && \
          unzip -o /config/_setup.zip -d /config '*.exe' && \
          find /config -maxdepth 1 -name 'LoxoneConfig*.exe' | \
            head -1 | xargs -I{} mv {} /config/LoxoneConfigSetup.exe 2>/dev/null || true
        rm -f /config/_setup.zip
        ;;
      *)
        # Direct .exe download
        wget -O /config/LoxoneConfigSetup.exe "$DOWNLOAD_URL" || \
          rm -f /config/LoxoneConfigSetup.exe
        ;;
    esac
  fi

  if [ ! -f "/config/LoxoneConfigSetup.exe" ]; then
    echo ""
    echo "ERROR: auto-download failed."
    echo ""
    echo "Manual fix:"
    echo "  1. Download LoxoneConfigSetup_*.exe from:"
    echo "     https://www.loxone.com/enen/support/downloads/"
    echo "  2. Place it at:  ./config/LoxoneConfigSetup.exe"
    echo "  3. Restart the container: ./loxone.sh restart"
    echo ""
    exit 1
  fi
fi

export WINEDEBUG=err
export WINE_NEW_WOW64=1

echo "init-install: wine=$(which wine) version=$(wine --version 2>&1)"
echo "init-install: WINEARCH=$WINEARCH WINEPREFIX=$WINEPREFIX WINE_NEW_WOW64=$WINE_NEW_WOW64"

echo "init-install: running winetricks fontsmooth-rgb..."
/usr/bin/winetricks -q fontsmooth-rgb 2>&1
echo "init-install: running winetricks gdiplus..."
/usr/bin/winetricks -q gdiplus 2>&1
echo "init-install: launching Loxone Config installer (GUI appears in browser)..."
wine "/config/LoxoneConfigSetup.exe" 2>&1
WINE_EXIT=$?
echo "init-install: installer exited with $WINE_EXIT"
exit 0
