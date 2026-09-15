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
usb-audio: Add mixer map quirk for Audient iD24"), so there are two patches:

| Patch                                                    | Kernels            | Adds                                      |
|----------------------------------------------------------|--------------------|-------------------------------------------|
| `patches/v7.2-audient-id24-mixer-map.patch`              | 7.2.x              | the whole map                             |
| `patches/v7.3-audient-id24-ignore-broken-controls.patch` | 7.3-rc2 and later  | the two removals, on top of upstream's map |

7.3-rc1 has neither upstream's map nor a patch here. The full analysis is the
commit message at the top of each patch.

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

Kernel headers do not include driver sources. `build.sh` downloads every file
in `sound/usb` (not its subdirectories) for the exact kernel DKMS is building,
from git.kernel.org (`7.3.0-rc2-1-cachyos-rc` → `v7.3-rc2`, `7.2.5-1-cachyos`
→ `v7.2.5`). It applies the patch and builds `snd-usb-audio` from upstream's
own object list against the installed headers.

- `patches/vX.Y-*.patch` applies from kernel series X.Y on, and the newest one
  not newer than the kernel is used.
- The module replaces `snd-usb-audio` for every USB audio device on the
  machine. For anything other than the iD24 it is the kernel's own driver.
- The sources are vanilla upstream tags, not the distribution's kernel tree.
- A kernel install needs network access.
- If the download fails or the patch stops applying, the DKMS build fails in
  the pacman output and that kernel keeps its stock driver. Add a patch for
  the new series under `patches/` and reinstall.

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

Kernel updates rebuild the module automatically. To pick up changes to this
repository, run `makepkg -si` again in `packaging/arch`.

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
bash tests/test-build-plan.sh                                  # offline
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

The kernel patch, `build.sh` and packaging are GPL-2.0-only
(`LICENSES/GPL-2.0-only.txt`). The UCM profile is BSD-3-Clause
(`LICENSES/BSD-3-Clause.txt`), as alsa-ucm-conf is.
