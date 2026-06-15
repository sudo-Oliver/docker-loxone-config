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
  exit 1
fi

echo "startapp: launching $LOXONE_EXE"
export WINEDEBUG=-all
setxkbmap "$XLANG" 2>/dev/null || true
exec wine "$LOXONE_EXE"
