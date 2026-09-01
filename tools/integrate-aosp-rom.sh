#!/usr/bin/env bash
set -euo pipefail

RODIN_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage:
  tools/integrate-aosp-rom.sh <aosp-root>
  tools/integrate-aosp-rom.sh <aosp-root> <product-makefile> <boardconfig>

Builds and verifies Rodin Essential, then stages a self-contained integration
at vendor/rodin-essential in an existing AOSP ROM source tree.

With the optional device-tree file arguments, the script also adds both exact
include lines idempotently. Paths may be absolute or relative to <aosp-root>.
With only <aosp-root>, it stages the bundle and prints the two lines.
EOF
}

if [ "$#" -ne 1 ] && [ "$#" -ne 3 ]; then
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

RODIN_PRODUCT_INCLUDE='$(call inherit-product, vendor/rodin-essential/rodin-essential.mk)'
RODIN_BOARD_INCLUDE='include vendor/rodin-essential/BoardConfigRodinEssential.mk'
RODIN_WIRED=0

resolve_tree_file() {
    local RODIN_REQUESTED="$1"
    local RODIN_RESOLVED
    case "$RODIN_REQUESTED" in
        /*) RODIN_RESOLVED="$(readlink -f "$RODIN_REQUESTED")" ;;
        *) RODIN_RESOLVED="$(readlink -f "$RODIN_AOSP_ROOT/$RODIN_REQUESTED")" ;;
    esac
    case "$RODIN_RESOLVED" in
        "$RODIN_AOSP_ROOT"/*) ;;
        *)
            echo "Device-tree file is outside the AOSP root: $RODIN_REQUESTED" >&2
            exit 1
            ;;
    esac
    [ -f "$RODIN_RESOLVED" ] || {
        echo "Device-tree file does not exist: $RODIN_RESOLVED" >&2
        exit 1
    }
    printf '%s\n' "$RODIN_RESOLVED"
}

append_include_once() {
    local RODIN_FILE="$1"
    local RODIN_LINE="$2"
    if grep -Fxq "$RODIN_LINE" "$RODIN_FILE"; then
        return 0
    fi
    printf '\n# Rodin Essential\n%s\n' "$RODIN_LINE" >>"$RODIN_FILE"
}

if [ "$#" -eq 3 ]; then
    RODIN_PRODUCT_FILE="$(resolve_tree_file "$2")"
    RODIN_BOARD_FILE="$(resolve_tree_file "$3")"
    for RODIN_DEVICE_TREE_FILE in "$RODIN_PRODUCT_FILE" "$RODIN_BOARD_FILE"; do
        [ -w "$RODIN_DEVICE_TREE_FILE" ] || {
            echo "Device-tree file is not writable: $RODIN_DEVICE_TREE_FILE" >&2
            exit 1
        }
    done
fi

"$RODIN_PROJECT_ROOT/tools/export-aosp-bundle.sh" "$RODIN_DESTINATION"

if [ "$#" -eq 3 ]; then
    append_include_once "$RODIN_PRODUCT_FILE" "$RODIN_PRODUCT_INCLUDE"
    append_include_once "$RODIN_BOARD_FILE" "$RODIN_BOARD_INCLUDE"
    RODIN_WIRED=1
fi

cat <<EOF

AOSP_INTEGRATION=PASS
STAGED_AT=$RODIN_DESTINATION
DEVICE_TREE_WIRED=$RODIN_WIRED
EOF

if [ "$RODIN_WIRED" -eq 0 ]; then
    cat <<EOF
Add this line to the Rodin product makefile:

  $RODIN_PRODUCT_INCLUDE

Add this line to device/xiaomi/rodin/BoardConfig.mk:

  $RODIN_BOARD_INCLUDE
EOF
fi

cat <<EOF
Then run the normal ROM build. For a focused validation first:

  m RodinEssential rodin_daemon rodin_ctl selinux_policy
EOF
