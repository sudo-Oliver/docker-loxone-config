# linux/386 variant — for legacy 32-bit x86 systems only
# Alpine does not support wine32 on amd64, so 32-bit Alpine is used here
# For Apple Silicon / amd64 / arm64 use Dockerfile.amd64 instead
FROM --platform=linux/386 jlesage/baseimage-gui:alpine-3.18-v4.5

ARG XLANG=de

RUN add-pkg wine wget xterm cabextract unzip xkeyboard-config setxkbmap
RUN wget -O /usr/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && \
  chmod +x /usr/bin/winetricks

COPY init-install.sh /init-install.sh
COPY startapp.sh /startapp.sh

# Set remote resizing as default
# https://github.com/jlesage/docker-baseimage-gui/issues/112
RUN sed -i "s/resize = 'scale';/resize = 'remote';/g" /opt/noVNC/app/ui.js

# ensure script permissions
RUN chmod a+rx /startapp.sh && chmod a+rx /init-install.sh

RUN set-cont-env APP_NAME "Loxone Config"
