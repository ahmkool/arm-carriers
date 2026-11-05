#!/bin/bash
# Runs Godot for level authoring. From the project root:
#   tools/level_gen/godot.sh bake <res://scene.tscn> <out.json>
#   tools/level_gen/godot.sh test <driver.gd> <res://scene.tscn> <screenshot_dir> [timeout_seconds]
# A test temporarily writes override.cfg at the project root, because autoloads are missing in --script mode.
# Keep the Godot window in front during a test: macOS can stall a covered window.
set -u
GODOT_BIN="${GODOT_BIN:-$HOME/Downloads/Godot_4_5.app/Contents/MacOS/Godot}"
SAVE_FILE="$HOME/Library/Application Support/Godot/app_userdata/Armed Together/save.json"

save_hash() {
	[ -f "$SAVE_FILE" ] && md5 -q "$SAVE_FILE"
}

bake() {
	BAKE_OUT="$2" LEVEL_SCENE="$1" perl -e 'alarm 180; exec @ARGV' "$GODOT_BIN" --path . --windowed --resolution 640x360 \
		--script "$PWD/tools/level_gen/bake_nav.gd" 2>&1 | grep -E 'BAKED|Parse Error'
	[ -s "$2" ]
}

run_test() {
	local driver scene out limit log before
	driver="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
	scene="$2"
	out="$3"
	limit="${4:-260}"
	log="$out/test.log"
	if [ -e override.cfg ]; then
		echo "override.cfg already exists; refusing to overwrite it" >&2
		exit 1
	fi
	mkdir -p "$out"
	out="$(cd "$out" && pwd)"
	log="$out/test.log"
	trap 'rm -f override.cfg' EXIT
	printf '[application]\n\nrun/flush_stdout_on_print=true\n\n[autoload]\n\nLevelTestDriver="*%s"\n' "$driver" > override.cfg
	before="$(save_hash)"
	VERIFY_OUT="$out" perl -e 'alarm shift; exec @ARGV' "$limit" "$GODOT_BIN" --path . --windowed --resolution 1280x720 "$scene" > "$log" 2>&1
	local status=$?
	rm -f override.cfg
	grep -E '^(FAIL|RESULT|INFO)|WATCHDOG|SCRIPT ERROR|Parse Error' "$log" | cut -c1-160
	echo "passes: $(grep -c '^PASS' "$log")   exit: $status   log: $log"
	[ "$before" = "$(save_hash)" ] || echo "WARNING: save.json changed during the test"
	exit "$status"
}

case "${1:-}" in
	bake) bake "$2" "$3" ;;
	test) run_test "$2" "$3" "$4" "${5:-260}" ;;
	*) sed -n 2,4p "$0"; exit 2 ;;
esac
