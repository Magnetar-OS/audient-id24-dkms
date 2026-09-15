# Changelog

Notable changes, in the format of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **The iD24's mixer stops fighting desktop audio, on every kernel.** DKMS
  builds `snd-usb-audio` with the iD24 mixer map for each installed kernel,
  from that kernel's own source. The monitor-mix control is no longer taken
  for the stream master, the sixteen bogus `ADAT-8 Volume` controls are gone,
  and so is the Input Gain dmesg spam.
- Patches for kernel series 7.2, with the whole map, and 7.3, with only the
  two removals on top of the rename upstream added in 7.3-rc2.
- **Named outputs and inputs instead of one 16-channel sink.** A UCM profile
  gives Analogue Output 1-2/3-4/5-6, Mic/Line Input 1 and 2, Loop-back, and a
  Direct profile with all channels for DAWs.
- Arch package `audient-id24-dkms-git`.
