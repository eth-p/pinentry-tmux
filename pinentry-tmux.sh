#!/usr/bin/env bash
# Function that kills all children of a process, except the process itself.
# Works with both BSD and GNU coreutils.
rkill() {
	ps -A -o pid= -o ppid= \
	| awk -v parent="$1" '$2 == parent { print $1 }' \
	| xargs kill -INT \
	|| true
}

# Resolve the path of this script, so that it can be compared with the
# candidates found in the PATH (symlinks included) and run in the popup.
self="$(realpath "$0")"

# If a pinentry program has not already been specified via the 
# PINENTRY_TMUX_PROGRAM environment variable, look within the path for an
# executable named "pinentry". Candidates that resolve to this script are
# skipped to prevent infinite recursion.
if [ -z "${PINENTRY_TMUX_PROGRAM:-}" ]; then
	while read -r pinentry_program; do
		if [[ ! -x "$pinentry_program" || "$(realpath "$pinentry_program")" = "$self" ]]; then
			continue
		fi

		PINENTRY_TMUX_PROGRAM="$pinentry_program"
		break
	done < <(which -a pinentry)
fi

if [ -z "${PINENTRY_TMUX_PROGRAM:-}" ]; then
	echo "pinentry-tmux: no pinentry program found" 1>&2
	exit 1
fi

# -----------------------------------------------------------------------------
# If called from within the popup, run the real pinentry program and
# forward its input and output to the caller pinentry-tmux script.
# -----------------------------------------------------------------------------
if [[ -n "${PINENTRY_TMUX_CALLER:-}" ]]; then
	popup_tty="$(tty)"

	# Tell the caller that the popup has started.
	: > "${PINENTRY_TMUX_STDIN%/*}/started"

	# Redirect STDIN and STDOUT.
	exec 1>"${PINENTRY_TMUX_STDOUT}" 0<"${PINENTRY_TMUX_STDIN}"
	unset PINENTRY_TMUX_POPUP
	unset PINENTRY_TMUX_STDIN
	unset PINENTRY_TMUX_STDOUT
	unset TMUX_TMPDIR
	unset TMUX

	# Trap SIGINT to tell the original pinentry-tmux to cancel.
	trap 'rkill "$PINENTRY_TMUX_CALLER"; kill -USR1 "$PINENTRY_TMUX_CALLER"' INT

	# Call the real pinentry.
	# Force the TTY type to xterm for compatibility.
	"${PINENTRY_TMUX_PROGRAM}" \
		--ttyname="${popup_tty}" \
		--ttytype="xterm" \
		--lc-ctype="${LC_CTYPE:-c}"

	exit $?
fi

# -----------------------------------------------------------------------------
# pinentry-tmux
# -----------------------------------------------------------------------------
set -euo pipefail
pid_pinentry_tmux=$$

# If we're not running in a pane, call the original pinentry directly.
if ! tmux display-message -p "#{client_name}" &>/dev/null; then
	"$PINENTRY_TMUX_PROGRAM" "$@"
	exit $?
fi

# Make a pair of FIFOs to communicate with the popup.
fifodir=$(mktemp -d)
PINENTRY_TMUX_STDOUT="$fifodir/r2t.sock"; mkfifo "$PINENTRY_TMUX_STDOUT"
PINENTRY_TMUX_STDIN="$fifodir/t2r.sock";  mkfifo "$PINENTRY_TMUX_STDIN"
popup_started="$fifodir/started"
popup_client=()
script_args=("$@")

# Traps and cleanup.
cleanup() {
	rm -f "$PINENTRY_TMUX_STDOUT" "$PINENTRY_TMUX_STDIN" "$popup_started"
	if [ -d "$fifodir" ]; then rmdir "$fifodir"; fi

	if [ -n "${pid_popup:-}" ]   && kill -0 "$pid_popup" &>/dev/null; then tmux display-popup "${popup_client[@]}" -C; fi
	if [ -n "${pid_in_sock:-}" ] && kill -0 "$pid_in_sock" &>/dev/null; then kill -INT "$pid_in_sock"; fi
}

abort() {
	echo "ERR 83886179 Operation cancelled <Pinentry-Tmux>";
	rkill "$pid_pinentry_tmux" 2>/dev/null
	exit 1
}

trap abort USR1
trap cleanup EXIT INT

