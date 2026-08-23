#!/usr/bin/env bash
set -euo pipefail

RODIN_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: tools/integrate-aosp-rom.sh <aosp-root>

Builds and verifies Rodin Essential, then stages a self-contained integration
at vendor/rodin-essential in an existing AOSP ROM source tree.

The script never edits device or product makefiles. After it succeeds, add the
two include lines printed at the end and rebuild the ROM.
EOF
}

if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
fi

RODIN_AOSP_ROOT="$(readlink -f "$1")"
RODIN_DESTINATION="$RODIN_AOSP_ROOT/vendor/rodin-essential"

[ -f "$RODIN_AOSP_ROOT/build/make/core/envsetup.mk" ] || {
    echo "Not an AOSP source root: $RODIN_AOSP_ROOT" >&2
    exit 1
}

if [ -e "$RODIN_DESTINATION" ]; then
    echo "Destination already exists: $RODIN_DESTINATION" >&2
    echo "Remove or archive it explicitly before staging a replacement." >&2
    exit 1
fi

"$RODIN_PROJECT_ROOT/tools/export-aosp-bundle.sh" "$RODIN_DESTINATION"

cat <<EOF

AOSP_INTEGRATION=PASS

Add this line to the Rodin product makefile:

  \$(call inherit-product, vendor/rodin-essential/rodin-essential.mk)

Add this line to device/xiaomi/rodin/BoardConfig.mk:

  include vendor/rodin-essential/BoardConfigRodinEssential.mk

Then run the normal ROM build. For a focused validation first:

  m RodinEssential rodin_daemon rodin_ctl selinux_policy
EOF
