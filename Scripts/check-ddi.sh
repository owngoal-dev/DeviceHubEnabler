#!/bin/sh
# Check that a Developer Disk Image's CoreDeviceUtilities still exports the
# three Swift symbols DeviceHubEnabler hooks. Run it on the Mac, with Xcode's
# nm, against the CoreDeviceUtilities binary inside the DDI; it fails naming
# the first missing symbol.
set -eu

[ "$#" -eq 1 ] && [ -f "$1" ] || {
    echo "usage: $0 /path/to/CoreDeviceUtilities" >&2
    exit 2
}

for arch in arm64 arm64e; do
    symbols=$(nm -arch "$arch" -gj "$1")
    for symbol in \
        '_$s19CoreDeviceUtilities28MediaStreamSupportedFeaturesV7currentACvgZ' \
        '_$s19CoreDeviceUtilities28MediaStreamSupportedFeaturesV8rawValueACs6UInt64V_tcfC' \
        '_$s19CoreDeviceUtilities07CurrentB0V20isCustomerRestrictedSbvg'; do
        if ! printf '%s\n' "$symbols" | grep -Fqx -- "$symbol"; then
            echo "$arch: missing $symbol" >&2
            exit 1
        fi
    done
done
echo 'DDI symbols present for arm64 and arm64e'
