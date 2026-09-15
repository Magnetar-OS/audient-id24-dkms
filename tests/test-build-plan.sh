#!/usr/bin/env bash
#
# Offline checks: kernel release and tag to series mapping, patch selection,
# and that every vendored series has a patch that applies to its source.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=build.sh
source "$root/build.sh"
# shellcheck source=tools/update-source.sh
source "$root/tools/update-source.sh"

failed=0
expect() {
  local want=$1 got
  shift
  got=$("$@" 2>/dev/null) || got="<error>"
  if [[ $got == "$want" ]]; then
    echo "ok    $*"
  else
    echo "FAIL  $*: expected '$want', got '$got'"
    failed=1
  fi
}

expect v7.3  kernel_series 7.3.0-rc2-1-cachyos-rc
expect v7.2  kernel_series 7.2.5-1-cachyos
expect v7.10 kernel_series 7.10.1-arch1-1
expect "<error>" kernel_series not-a-kernel

expect v7.3  tag_series v7.3-rc3
expect v7.3  tag_series v7.3
expect v7.2  tag_series v7.2.5
expect "<error>" tag_series 7.2.5
expect "<error>" tag_series v7.3-rc3-dirty

expect "$root/patches/v7.2-audient-id24-mixer-map.patch" series_patch "$root" v7.2
expect "$root/patches/v7.3-audient-id24-ignore-broken-controls.patch" series_patch "$root" v7.3
expect "<error>" series_patch "$root" v7.1

for dir in "$root"/vendor/v*/; do
  series=$(basename "$dir")
  if patch_file=$(series_patch "$root" "$series" 2>&1) &&
     patch -d "$dir" -p1 --dry-run --silent < "$patch_file" > /dev/null; then
    echo "ok    ${patch_file##*/} applies to vendor/$series ($(< "$dir/TAG"))"
  else
    echo "FAIL  vendor/$series: $patch_file"
    failed=1
  fi
done

exit "$failed"
