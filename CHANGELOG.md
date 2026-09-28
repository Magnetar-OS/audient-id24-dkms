# Changelog

Notable changes, in the format of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- **The replacement driver no longer lags the kernel's own.** The vendored
  `sound/usb` moves to v7.2.8 and v7.3-rc5, which bring upstream's
  `max_urb_packs` clamp before the endpoint `memcpy` (an array overrun) and
  the ready-list race fix in `endpoint.c`, plus the rc4 implicit-feedback and
  mixer-map quirks. Before this, the module DKMS built for 7.2.8 and 7.3-rc4
  was older than the stock one it replaced, for every USB audio device.

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
- Patches for kernel series 7.2, with the whole map, and 7.3, with only the
  two removals on top of the rename upstream added in 7.3-rc2.
- The build is offline, from vendored upstream `sound/usb` for 7.2 (v7.2.8)
  and 7.3 (v7.3-rc5), so it works inside pacman's network-less hooks. A kernel
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
