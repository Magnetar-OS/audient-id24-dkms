#!/usr/bin/env bash
#
# Replace vendor/vX.Y with the unmodified upstream sound/usb at <tag>, then
# check that patches/vX.Y-*.patch still applies to it.
#
#   tools/update-source.sh v7.3-rc3
#
# Run by hand, with network access, when a new kernel series arrives or the
# upstream driver changes. Commit the result and reinstall the package. DKMS
# itself never downloads anything.
set -euo pipefail

readonly KERNEL_GIT=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
readonly SOURCE_DIR=sound/usb

# Tag to series: v7.3-rc3 -> v7.3, v7.2.5 -> v7.2, v7.3 -> v7.3
tag_series() {
  if [[ ! $1 =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+|-rc[0-9]+)?$ ]]; then
    echo "update-source.sh: '$1' is not a kernel tag like v7.3, v7.3-rc3 or v7.2.5" >&2
    return 1
  fi
  echo "v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
}

# The files (not subdirectories) directly in <dir> at <tag>, from cgit's plain
# directory listing. Subdirectories are separate drivers and are not needed.
list_dir() {
  local tag=$1 dir=$2 listing
  listing=$(curl --fail --silent --show-error --location --retry 6 "$KERNEL_GIT/plain/$dir/?h=$tag")
  grep -oE "plain/$dir/[^/?']+\?h=" <<< "$listing" | sed -E 's|^plain/||; s|\?h=$||'
}

main() {
  if (( $# != 1 )); then
    echo "usage: tools/update-source.sh <tag>" >&2
    return 2
  fi
  local tag=$1 root series staging listing path
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  series=$(tag_series "$tag")
  staging=$(mktemp -d)
  # shellcheck disable=SC2064 # expand now: $staging is local to main
  trap "rm -rf -- $(printf %q "$staging")" EXIT

  listing=$(list_dir "$tag" "$SOURCE_DIR")
  local sources=()
  mapfile -t sources <<< "$listing"
  if (( ${#sources[@]} == 0 )) || [[ -z ${sources[0]} ]]; then
    echo "update-source.sh: empty listing for $SOURCE_DIR at $tag" >&2
    return 1
  fi

  local args=()
  for path in "${sources[@]}"; do
    mkdir -p "$staging/$(dirname "$path")"
    args+=(-o "$staging/$path" "$KERNEL_GIT/plain/$path?h=$tag")
  done
  # One transfer at a time over a reused connection: git.kernel.org answers
  # concurrent requests with 503, and sequential ones now and then, which
  # curl's backed-off retries ride out.
  curl --fail --silent --show-error --location --retry 6 "${args[@]}"
  printf '%s\n' "$tag" > "$staging/TAG"

  rm -rf "$root/vendor/$series"
  mkdir -p "$root/vendor/$series"
  cp -r "$staging/." "$root/vendor/$series/"
  echo "update-source.sh: vendor/$series now holds $SOURCE_DIR at $tag (${#sources[@]} files)"

  local patches=("$root/patches/$series"-*.patch)
  if [[ ! -f ${patches[0]} ]]; then
    echo "update-source.sh: no patches/$series-*.patch yet; write one against vendor/$series" >&2
    return 1
  fi
  patch -d "$root/vendor/$series" -p1 --dry-run < "${patches[0]}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
