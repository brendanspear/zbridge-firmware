#!/bin/zsh
set -euo pipefail

zbridge_script_dir="${0:A:h}"
zbridge_build_dir="${1:-$(mktemp -d "${TMPDIR:-/tmp}/zbridge-direct.XXXXXX")}"
zbridge_pio="${ZBRIDGE_PIO:-pio}"
zbridge_upstream="https://github.com/ZuluSCSI/ZuluSCSI-firmware.git"
zbridge_commit="1e03e1e289788a8ae0f3d6df273d4eadd185ed10"

if [[ -e "$zbridge_build_dir/.git" || -n "$(find "$zbridge_build_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    print -u2 "Build directory must be empty: $zbridge_build_dir"
    exit 2
fi

git clone "$zbridge_upstream" "$zbridge_build_dir"
git -C "$zbridge_build_dir" checkout --detach "$zbridge_commit"
git -C "$zbridge_build_dir" apply --unidiff-zero "$zbridge_script_dir/patches/0001-zbridge-integration.patch"
git -C "$zbridge_build_dir" apply "$zbridge_script_dir/patches/0002-zbridge-fast-host-write.patch"
git -C "$zbridge_build_dir" apply "$zbridge_script_dir/patches/0003-zbridge-bootloader-stubs.patch"
git -C "$zbridge_build_dir" apply "$zbridge_script_dir/patches/0004-zbridge-fast-writer-flash-placement.patch"
git -C "$zbridge_build_dir" apply "$zbridge_script_dir/patches/0005-zbridge-usb-bulk-interface.patch"
git -C "$zbridge_build_dir" apply --unidiff-zero "$zbridge_script_dir/patches/0006-zbridge-usb-vendor-driver-hook.patch"
git -C "$zbridge_build_dir" apply "$zbridge_script_dir/patches/0007-zbridge-fast-host-read.patch"
git -C "$zbridge_build_dir" apply "$zbridge_script_dir/patches/0008-zbridge-boot-mode.patch"
git -C "$zbridge_build_dir" apply "$zbridge_script_dir/patches/0009-zbridge-disk-scan-stack.patch"
cp "$zbridge_script_dir/src/ZBridge.cpp" "$zbridge_build_dir/src/ZBridge.cpp"
cp "$zbridge_script_dir/src/ZBridge.h" "$zbridge_build_dir/src/ZBridge.h"
cp "$zbridge_script_dir/src/ZBridgeFastHostWrite.cpp" "$zbridge_build_dir/src/ZBridgeFastHostWrite.cpp"
cp "$zbridge_script_dir/src/ZBridgeFastHostWrite.h" "$zbridge_build_dir/src/ZBridgeFastHostWrite.h"
cp "$zbridge_script_dir/src/ZBridgeFastHostRead.cpp" "$zbridge_build_dir/src/ZBridgeFastHostRead.cpp"
cp "$zbridge_script_dir/src/ZBridgeFastHostRead.h" "$zbridge_build_dir/src/ZBridgeFastHostRead.h"
cp "$zbridge_script_dir/src/ZBridgeBootloaderStubs.cpp" "$zbridge_build_dir/ZBridgeBootloaderStubs.cpp"
cp "$zbridge_script_dir/src/tusb_config.h" "$zbridge_build_dir/src/tusb_config.h"
cp "$zbridge_script_dir/src/ZBridgeTinyUSBCDC.c" "$zbridge_build_dir/src/ZBridgeTinyUSBCDC.c"
cp "$zbridge_script_dir/src/ZBridgeTinyUSBVendor.c" "$zbridge_build_dir/src/ZBridgeTinyUSBVendor.c"

cd "$zbridge_build_dir"
"$zbridge_pio" run -e ZuluSCSI_Blaster

print "BIN: $zbridge_build_dir/.pio/build/ZuluSCSI_Blaster/firmware.bin"
print "UF2: $zbridge_build_dir/.pio/build/ZuluSCSI_Blaster/firmware.uf2"
shasum -a 256 \
    "$zbridge_build_dir/.pio/build/ZuluSCSI_Blaster/firmware.bin" \
    "$zbridge_build_dir/.pio/build/ZuluSCSI_Blaster/firmware.uf2"
