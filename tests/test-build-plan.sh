#!/usr/bin/env bash
#
# Offline checks: kernel release and tag to series mapping, patch selection,
# and that every vendored series has a patch that applies to its source with
# no fuzz, as build.sh requires.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..

root=$(cd "$(dirname "$0")/.." && pwd)
# update-source.sh sources build.sh as well.
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

expect v7.3-rc4 kernel_tag 7.3.0-rc4-1-cachyos-rc
expect v7.3     kernel_tag 7.3.0-1-cachyos
expect v7.2.8   kernel_tag 7.2.8-1-cachyos
expect "<error>" kernel_tag not-a-kernel

expect yes tag_is_older v7.3-rc3 v7.3-rc4
expect yes tag_is_older v7.3-rc5 v7.3
expect yes tag_is_older v7.3     v7.3.1
expect yes tag_is_older v7.2.6   v7.2.8
expect no  tag_is_older v7.3-rc5 v7.3-rc4
expect no  tag_is_older v7.3-rc5 v7.3-rc5
expect no  tag_is_older v7.2.8   v7.2.8

# A fixture series whose vendored tag is v7.3-rc3: kernels past it warn,
# kernels at or before it do not.
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/vendor/v7.3"
echo v7.3-rc3 > "$fixture/vendor/v7.3/TAG"
warning="build.sh: warning: vendor/v7.3 is upstream v7.3-rc3, older than kernel 7.3.0-rc4-1-cachyos-rc; the fixes upstream made after v7.3-rc3 are missing from this module. Run tools/update-source.sh v7.3-rc4 and rebuild the package."
# The warning goes to stderr: pacman's DKMS hook discards the stdout of
# `dkms install`, and with it POST_INSTALL's.
# shellcheck disable=SC2329 # invoked through expect
lag_stderr() { { vendor_lag_warning "$@" > /dev/null; } 2>&1; }
expect "$warning" lag_stderr "$fixture" 7.3.0-rc4-1-cachyos-rc
expect ""         lag_stderr "$fixture" 7.3.0-rc3-1-cachyos-rc
expect ""         lag_stderr "$fixture" 7.3.0-rc2-1-cachyos-rc

# update-source.sh checks a refreshed series with the same one-patch rule as
# build.sh: two patches for a series fail the check.
mkdir -p "$fixture/patches"
cp "$root/patches/v7.3-"*.patch "$fixture/patches/v7.3-a.patch"
cp "$root/patches/v7.3-"*.patch "$fixture/patches/v7.3-b.patch"
if check_patch "$fixture" v7.3 > /dev/null 2>&1; then
  echo "FAIL  check_patch accepts two patches for one series"
  failed=1
else
  echo "ok    check_patch rejects two patches for one series"
fi
if check_patch "$root" v7.3 > /dev/null 2>&1; then
  echo "ok    check_patch $root v7.3"
else
  echo "FAIL  check_patch $root v7.3"
  failed=1
fi

for dir in "$root"/vendor/v*/; do
  series=$(basename "$dir")
  if patch_file=$(series_patch "$root" "$series" 2>&1) &&
     patch -d "$dir" -p1 --fuzz=0 --dry-run --silent < "$patch_file" > /dev/null; then
    echo "ok    ${patch_file##*/} applies to vendor/$series ($(< "$dir/TAG"))"
  else
    echo "FAIL  vendor/$series: $patch_file"
    failed=1
  fi
done

exit "$failed"
