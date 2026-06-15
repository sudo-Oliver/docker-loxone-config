#!/bin/sh

echo "startapp: DISPLAY=$DISPLAY HOME=$HOME WINEPREFIX=$WINEPREFIX WINEARCH=$WINEARCH"

LOXONE_EXE=""
for dir in "Program Files" "Program Files (x86)"; do
  candidate="/config/wine/drive_c/${dir}/Loxone/LoxoneConfig/LoxoneConfig.exe"
  if [ -f "$candidate" ]; then
    LOXONE_EXE="$candidate"
    break
  fi
done

echo "startapp: LOXONE_EXE=$LOXONE_EXE"

if [ -z "$LOXONE_EXE" ]; then
  echo "startapp: Loxone not installed — launching installer via xterm"
  xterm -display "$DISPLAY" -e "/init-install.sh"
  XTERM_EXIT=$?
  echo "startapp: xterm exited with $XTERM_EXIT"
  if [ "$XTERM_EXIT" -ne 0 ]; then
    echo "startapp: xterm failed — running init-install.sh directly (output in docker logs)"
    /init-install.sh
  fi
  for dir in "Program Files" "Program Files (x86)"; do
    candidate="/config/wine/drive_c/${dir}/Loxone/LoxoneConfig/LoxoneConfig.exe"
    if [ -f "$candidate" ]; then
      LOXONE_EXE="$candidate"
      break
    fi
  done
fi

if [ -z "$LOXONE_EXE" ]; then
  echo "startapp: Loxone exe not found after install — check docker logs"
  exit 1
fi

echo "startapp: launching $LOXONE_EXE"
export WINEDEBUG=-all
setxkbmap $XLANG
exec wine "$LOXONE_EXE"
