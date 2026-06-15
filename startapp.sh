#!/bin/sh

# win32 prefix: Program Files/Loxone
# win64 prefix: Program Files (x86)/Loxone  (32-bit installer goes here)
LOXONE_EXE=""
for dir in "Program Files" "Program Files (x86)"; do
  candidate="/config/wine/drive_c/${dir}/Loxone/LoxoneConfig/LoxoneConfig.exe"
  if [ -f "$candidate" ]; then
    LOXONE_EXE="$candidate"
    break
  fi
done

if [ -z "$LOXONE_EXE" ]; then
  xterm -e "/init-install.sh" || exit 1
  # After install, find it again
  for dir in "Program Files" "Program Files (x86)"; do
    candidate="/config/wine/drive_c/${dir}/Loxone/LoxoneConfig/LoxoneConfig.exe"
    if [ -f "$candidate" ]; then
      LOXONE_EXE="$candidate"
      break
    fi
  done
fi

[ -z "$LOXONE_EXE" ] && exit 1

export WINEDEBUG=-all
setxkbmap $XLANG
exec wine "$LOXONE_EXE"
