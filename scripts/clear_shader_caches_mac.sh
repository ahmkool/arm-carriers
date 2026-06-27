#!/usr/bin/env bash
# Clear Godot + Metal shader caches for a cold-start VFX compile test (macOS).
# Quit the exported game and Godot editor before running.

set -euo pipefail

APP_NAME="Armed Together"
BUNDLE_ID="com.nighttrainstudio.armedtogether"
CLEAR_EDITOR_METAL=false

usage() {
	cat <<EOF
Usage: $(basename "$0") [--editor]

Deletes shader / pipeline caches for "${APP_NAME}" on macOS.

  --editor   Also clear Godot editor Metal cache (org.godotengine.godot)
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--editor)
			CLEAR_EDITOR_METAL=true
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "This script is for macOS only." >&2
	exit 1
fi

GODOT_USERDATA="$HOME/Library/Application Support/Godot/app_userdata/${APP_NAME}"
DARWIN_CACHE="$(getconf DARWIN_USER_CACHE_DIR)"
METAL_ROOT="${DARWIN_CACHE}/${BUNDLE_ID}"

TARGETS=(
	"${GODOT_USERDATA}/shader_cache"
	"${GODOT_USERDATA}/pipeline_cache"
	"${METAL_ROOT}/com.apple.metal"
	"${METAL_ROOT}/com.apple.metalfe"
)

if $CLEAR_EDITOR_METAL; then
	TARGETS+=("${DARWIN_CACHE}/org.godotengine.godot")
fi

echo "Clearing shader caches for ${APP_NAME}..."
echo "(Quit the game and editor first.)"
echo

removed=0
for path in "${TARGETS[@]}"; do
	if [[ -e "$path" ]]; then
		rm -rf "$path"
		echo "  removed: $path"
		removed=$((removed + 1))
	else
		echo "  skipped (not found): $path"
	fi
done

echo
if [[ $removed -eq 0 ]]; then
	echo "Nothing to clear — caches were already empty."
else
	echo "Done. Launch the exported .app for a true cold-start test."
fi
