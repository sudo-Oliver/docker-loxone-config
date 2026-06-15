# sudo-Oliver/docker-loxone-config

Docker container for [Loxone Config](https://www.loxone.com/dede/produkte/loxone-config/)

The Windows GUI of the Loxone Config application is run through [Wine](https://en.wikipedia.org/wiki/Wine_(software)) and accessed via a modern web browser (no installation needed on client side) or any VNC client.

350 MB RAM. Runs on anything with Docker: Mac, Linux, Raspberry Pi, NAS, home server.

---

> **Based on [lian/docker-loxone-config](https://github.com/lian/docker-loxone-config)** — the original brilliant idea of running Loxone Config via Wine + noVNC in Docker belongs entirely to [lian](https://github.com/lian). This fork adds Apple Silicon support (Rosetta 2 primary + QEMU-user fallback), a platform auto-detection setup script, security defaults, and cross-platform CI.

This container is based on the fantastic [jlesage/baseimage-gui](https://hub.docker.com/r/jlesage/baseimage-gui).

---

## Quick Start

```shell
# 1. Clone
git clone https://github.com/sudo-Oliver/docker-loxone-config
cd docker-loxone-config

# 2. Run setup (auto-detects platform, asks backend choice, configures security)
chmod +x setup.sh && ./setup.sh

# 3. Build and start (first run ~5-10 min)
docker compose up -d --build

# 4. Open in browser
# KasmVNC (recommended): http://localhost:6901
# Classic noVNC:         http://localhost:5800
```

First launch installs Wine + Loxone Config inside the container (~10-15 min). Subsequent launches skip this step.

---

## Display Backend: KasmVNC vs Classic noVNC

`setup.sh` asks which backend you want. KasmVNC is the recommended choice.

| Feature | KasmVNC (recommended) | Classic noVNC (legacy) |
|---------|----------------------|------------------------|
| Streaming | WebP/JPEG adaptive — smooth, low bandwidth | Raw VNC framebuffer — laggy on updates |
| Clipboard | Full bidirectional | Limited, unreliable |
| Resolution | Dynamic — resizes to browser window | Static, must be set before start |
| Password | Any length | Max 8 chars (RFC 6143 limit) |
| File transfer | Upload/download in browser UI | Not available |
| Port | 6901 | 5800 |
| Maturity | Modern, container-first design | Stable, widely used |

**KasmVNC manual setup** (without setup.sh):

```shell
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.kasmvnc.yml
PLATFORM=linux/amd64
DOCKERFILE=Dockerfile.kasmvnc
VNC_PASSWORD=yourpassword
VNC_RESOLUTION=1920x1080

docker compose up -d --build
# open http://localhost:6901
```

**Classic noVNC manual setup**:

```shell
# .env
COMPOSE_FILE=docker-compose.yml
PLATFORM=linux/amd64
DOCKERFILE=Dockerfile.amd64
VNC_PASSWORD=yourpass   # max 8 chars

docker compose up -d --build
# open http://localhost:5800
```

---

## Apple Silicon (M1/M2/M3/M4)

The primary image (`Dockerfile.amd64`) targets `linux/amd64` and runs via **Rosetta 2** on Apple Silicon — near-native speed, no manual configuration needed.

`setup.sh` detects Apple Silicon automatically and writes the correct `.env`.

**Docker Desktop requirement**: Enable Rosetta in Docker Desktop → Settings → General → "Use Rosetta for x86_64/amd64 emulation on Apple Silicon".

**Manual setup without setup.sh**:

```shell
# .env
PLATFORM=linux/amd64
DOCKERFILE=Dockerfile.amd64
VNC_PASSWORD=yourpassword

docker compose up -d --build
```

---

## Apple Silicon — QEMU Fallback (Rosetta-free)

> **Use this only if Rosetta 2 is unavailable.** Rosetta 2 (`Dockerfile.amd64`) is always faster — use it as long as Apple supports it.

If Rosetta 2 is deprecated or unavailable, `Dockerfile.arm64-qemu` provides a fully independent fallback:

- Native `linux/arm64` container — no Apple dependency
- `qemu-i386-static` inside the container translates i386 Wine ELF → ARM64 at runtime
- Performance: ~3-5x slower than Rosetta 2, but sufficient for Loxone Config GUI usage
- Works identically on Linux ARM64 (Raspberry Pi 64-bit, ARM servers)

**One-time host setup** (registers i386 binfmt on the host kernel — re-run after reboot):

```shell
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

`setup.sh` detects Rosetta availability and offers to run this automatically when needed.

**Manual setup for QEMU fallback:**

```shell
# .env
PLATFORM=linux/arm64
DOCKERFILE=Dockerfile.arm64-qemu
VNC_PASSWORD=yourpassword

docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
docker compose up -d --build
```

---

## Platform Matrix

| Host | Backend | Dockerfile | Platform | Speed |
|------|---------|------------|----------|-------|
| Apple Silicon + Rosetta 2 | KasmVNC | Dockerfile.kasmvnc | linux/amd64 | Fast (Rosetta 2) ★ |
| Apple Silicon + Rosetta 2 | Classic | Dockerfile.amd64 | linux/amd64 | Fast (Rosetta 2) |
| Apple Silicon (no Rosetta) | KasmVNC | Dockerfile.arm64-kasmvnc | linux/arm64 | KasmVNC native / Wine QEMU |
| Apple Silicon (no Rosetta) | Classic | Dockerfile.arm64-qemu | linux/arm64 | QEMU-user fallback |
| Intel macOS / Linux amd64 | KasmVNC | Dockerfile.kasmvnc | linux/amd64 | Native ★ |
| Intel macOS / Linux amd64 | Classic | Dockerfile.amd64 | linux/amd64 | Native |
| Linux ARM64 (RPi, ARM server) | KasmVNC | Dockerfile.arm64-kasmvnc | linux/arm64 | KasmVNC native / Wine QEMU |
| Linux ARM64 (RPi, ARM server) | Classic | Dockerfile.arm64-qemu | linux/arm64 | QEMU-user |
| Legacy 32-bit x86 | Classic only | Dockerfile | linux/386 | Native |

★ = recommended combination

---

## Usage

### docker-compose.yml

The `docker-compose.yml` reads settings from `.env`. Run `./setup.sh` to generate it, or copy `.env.example`:

```shell
cp .env.example .env
# edit .env to your needs
docker compose up -d --build
```

Minimal example without setup.sh:

```yaml
services:
  loxone-config:
    image: "local/loxone-config:latest"
    container_name: loxone-config
    platform: linux/amd64
    build:
      context: .
      dockerfile: Dockerfile.amd64
    ports:
      - "5800:5800"
    environment:
      - VNC_PASSWORD=changeme
      - USER_ID=1000
      - GROUP_ID=1000
      - DISPLAY_WIDTH=1920
      - DISPLAY_HEIGHT=1080
      - HOME=/config/
      - WINEPREFIX=/config/wine
      - WINEARCH=win32
      - XLANG=de
      - KEEP_APP_RUNNING=1
    volumes:
      - "./config:/config:rw"
      - "./config/Loxone:/config/wine/drive_c/users/app/Documents/Loxone:rw"
    restart: unless-stopped
```

**NOTE**: On first launch, required fonts, libraries and Loxone Config are installed into `/config/wine`. Further launches skip this step. To start clean, delete `/config/wine`.

### Data Paths

| Container path | Description |
|----------------|-------------|
| `/config` | Persistent data: config, logs, Wine prefix |
| `/config/Loxone` | Loxone Config project files |
| `/config/wine` | Wine installation (delete for fresh install) |

**Custom paths** — set via `.env` or environment:

```
CONFIG_PATH=/mnt/user/loxone-daten
LOXONE_PATH=/mnt/user/loxone-daten/Loxone
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `USER_ID` | UID the app runs as | `1000` |
| `GROUP_ID` | GID the app runs as | `1000` |
| `TZ` | Timezone | `Etc/UTC` |
| `KEEP_APP_RUNNING` | Auto-restart on crash | `1` |
| `DISPLAY_WIDTH` | Window width (px) | `1920` |
| `DISPLAY_HEIGHT` | Window height (px) | `1080` |
| `SECURE_CONNECTION` | Enable HTTPS + SSL-VNC | `0` |
| `VNC_PASSWORD` | Web/VNC password (max 8 chars) | (unset) |
| `XLANG` | Keyboard layout | `de` |

### Ports

| Port | Description |
|------|-------------|
| 5800 | Web browser (noVNC) |
| 5900 | VNC client (optional) |

For localhost-only access: `127.0.0.1:5800:5800` instead of `5800:5800`.

### Keyboard Maps

| Map | Language |
|-----|----------|
| `us` | English (US) |
| `en` | English |
| `at` | German (Austria) |
| `ch` | German (Switzerland) |
| `de` | German (default) |
| `fr` | French |

---

## Security

**Do not expose this service to the internet or local network without authentication.**

### Option 1: VNC Password (minimum)

```
VNC_PASSWORD=yourpassword   # max 8 chars (RFC 6143)
```

### Option 2: VNC Password + HTTPS

```
VNC_PASSWORD=yourpassword
SECURE_CONNECTION=1
```

With `SECURE_CONNECTION=1`, a self-signed certificate is generated automatically in `/config/certs/`. Provide your own:

| File | Purpose |
|------|---------|
| `/config/certs/vnc-server.pem` | VNC SSL (private key + cert) |
| `/config/certs/web-privkey.pem` | HTTPS private key |
| `/config/certs/web-fullchain.pem` | HTTPS certificate chain |

### Option 3: SSH Tunnel (recommended for remote access)

Keep port 5800 bound to localhost only, access via SSH tunnel:

```shell
ssh -L 5800:localhost:5800 user@your-server
# then open: http://localhost:5800
```

No exposed ports, no certificates needed.

### Option 4: Localhost-only binding

```yaml
ports:
  - "127.0.0.1:5800:5800"
```

---

## User/Group IDs

```shell
id   # shows your uid and gid
```

Set `USER_ID` and `GROUP_ID` to match the host user owning the config volume. Avoids permission issues on mounted volumes.

---

## Accessing the GUI

```
# Browser (noVNC)
http://<HOST IP>:5800

# VNC client
<HOST IP>:5900
```

---

## Shell Access

```shell
docker exec -it loxone-config bash
```

---

## Getting Help

[Create a new issue](https://github.com/lian/docker-loxone-config/issues)

## Credits & Thanks

* **[lian](https://github.com/lian)** — original author of [docker-loxone-config](https://github.com/lian/docker-loxone-config), the idea and core implementation
* **[jlesage](https://github.com/jlesage)** — [baseimage-gui](https://hub.docker.com/r/jlesage/baseimage-gui) which makes all the noVNC/X11/GUI-in-Docker magic possible
* [t_heinrich](https://www.loxforum.com/member/1843-t_heinrich) for bug reports
* [timboettiger](https://github.com/timboettiger) for keyboard maps
