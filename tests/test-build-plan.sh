#!/usr/bin/env bash
#
# Offline checks for build.sh: kernel release to tag mapping and patch
# selection. The download and build themselves are exercised by DKMS.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR/..

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=build.sh
source "$root/build.sh"

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

expect v7.3-rc2 kernel_tag 7.3.0-rc2-1-cachyos-rc
expect v7.3     kernel_tag 7.3.0-1-cachyos
expect v7.2.5   kernel_tag 7.2.5-1-cachyos
expect v7.10.1  kernel_tag 7.10.1-arch1-1
expect "<error>" kernel_tag not-a-kernel

p=$root/patches
expect "$p/v7.2-audient-id24-mixer-map.patch" select_patch 7.2.5-1-cachyos "$p"
expect "$p/v7.3-audient-id24-ignore-broken-controls.patch" select_patch 7.3.0-rc2-1-cachyos-rc "$p"
expect "$p/v7.3-audient-id24-ignore-broken-controls.patch" select_patch 7.10.0-1-cachyos "$p"
expect "<error>" select_patch 7.1.9-1-cachyos "$p"

exit "$failed"
