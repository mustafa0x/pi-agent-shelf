#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
package_dir=${1:-${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/npm/node_modules/pi-openai-fast-mode}
checksum=$(shasum -a 256 "$package_dir/src/index.ts" | awk '{print $1}')

case "$checksum" in
    2ce1adb17085d0fcac2467c80461440bed3d1e1950f9250d77a2e37442937396)
        echo 'Fast mode reporting is already enabled.'
        exit 0
        ;;
    c1d24a44e4ecc778ea8c1cf1d75aba72b76f4c991ecc27e269342494dc996682)
        patch --batch --forward -p1 -d "$package_dir" < "$repo_dir/Integrations/fast-mode/pi-openai-fast-mode-0.5.0.patch"
        ;;
    *)
        echo 'Unrecognized Fast extension source; refusing to patch. This patch supports pi-openai-fast-mode 0.5.0 only.' >&2
        exit 1
        ;;
esac

echo 'Fast mode reporting enabled. Run /reload in existing pi sessions.'
