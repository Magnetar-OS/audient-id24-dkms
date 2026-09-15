# audient-id24-dkms

Linux fixes for the Audient iD24 USB interface (`2708:000d`): a
`snd-usb-audio` mixer map built by DKMS for every installed kernel, and a UCM
profile that splits its 16-out/12-in stream into named devices.

## Kernel: mixer map

An `audient_id24_map` in `sound/usb/mixer_maps.c` that:

- renames `Speaker Playback Volume` (feature unit 12) to `Monitor Mix Playback
  Volume`, so PipeWire stops adopting it as the stream master. That control
  attenuates channels asymmetrically below 0 dB.
- removes the sixteen `ADAT-8 Volume` controls from the malformed mixer unit
  60. `alsactl` was rewriting all 96 cells to -127 dB at every boot.
- removes the placeholder 0..1 `Input Gain Control` (feature unit 11), and
  with it the `cannot get min/max values for control 11` dmesg spam.

Upstream added the rename by itself in 7.3-rc2 (c53f5bfc3700, "ALSA:
usb-audio: Add mixer map quirk for Audient iD24"), so the 7.3 patch only adds
the two removals on top of upstream's map, while the 7.2 patch adds the whole
map. The full analysis is the commit message at the top of each patch.

## UCM profile

`ucm2/USB-Audio/Audient/Audient-iD24-{,HiFi-}000d.conf`. Instead of one
16-channel "Multichannel" sink, PipeWire shows:

- sinks: Analogue Output 1-2 (default), 3-4, 5-6, Loop-back
- sources: Mic/Line Input 1, Mic/Line Input 2 (mono), Loop-back (stereo)
- profile "Direct": the raw 16 out / 12 in, for DAWs

The HiFi verb resets the monitor-mix control to 127 on all channels, under
either of its names. `ucm2/USB-Audio/conf.d/2708-000d.conf` selects the
profile without editing the pacman-owned `USB-Audio.conf`.

Tested on an iD24 (bcdDevice 1.12) with PipeWire 1.6.8 on kernel 7.3-rc1;
alsa-tests `ucm-validator2` passes.

## How the build works

Kernel headers do not include driver sources, and pacman runs hooks, DKMS
included, in a network namespace with only loopback. So the repository carries
the source:

- `vendor/vX.Y/sound/usb/` is upstream's unmodified `sound/usb` for kernel
  series X.Y, at the tag named in `vendor/vX.Y/TAG`. Only the directory's own
  files; its subdirectories are other drivers.
- `patches/vX.Y-*.patch` is the patch for that series.
- `build.sh` copies the series matching the kernel DKMS is building, applies
  its patch and builds `snd-usb-audio` from upstream's own object list against
  the installed headers, offline.

| Series | Vendored tag | Patch                                            |
|--------|--------------|--------------------------------------------------|
| v7.2   | `v7.2.6`     | `v7.2-audient-id24-mixer-map.patch`              |
| v7.3   | `v7.3-rc3`   | `v7.3-audient-id24-ignore-broken-controls.patch` |

- The module replaces `snd-usb-audio` for every USB audio device on the
  machine. Apart from the iD24 map it is upstream's driver at the vendored tag.
- Every kernel in a series runs the vendored driver version, not necessarily
  its own point release's.
- A kernel from a series with no `vendor/` directory fails its DKMS build in
  the pacman output and keeps its stock driver until the series is added.
- The module installs to `updates/dkms`, which depmod prefers over the stock
  module; the kernel package's own file is left alone.

## Install

Needs the headers package for each kernel, e.g. `linux-cachyos-headers`.

```sh
git clone https://github.com/Magnetar-OS/audient-id24-dkms
cd audient-id24-dkms/packaging/arch
makepkg -si
```

The UCM profile applies the next time PipeWire starts. The running kernel
keeps the `snd-usb-audio` it loaded at boot, so either reboot or reload it:

```sh
systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber
sudo modprobe -r snd_usb_audio && sudo modprobe snd_usb_audio
systemctl --user start pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber
```

## Update

Kernel updates within a vendored series rebuild the module automatically.

For a new kernel series, or an upstream change to the driver:

```sh
tools/update-source.sh v7.4-rc1   # fetches vendor/v7.4, dry-runs patches/v7.4-*.patch
# no patches/v7.4-*.patch yet? copy the newest one and fix it against vendor/v7.4
bash tests/test-build-plan.sh
git add vendor patches && git commit && git push
cd packaging/arch && makepkg -si
```

## Verify

```sh
dkms status audient-id24
modinfo -n snd_usb_audio                           # .../updates/dkms/snd-usb-audio.ko*
amixer -c iD24 controls | grep -E 'Monitor Mix|ADAT-8|Input Gain'
```

With the patched module loaded, only `Monitor Mix Playback Volume` matches.

## Remove

```sh
sudo pacman -R audient-id24-dkms-git
```

## Development

```sh
bash tests/test-build-plan.sh                                  # offline, includes patch dry-runs
./build.sh "$(uname -r)" "/usr/lib/modules/$(uname -r)/build"  # real build into src/, no install
```

Validate UCM edits with alsa-tests:
`cd alsa-tests/python/ucm-validator2 && make configs ALSA_UCM_DIR=<alsa-ucm-conf>/ucm2`.

## Upstream

Nothing from this repository is submitted yet.

- Kernel: the rename is upstream since 7.3-rc2.
  `patches/v7.3-audient-id24-ignore-broken-controls.patch` is the remaining
  change, written on top of it, and ready for `git send-email
  --to=linux-sound@vger.kernel.org --cc=tiwai@suse.de --cc=perex@perex.cz`
  once it has a Signed-off-by.
- UCM: a pull request to alsa-project/alsa-ucm-conf adds the two files and the
  line `Macro.id24-000d.StringMatch "Id='2708:000d'
  Profile='Audient/Audient-iD24-000d'"` to `USB-Audio.conf`. Once that ships,
  this package's `conf.d` hook and profile files should go.

## License

The kernel patches, vendored kernel source, `build.sh`, tools and packaging are
GPL-2.0-only (`LICENSES/GPL-2.0-only.txt`). The UCM profile is BSD-3-Clause
(`LICENSES/BSD-3-Clause.txt`), as alsa-ucm-conf is.