# Only forward the environment variables that the popup needs. Forwarding
# everything would expose them in the argument list of the tmux client.
popup_envs() {
	local name
	while IFS='=' read -r -d '' name value; do
		case "$name" in
			TERM|LANG|LC_*|HOME|PATH|GPG_TTY|PINENTRY_USER_DATA|PINENTRY_TMUX_PROGRAM|DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS)
				printf '%s\0' "-e" "$name=$value" ;;
		esac
	done < <(env -0)
}

# Start the popup on the tmux client attached to the given tty.
start_popup() {
	local tty="$1" client_name client_tty envs=() fallback=0

	if [[ -n "$tty" ]]; then
		while IFS=$'\t' read -r client_tty client_name; do
			if [[ "$client_tty" = "$tty" ]]; then
				popup_client=(-c "$client_name")
				break
			fi
		done < <(tmux list-clients -F $'#{client_tty}\t#{client_name}')

		if [[ "${#popup_client[@]}" -eq 0 ]]; then fallback=1; fi
	fi

	# Skip the greeting of the real pinentry and the replies to the replayed
	# options (and ttyname when falling back), because we already replied.

	{
		for ((i = 0; i <= fallback + ${#pending[@]}; i++)); do IFS='' read -r _; done
		cat
	} <"$PINENTRY_TMUX_STDIN" &
	pid_in_sock=$!

	exec 3<>"$PINENTRY_TMUX_STDOUT"
	started=1

	local option
	for option in "${pending[@]}"; do printf "%s\n" "$option" 1>&3; done

	# No tmux client owns the tty, so run the real pinentry on that tty.
	if [[ "$fallback" -eq 1 ]]; then
		"$PINENTRY_TMUX_PROGRAM" "${script_args[@]}" <"$PINENTRY_TMUX_STDOUT" >"$PINENTRY_TMUX_STDIN" &
		pid_popup=$!
		printf "OPTION ttyname=%s\n" "$tty" 1>&3
		return
	fi

	({
		while IFS='' read -r -d '' arg; do
			envs+=("$arg")
		done < <(popup_envs)

		# Determine the ideal height for a popup.
		DESIRED_WIDTH=78
		DESIRED_HEIGHT=18
		read -r ACTUAL_WIDTH ACTUAL_HEIGHT \
			< <(tmux display-message "${popup_client[@]}" -p '#{client_width} #{client_height}')

		if [[ "$ACTUAL_WIDTH" -lt "$DESIRED_WIDTH" ]]; then
			DESIRED_WIDTH="$ACTUAL_WIDTH"
		fi

		if [[ "$ACTUAL_HEIGHT" -lt "$DESIRED_HEIGHT" ]]; then
			DESIRED_HEIGHT="$ACTUAL_HEIGHT"
		fi

		tmux display-popup -E \
			"${popup_client[@]}" \
			-d "$(pwd)" \
			"${envs[@]}" \
			-e "PINENTRY_TMUX_CALLER=$pid_pinentry_tmux" \
			-e "PINENTRY_TMUX_STDIN=$PINENTRY_TMUX_STDOUT" \
			-e "PINENTRY_TMUX_STDOUT=$PINENTRY_TMUX_STDIN" \
			-T "[ pinentry-tmux ]" \
			-s 'fg=#0066aa bg=0' \
			-S 'fg=#0066ff' \
			-B \
			-w "$DESIRED_WIDTH" \
			-h "$DESIRED_HEIGHT" \
			"$self" || true

		# If the popup never ran, tell the main process to give up.
		if [ ! -e "$popup_started" ]; then
			kill -USR1 "$pid_pinentry_tmux"
		fi
	}) 0>&- &>/dev/null &
	pid_popup=$!
}

# Write STDOUT from pinentry-tmux to the socket STDIN.
# A couple options will need to be intercepted for this to work properly.
# The popup is started once the tty is known, so the correct client is used.
started=0
pending=()
printf "OK Pleased to meet you\n"
while IFS='' read -r line; do
	case "$line" in
		"OPTION ttyname="*)
			printf "OK\n"
			if [[ "$started" -eq 0 ]]; then start_popup "${line#OPTION ttyname=}"; fi
			continue ;;
		"GETINFO flavor"*) printf "D pinentry-tmux\nOK\n"; continue ;;
	esac

	if [[ "$started" -eq 0 ]]; then
		case "$line" in
			OPTION*) pending+=("$line"); printf "OK\n"; continue ;;
		esac
		start_popup ""
	fi

	printf "%s\n" "$line" 1>&3
done

# Wait for the real pinentry to finish.
if [[ "$started" -eq 1 ]]; then
	exec 3>&-
	wait "$pid_in_sock"
	wait "$pid_popup"
fi
