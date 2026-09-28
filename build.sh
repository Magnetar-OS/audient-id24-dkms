#!/usr/bin/env bash
#
# DKMS build step for snd-usb-audio with the Audient iD24 mixer map.
#
# vendor/vX.Y holds the unmodified upstream sound/usb for kernel series X.Y
# (tools/update-source.sh fetches it), and patches/vX.Y-*.patch is the patch
# for that series. This copies the source for the kernel being built, applies
# the patch and builds snd-usb-audio out of tree against the kernel's headers.
# It never touches the network: pacman runs hooks, and so DKMS, in a network
# namespace with only loopback.
#
# DKMS runs it as MAKE[0] with the kernel release and headers directory, and
# appends its own make arguments (LLVM=1 on a clang-built kernel):
#
#   build.sh <kernelver> <kernel_source_dir> [make args...]
#
# and as POST_INSTALL, to print a warning into the pacman output when the
# vendored source is older than the kernel it was built for:
#
#   build.sh --check-vendor <kernelver>
#
# A kernel from a series with no vendored source fails its build, and keeps its
# stock driver, rather than getting another series' driver.
set -euo pipefail

readonly MODULE=snd-usb-audio
readonly MODULE_DIR=sound/usb

# Kernel release to series: 7.3.0-rc2-1-cachyos-rc -> v7.3
kernel_series() {
  if [[ ! $1 =~ ^([0-9]+)\.([0-9]+)\. ]]; then
    echo "build.sh: unrecognised kernel release '$1'" >&2
    return 1
  fi
  echo "v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
}

# series_patch <root> <series>: the one patch for a vendored series.
series_patch() {
  local root=$1 series=$2
  if [[ ! -f $root/vendor/$series/TAG ]]; then
    echo "build.sh: no vendored source for kernel series $series; run tools/update-source.sh" >&2
    return 1
  fi
  local patches=("$root/patches/$series"-*.patch)
  if (( ${#patches[@]} != 1 )) || [[ ! -f ${patches[0]} ]]; then
    echo "build.sh: expected exactly one patches/$series-*.patch" >&2
    return 1
  fi
  printf '%s\n' "${patches[0]}"
}

# Kernel release to the upstream tag it is built from:
# 7.3.0-rc4-1-cachyos-rc -> v7.3-rc4, 7.3.0-1-cachyos -> v7.3,
# 7.2.8-1-cachyos -> v7.2.8
kernel_tag() {
  if [[ ! $1 =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-rc([0-9]+))? ]]; then
    echo "build.sh: unrecognised kernel release '$1'" >&2
    return 1
  fi
  local tag="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  if [[ -n ${BASH_REMATCH[5]} ]]; then
    tag+="-rc${BASH_REMATCH[5]}"
  elif (( BASH_REMATCH[3] > 0 )); then
    tag+=".${BASH_REMATCH[3]}"
  fi
  echo "$tag"
}

# Order key of a tag within its series: rcs sort before the release, and
# the release before its point releases.
tag_key() {
  [[ $1 =~ ^v[0-9]+\.[0-9]+(\.([0-9]+)|-rc([0-9]+))?$ ]] || return 1
  if [[ -n ${BASH_REMATCH[3]} ]]; then
    echo "$(( BASH_REMATCH[3] ))"
  else
    echo "$(( 1000 + ${BASH_REMATCH[2]:-0} ))"
  fi
}

# tag_is_older <a> <b>: "yes" if tag a comes before tag b in one series.
tag_is_older() {
  local a b
  a=$(tag_key "$1") && b=$(tag_key "$2") || return 1
  if (( a < b )); then echo yes; else echo no; fi
}

# vendor_lag_warning <root> <kernelver>: warn when the vendored source for
# the kernel's series is an older upstream tag than the kernel itself. The
# module then lacks the fixes upstream made in between, while replacing a
# stock module that has them. Prints nothing when the vendor is current.
vendor_lag_warning() {
  local root=$1 kernelver=$2 series vendored ktag
  series=$(kernel_series "$kernelver") || return 0
  [[ -f $root/vendor/$series/TAG ]] || return 0
  vendored=$(< "$root/vendor/$series/TAG")
  ktag=$(kernel_tag "$kernelver") || return 0
  if [[ $(tag_is_older "$vendored" "$ktag") == yes ]]; then
    echo "build.sh: warning: vendor/$series is upstream $vendored, older than kernel $kernelver; the fixes upstream made after $vendored are missing from this module. Run tools/update-source.sh $ktag and rebuild the package." >&2
  fi
}

main() {
  # DKMS runs this as POST_INSTALL, whose stderr reaches the pacman output
  # (the pacman hook discards dkms's stdout); MAKE[0]'s output only reaches
  # make.log.
  if [[ ${1-} == --check-vendor ]]; then
    local root
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    vendor_lag_warning "$root" "${2:?usage: build.sh --check-vendor <kernelver>}"
    return 0
  fi
  if (( $# < 2 )); then
    echo "usage: build.sh <kernelver> <kernel_source_dir> [make args...]" >&2
    return 2
  fi
  local kernelver=$1 ksrc=$2
  shift 2
  local root series patch_file
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  series=$(kernel_series "$kernelver")
  patch_file=$(series_patch "$root" "$series")
  vendor_lag_warning "$root" "$kernelver"

  rm -rf "$root/src"
  mkdir -p "$root/src"
  cp -r "$root/vendor/$series/." "$root/src/"
  rm "$root/src/TAG"
  echo "build.sh: $MODULE_DIR from $(< "$root/vendor/$series/TAG"), applying ${patch_file##*/}"
  # --fuzz=0: a hunk whose context has drifted fails the build instead of
  # landing wherever two lines of context still match.
  patch -d "$root/src" -p1 --forward --fuzz=0 --no-backup-if-mismatch < "$patch_file"

  # Keep upstream's object lists, with their CONFIG_ conditions, so the module
  # is linked from the same objects as the kernel's own. Drop the obj- lines:
  # they also build snd-usbmidi-lib and descend into sibling drivers that are
  # not vendored.
  local makefile="$root/src/$MODULE_DIR/Makefile"
  grep -v '^obj-' "$makefile" > "$makefile.dkms"
  printf 'obj-m := %s.o\n' "$MODULE" >> "$makefile.dkms"
  mv "$makefile.dkms" "$makefile"

  make -j"$(nproc)" -C "$ksrc" M="$root/src/$MODULE_DIR" "$@" modules
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
