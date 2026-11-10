# Changelog

Notable changes, in the format of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- **The replacement driver no longer lags the kernel's own.** The vendored
  `sound/usb` moves to v7.2.15 (7.2's last release) and v7.3.3, which bring
  upstream's `max_urb_packs` clamp before the endpoint `memcpy` (an array
  overrun), the ready-list race fix in `endpoint.c`, and the newer
  implicit-feedback, mixer-map and device quirks. Before this, the module DKMS
  built for 7.2 and 7.3 kernels was older than the stock one it replaced, for
  every USB audio device.
- **`tools/update-source.sh` can vendor a fresh rc.** It fetched every tag
  from the stable tree, which carries new rc and release tags only days after
  mainline, so vendoring one failed with a 404. Those tags now come from
  mainline, point releases from stable.

### Added

- **A kernel newer than the vendored driver is reported.** Each DKMS install
  prints a warning into the pacman output when `vendor/<series>/TAG` is an
  older upstream tag than the kernel being built, naming the tag to pass to
  `tools/update-source.sh`. Before, the build silently produced a driver
  older than the stock one it replaced.
- **The iD24's mixer stops fighting desktop audio, on every kernel.** DKMS
  builds `snd-usb-audio` with the iD24 mixer map for each installed kernel.
  The monitor-mix control is no longer taken for the stream master, the
  sixteen bogus `ADAT-8 Volume` controls are gone, and so is the Input Gain
  dmesg spam.
- **Kernel 7.4 is supported.** DKMS builds the module for 7.4 kernels from
  vendored v7.4-rc2. Before, a 7.4 kernel failed its DKMS build and kept the
  stock driver.
- Patches for kernel series 7.2, with the whole map, and 7.3 and 7.4, with
  only the two removals on top of the rename upstream added in 7.3-rc2.
- The build is offline, from vendored upstream `sound/usb` for 7.2 (v7.2.15),
  7.3 (v7.3.3) and 7.4 (v7.4-rc2), so it works inside pacman's network-less hooks. A kernel
  from a series with no vendored source fails loudly and keeps its stock
  driver.
- `tools/update-source.sh <tag>` vendors a new series or a newer upstream
  driver and checks the patch still applies.
- The module installs to `updates/dkms`. DKMS keeps the stock module file
  aside while it is installed and restores it on removal.
- **Named outputs and inputs instead of one 16-channel sink.** A UCM profile
  gives Analogue Output 1-2/3-4/5-6, Mic/Line Input 1 and 2, Loop-back, and a
  Direct profile with all channels for DAWs.
- Arch package `audient-id24-dkms-git`.
