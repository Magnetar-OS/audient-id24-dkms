#!/usr/bin/env bash
#
# DKMS build step for snd-usb-audio with the Audient iD24 mixer map.
#
# Kernel headers ship no driver sources, so this downloads sound/usb for the
# exact kernel being built from git.kernel.org, applies the patch written for
# that kernel series, and builds snd-usb-audio out of tree. Every kernel gets
# its own driver plus this patch and nothing else.
#
# DKMS runs it as MAKE[0] with the kernel release and headers directory, and
# appends its own make arguments (LLVM=1 on a clang-built kernel):
#
#   build.sh <kernelver> <kernel_source_dir> [make args...]
#
# Needs network access. Fails, leaving the kernel on its stock driver, when the
# download fails or no patch applies.
set -euo pipefail

readonly KERNEL_GIT=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
readonly MODULE=snd-usb-audio
readonly MODULE_DIR=sound/usb

# Kernel release to upstream tag. The stable tree carries mainline tags too.
#   7.3.0-rc2-1-cachyos-rc -> v7.3-rc2
#   7.3.0-1-cachyos        -> v7.3
#   7.2.5-1-cachyos        -> v7.2.5
kernel_tag() {
  if [[ ! $1 =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-rc[0-9]+)? ]]; then
    echo "build.sh: unrecognised kernel release '$1'" >&2
    return 1
  fi
  local series="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  if [[ -n ${BASH_REMATCH[4]} ]]; then
    echo "v$series${BASH_REMATCH[4]}"
  elif [[ ${BASH_REMATCH[3]} == 0 ]]; then
    echo "v$series"
  else
    echo "v$series.${BASH_REMATCH[3]}"
  fi
}

# patches/vX.Y-*.patch applies from kernel series X.Y on. Pick the newest one
# that is not newer than the kernel.
select_patch() {
  local kernelver=$1 dir=$2 series p v best=""
  if [[ ! $kernelver =~ ^([0-9]+\.[0-9]+)\. ]]; then
    echo "build.sh: unrecognised kernel release '$kernelver'" >&2
    return 1
  fi
  series=${BASH_REMATCH[1]}
  while IFS= read -r p; do
    v=${p##*/v}
    v=${v%%-*}
    if [[ $(printf '%s\n' "$v" "$series" | sort -V | head -n1) == "$v" ]]; then
      best=$p
    fi
  done < <(printf '%s\n' "$dir"/v*.patch | sort -V)
  if [[ -z $best || ! -e $best ]]; then
    echo "build.sh: no patch in $dir applies to kernel series $series" >&2
    return 1
  fi
  printf '%s\n' "$best"
}

# The files (not subdirectories) directly in <dir> at <tag>, from cgit's plain
# directory listing. Subdirectories are separate drivers and are not needed.
list_dir() {
  local tag=$1 dir=$2 listing
  listing=$(curl --fail --silent --show-error --location --retry 6 "$KERNEL_GIT/plain/$dir/?h=$tag")
  grep -oE "plain/$dir/[^/?']+\?h=" <<< "$listing" | sed -E 's|^plain/||; s|\?h=$||'
}

# fetch <tag> <dest> <path>...
# One transfer at a time over a reused connection: git.kernel.org answers
# concurrent requests with 503, and even sequential ones now and then, which
# curl's backed-off retries ride out.
fetch() {
  local tag=$1 dest=$2 path
  shift 2
  local args=()
  for path in "$@"; do
    mkdir -p "$dest/$(dirname "$path")"
    args+=(-o "$dest/$path" "$KERNEL_GIT/plain/$path?h=$tag")
  done
  curl --fail --silent --show-error --location --retry 6 "${args[@]}"
}

main() {
  if (( $# < 2 )); then
    echo "usage: build.sh <kernelver> <kernel_source_dir> [make args...]" >&2
    return 2
  fi
  local kernelver=$1 ksrc=$2
  shift 2
  local here tag patch_file listing
  here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  tag=$(kernel_tag "$kernelver")
  patch_file=$(select_patch "$kernelver" "$here/patches")

  rm -rf "$here/src"
  echo "build.sh: fetching $MODULE_DIR at $tag"
  listing=$(list_dir "$tag" "$MODULE_DIR")
  local sources=()
  mapfile -t sources <<< "$listing"
  if (( ${#sources[@]} == 0 )) || [[ -z ${sources[0]} ]]; then
    echo "build.sh: empty listing for $MODULE_DIR at $tag" >&2
    return 1
  fi
  fetch "$tag" "$here/src" "${sources[@]}"
  echo "build.sh: applying ${patch_file##*/}"
  patch -d "$here/src" -p1 --forward --no-backup-if-mismatch < "$patch_file"

  # Keep upstream's object lists, with their CONFIG_ conditions, so the module
  # is linked from the same objects as the kernel's own. Drop the obj- lines:
  # they also build snd-usbmidi-lib and descend into sibling drivers that were
  # not downloaded.
  local makefile="$here/src/$MODULE_DIR/Makefile"
  grep -v '^obj-' "$makefile" > "$makefile.dkms"
  printf 'obj-m := %s.o\n' "$MODULE" >> "$makefile.dkms"
  mv "$makefile.dkms" "$makefile"

  make -j"$(nproc)" -C "$ksrc" M="$here/src/$MODULE_DIR" "$@" modules
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
