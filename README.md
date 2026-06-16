# sudo-Oliver/docker-loxone-config

Docker container for [Loxone Config](https://www.loxone.com/dede/produkte/loxone-config/)

Runs the Loxone Config Windows GUI through [Wine](https://en.wikipedia.org/wiki/Wine_(software)), accessible in any browser — no client installation needed.

~400 MB RAM. Works on anything with Docker: Apple Silicon Mac, Intel Mac/Linux, Raspberry Pi, NAS, home server.

> **Based on [lian/docker-loxone-config](https://github.com/lian/docker-loxone-config)** — the original idea of running Loxone Config via Wine + noVNC in Docker belongs to [lian](https://github.com/lian). This fork adds full Apple Silicon support via FEX-Emu, a guided setup script, KasmVNC high-quality streaming, and cross-platform CI.

---

## Quick Start

**Step 1 — Download the Loxone Config installer** (before running setup):

> Go to **https://www.loxone.com/enen/support/downloads/**
> Download **Loxone Config** → Windows `.exe` installer → save to your **Downloads** folder.

**Step 2 — Run setup:**

```shell
git clone https://github.com/sudo-Oliver/docker-loxone-config
cd docker-loxone-config
chmod +x setup.sh && ./setup.sh
```

`setup.sh` detects your hardware, asks a few plain-language questions (password, port, keyboard layout), finds the installer automatically, and offers to build and start right away.

**Step 3 — Start and open:**

```shell
./loxone.sh start
```

Then open **http://localhost:6901** in your browser.

Login with:
- **Username:** `kasm_user`
- **Password:** the password you set during setup (or `changeme` if you skipped)

**What happens on first launch:** The Loxone Config installer wizard opens in your browser. Click through it — takes about 10 minutes. After that, Loxone Config opens automatically on every start — no wizard again.

**Daily use commands:**

```shell
./loxone.sh start    # start (or resume after stop)
./loxone.sh stop     # stop
./loxone.sh restart  # restart — fixes most stuck states
./loxone.sh status   # check if running
./loxone.sh open     # open browser directly
./loxone.sh logs     # tail live logs
```

---

## Before You Start

Download the Loxone Config Windows installer from the Loxone website:

> **https://www.loxone.com/enen/support/downloads/**
>
> Look for **Loxone Config** → download the Windows `.exe` installer.
> Save it to your **Downloads** folder — `setup.sh` finds and copies it automatically.

---

## Apple Silicon (M1 / M2 / M3 / M4)

Apple Silicon is fully supported with **native ARM64 performance**. No Rosetta 2 checkbox, no QEMU, no extra setup.

`setup.sh` detects Apple Silicon automatically and configures everything correctly.

**How it works:** Loxone Config embeds Qt6WebEngine (Chromium). Chromium installs a signal handler that checks AVX CPU-register state. Rosetta 2 delegates AVX state to the hardware kernel, which populates signal frames incorrectly under Docker — causing a hard crash. [FEX-Emu](https://fex-emu.com/) manages the entire x86-64 CPU state in software, including AVX xsave headers, so the crash never occurs.

| Layer | What runs |
|-------|-----------|
| Apple Silicon Mac | ARM64 hardware |
| Docker Desktop | Native ARM64 Linux VM |
| Container | `linux/arm64` (native — no Rosetta, no QEMU) |
| FEX-Emu | JIT x86-64 → ARM64 translator (handles AVX correctly) |
| Wine 11 (WineHQ stable) | x86-64 userspace inside FEX |
| KasmVNC | ARM64 native display server |
| LoxoneConfig.exe | Windows AMD64 app |

**Manual setup without setup.sh (Apple Silicon):**

```shell
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.kasmvnc.yml
PLATFORM=linux/arm64
DOCKERFILE=Dockerfile.arm64-fex
VNC_PASSWORD=yourpassword

docker compose up -d --build
# open http://localhost:6901  (username: kasm_user)
```

---

## Intel Mac / Linux x86-64

Runs natively — no translation layer needed.

**Manual setup without setup.sh (Intel/AMD64):**

```shell
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.kasmvnc.yml
PLATFORM=linux/amd64
DOCKERFILE=Dockerfile.kasmvnc
VNC_PASSWORD=yourpassword

docker compose up -d --build
# open http://localhost:6901  (username: kasm_user)
```

---

## Linux ARM64 (Raspberry Pi, ARM server)

Same FEX-Emu stack as Apple Silicon — `Dockerfile.arm64-fex`.

```shell
# .env
COMPOSE_FILE=docker-compose.yml:docker-compose.kasmvnc.yml
PLATFORM=linux/arm64
DOCKERFILE=Dockerfile.arm64-fex
VNC_PASSWORD=yourpassword

docker compose up -d --build
```

---

## Platform Matrix

| Host | Display | Dockerfile | Platform | Translation |
|------|---------|------------|----------|-------------|
| Apple Silicon (M1/M2/M3/M4) | KasmVNC ★ | `Dockerfile.arm64-fex` | `linux/arm64` | FEX-Emu JIT |
| Intel Mac / Linux amd64 | KasmVNC ★ | `Dockerfile.kasmvnc` | `linux/amd64` | Native |
| Intel Mac / Linux amd64 | Classic | `Dockerfile.amd64` | `linux/amd64` | Native |
| Linux ARM64 (RPi, ARM server) | KasmVNC ★ | `Dockerfile.arm64-fex` | `linux/arm64` | FEX-Emu JIT |
| Legacy 32-bit x86 | Classic | `Dockerfile` | `linux/386` | Native |

★ = recommended

---

## Display Backend: KasmVNC vs Classic noVNC

`setup.sh` recommends KasmVNC. Use Classic only if KasmVNC causes problems.

| Feature | KasmVNC (recommended) | Classic noVNC (legacy) |
|---------|----------------------|------------------------|
| Streaming | WebP/JPEG adaptive — smooth, low bandwidth | Raw VNC — laggy on updates |
| Clipboard | Full bidirectional | Limited, unreliable |
| Resolution | Dynamic (resizes to browser window) | Fixed, set before start |
| Password | Any length | Max 8 chars (RFC 6143) |
| File transfer | Upload/download in browser | Not available |
| Port | 6901 | 5800 |

---

## What setup.sh Does

1. **Detects hardware** — Apple Silicon, Intel, ARM, 32-bit; no manual choice needed
2. **Display quality** — recommends KasmVNC with plain explanation; Classic as fallback
3. **Password** — explains network exposure; enforces minimum length
4. **Data folder** — where Loxone projects are stored (survives container updates)
5. **Installer** — finds `LoxoneConfigSetup.exe` in Downloads automatically
6. **Port** — default `6901` (KasmVNC) or `5800` (Classic); change if occupied
7. **Keyboard layout** — so keys work correctly inside Loxone Config
8. Writes `.env`, generates `loxone.sh`, offers to build immediately

---

## Data Paths

| Container path | Description |
|----------------|-------------|
| `/config` | Persistent data: Wine prefix, logs, installer |
| `/config/Loxone` | Loxone Config project files |
| `/config/wine` | Wine prefix (delete for clean reinstall) |
| `/config/LoxoneConfigSetup.exe` | Installer — place here before first start |

**Custom paths** — set via `.env`:

```
CONFIG_PATH=/mnt/nas/loxone-data
LOXONE_PATH=/mnt/nas/loxone-data/Loxone
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `USER_ID` | UID the app runs as | `1000` |
| `GROUP_ID` | GID the app runs as | `1000` |
| `TZ` | Timezone | `Etc/UTC` |
| `KEEP_APP_RUNNING` | Auto-restart on crash | `1` |
| `DISPLAY_WIDTH` | Window width (px) | `1920` |
| `DISPLAY_HEIGHT` | Window height (px) | `1080` |
| `VNC_PASSWORD` | Web/VNC password | (unset) |
| `XLANG` | Keyboard layout (`de`, `at`, `ch`, `us`, `en`, `fr`) | `de` |
| `QTWEBENGINE_CHROMIUM_FLAGS` | Chromium flags (passed to Loxone's embedded browser) | `--no-sandbox` |

---

## Ports

| Port | Description |
|------|-------------|
| 6901 | KasmVNC web browser |
| 5901 | KasmVNC raw VNC client |
| 5800 | Classic noVNC (if using Classic backend) |
| 5900 | Classic VNC client |

For localhost-only access: `127.0.0.1:6901:6901` instead of `6901:6901`.

---

## Security

**Do not expose this service to the internet without authentication.**

### Password (minimum)

Set `VNC_PASSWORD` in `.env`. KasmVNC accepts any length. Classic noVNC is limited to 8 characters.

```
VNC_PASSWORD=yourpassword
```

KasmVNC login: username `kasm_user`, password as set above (default: `changeme`).

### SSH Tunnel (recommended for remote access)

Keep port bound to localhost, access via SSH:

```shell
ssh -L 6901:localhost:6901 user@your-server
# open: http://localhost:6901
```

No exposed ports, no certificates needed.

### Localhost-only binding

```yaml
ports:
  - "127.0.0.1:6901:6901"
```

---

## Reinstall / Reset

To wipe the Wine prefix and reinstall Loxone Config from scratch:

```shell
./loxone.sh stop
rm -rf ./config/wine
./loxone.sh start
```

The Loxone Config installer runs again automatically. Your project files in `./config/Loxone` are untouched.

---

## Shell Access

```shell
docker exec -it loxone-config bash
```

---

## Performance

| Metric | FEX-Emu (Apple Silicon) | Native (Intel/AMD64) |
|--------|------------------------|----------------------|
| RAM | ~400 MB | ~350 MB |
| Startup | seconds (after first build) | seconds |
| JIT speed | ~50-70% native x86 speed | 100% |
| vs Windows VM | 20-50x less RAM; seconds vs minutes startup | — |

FEX-Emu JIT speed is sufficient for Loxone Config's GUI workload (config editing, programming, firmware upload). No perceptible lag in practice.

---

## Troubleshooting

**App won't start / install fails:**

```shell
./loxone.sh logs   # look for errors
./loxone.sh restart
```

**Black screen in browser:**

```shell
./loxone.sh restart
```

**Clean reinstall (keeps project files):**

```shell
./loxone.sh stop
rm -rf ./config/wine
./loxone.sh start
```

**LoxoneConfigSetup.exe not found:**

```shell
cp ~/Downloads/LoxoneConfigSetup*.exe ./config/LoxoneConfigSetup.exe
./loxone.sh restart
```

---

## Getting Help

[Create a new issue](https://github.com/sudo-Oliver/docker-loxone-config/issues)

---

## Credits

- **[lian](https://github.com/lian)** — original [docker-loxone-config](https://github.com/lian/docker-loxone-config), the core idea and implementation
- **[FEX-Emu](https://fex-emu.com/)** — x86-64 JIT translator enabling Apple Silicon support without Rosetta 2
- **[KasmTech](https://www.kasmweb.com/)** — [KasmVNC](https://github.com/kasmtech/KasmVNC) high-quality browser VNC
- **[WineHQ](https://www.winehq.org/)** — Wine compatibility layer
- [timboettiger](https://github.com/timboettiger) for keyboard maps
