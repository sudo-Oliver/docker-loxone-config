# Apple Silicon performance: findings and next steps

These are notes from performance testing on an Apple M4 (10 cores, 32 GB) with Colima.
Nothing in this file is implemented yet. It records what we measured and which approaches look promising.

## Why the current arm64-fex image feels slow

- **No GPU.** The Linux VM has no GPU acceleration, so Mesa llvmpipe renders OpenGL 4.5 on the CPU.
  The llvmpipe library is x86-64 code from the FEX RootFS, so FEX also has to translate the renderer.
- **Everything is emulated.** Wine, its DLLs and all Unix libraries run as x86-64 code under FEX,
  not only Loxone Config itself.
- **Streaming.** Every frame is encoded by KasmVNC, sent to the browser and decoded there.
- **Small window on Retina displays.** The desktop renders at 1920×1080 without HiDPI scaling.
- **VM resources.** A default `colima start` gives the VM only part of the Mac (for example 4 CPUs / 8 GB).

## Promising approaches

1. **More VM resources (quick win).** For example `colima start --cpu 8 --memory 16`.
2. **HiDPI.** Set Wine's `LogPixels` (144/192) and a matching KasmVNC resolution.
3. **Hangover instead of Wine-under-FEX.** [Hangover](https://github.com/AndreRH/hangover) runs Wine natively
   on ARM64 and emulates only the x86-64 application code through FEX (ARM64EC, similar to Windows' Prism).
   Packages for Debian 13 / Ubuntu exist (`hangover_11.16_debian13_trixie_arm64`).
   This should remove most of the emulation overhead. Not tested yet with Loxone Config.
4. **GPU via krunkit.** `colima start --vm-type krunkit --mount-type virtiofs` exposes a virtio-gpu device
   (`/dev/dri/renderD128`) with Venus (Vulkan → MoltenVK → Metal).
   - Needs krunkit ≥ 1.2.1. The Homebrew tap `slp/krunkit` only had 1.1.1 at the time of testing.
   - Test result: with Debian 13's Mesa 25.0, the Venus driver loads but `vkCreateInstance` fails with
     `ERROR_OUT_OF_HOST_MEMORY`. A newer Mesa is needed; that test was not finished.
   - Goal: OpenGL ≥ 4.5 through Zink on Venus, or Direct3D 11 through DXVK.

## Other open issues

- "Failed to load the Icon Library" dialog in Config 17.3 under Wine. `IconLibrary.zip` and its XML files
  are valid and the icons are extracted. The root cause is still unknown and needs a `WINEDEBUG=+file` trace.
- MCP: `initialize` and `tools/list` work. Project queries (`code_query`) timed out once a project was open
  in our test; this needs more investigation.
