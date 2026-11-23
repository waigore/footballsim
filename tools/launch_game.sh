#!/usr/bin/env bash
# Reliably launch The Manchester Derby on desktop.
# Detaches via macOS LaunchServices so agent shells cannot kill the process.
#
# Usage:
#   tools/launch_game.sh                 # launch (keep existing instance)
#   tools/launch_game.sh --restart       # quit existing, then launch
#   tools/launch_game.sh --clear-cache   # wipe userdata + .godot, reimport, launch
#   tools/launch_game.sh -- --home=ARS --away=LIV
#
# Env overrides: GODOT_APP, GODOT_BIN
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${GODOT_APP:-/Applications/Godot.app}"
GODOT_BIN="${GODOT_BIN:-}"
USERDATA="${HOME}/Library/Application Support/Godot/app_userdata/The Manchester Derby"
LOG="${TMPDIR:-/tmp}/footballsim-launch.log"
PIDFILE="${TMPDIR:-/tmp}/footballsim-launch.pid"

CLEAR=0
REIMPORT=0
RESTART=0
EXTRA=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--clear-cache) CLEAR=1; REIMPORT=1; RESTART=1; shift ;;
		--reimport) REIMPORT=1; shift ;;
		--restart) RESTART=1; shift ;;
		--) shift; EXTRA+=("$@"); break ;;
		-*)
			echo "unknown flag: $1 (pass game args after --)" >&2
			exit 2
			;;
		*) EXTRA+=("$1"); shift ;;
	esac
done

if [[ -z "$GODOT_BIN" ]]; then
	if [[ -x "${APP}/Contents/MacOS/Godot" ]]; then
		GODOT_BIN="${APP}/Contents/MacOS/Godot"
	elif command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	else
		echo "Godot not found (set GODOT_APP or GODOT_BIN)" >&2
		exit 1
	fi
fi

# True only when a process uses --path <ROOT> as an exact path token.
running_pids() {
	ps -axo pid=,command= | awk -v root="$ROOT" '
	{
		line = $0
		sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", line)
		needle = "--path " root
		i = index(line, needle)
		if (i == 0) next
		c = substr(line, i + length(needle), 1)
		if (c == "" || c == " ") print $1
	}'
}

kill_existing() {
	local pids
	pids="$(running_pids || true)"
	[[ -z "$pids" ]] && return 0
	echo "stopping: $pids"
	# shellcheck disable=SC2086
	kill $pids 2>/dev/null || true
	sleep 1
	pids="$(running_pids || true)"
	if [[ -n "$pids" ]]; then
		# shellcheck disable=SC2086
		kill -9 $pids 2>/dev/null || true
		sleep 0.3
	fi
}

if [[ "$CLEAR" -eq 1 ]]; then
	echo "clearing userdata + .godot"
	rm -rf "$USERDATA" "$ROOT/.godot"
fi

if [[ "$RESTART" -eq 1 ]]; then
	kill_existing
fi

if [[ "$REIMPORT" -eq 1 || ! -f "$ROOT/.godot/global_script_class_cache.cfg" ]]; then
	echo "importing project cache…"
	"$GODOT_BIN" --path "$ROOT" --import --headless >"$LOG" 2>&1 || {
		echo "import failed — see $LOG" >&2
		tail -40 "$LOG" >&2 || true
		exit 1
	}
fi

: >"$LOG"
if [[ -d "$APP" ]]; then
	# LaunchServices detach — required; bare `godot &` dies with the agent shell.
	if [[ ${#EXTRA[@]} -gt 0 ]]; then
		open -na "$APP" --args --path "$ROOT" -- "${EXTRA[@]}"
	else
		open -na "$APP" --args --path "$ROOT"
	fi
else
	# Non-macOS / no .app: nohup + disown still beats a raw background job.
	if [[ ${#EXTRA[@]} -gt 0 ]]; then
		nohup "$GODOT_BIN" --path "$ROOT" -- "${EXTRA[@]}" >>"$LOG" 2>&1 &
	else
		nohup "$GODOT_BIN" --path "$ROOT" >>"$LOG" 2>&1 &
	fi
	disown || true
fi

# Confirm it stayed up (agent-shell background jobs fail this check).
alive=""
for _ in 1 2 3 4 5 6 7 8; do
	sleep 1
	alive="$(running_pids || true)"
	[[ -n "$alive" ]] && break
done

if [[ -z "$alive" ]]; then
	echo "launch failed — process exited" >&2
	[[ -s "$LOG" ]] && tail -40 "$LOG" >&2
	exit 1
fi

pid="$(echo "$alive" | head -1)"
echo "$pid" >"$PIDFILE"
echo "running pid=$pid"
echo "log=$LOG"
exit 0
