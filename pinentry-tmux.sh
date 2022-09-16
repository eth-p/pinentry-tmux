#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# If called from within the popup, run the real pinentry program and
# forward its input and output to the caller pinentry-tmux script.
# -----------------------------------------------------------------------------
if [[ "${PINENTRY_TMUX_POPUP:-}" = 1 ]]; then
	popup_tty="$(tty)"
	gpg-connect-agent updatestartuptty /bye >/dev/null

	# Redirect STDIN and STDOUT.
	exec 1>"${PINENTRY_TMUX_STDOUT}" 0<"${PINENTRY_TMUX_STDIN}"
	unset PINENTRY_TMUX_POPUP
	unset PINENTRY_TMUX_STDIN
	unset PINENTRY_TMUX_STDOUT
	unset TMUX_TMPDIR
	unset TMUX

	# Trap SIGINT to return an error message.
	trap 'echo "ERR 83886179 Operation cancelled <Pinentry-Tmux>"' INT

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

# If a pinentry program has not already been specified via the 
# PINENTRY_TMUX_PROGRAM environment variable, look within the path for any
# executable named "pinentry".
if [ -z "${PINENTRY_TMUX_PROGRAM:-}" ]; then
	while read -r pinentry_program; do
		if [[ "$pinentry_program" = "$0" || ! -x "$pinentry_program" ]]; then
			continue
		fi

		PINENTRY_TMUX_PROGRAM="$pinentry_program"
		break
	done < <(which -a pinentry)
fi

# If TMUX is not running, then call the pinentry program directly.
if ! tmux display-message -p '' &>/dev/null; then
	"$PINENTRY_TMUX_PROGRAM" "$@"
	exit $?
fi

# Make a FIFO to communicate with the popup.
fifodir=$(mktemp -u)
mkdir -m 700 "$fifodir"
PINENTRY_TMUX_STDOUT="$fifodir/r2t.sock"; mkfifo "$PINENTRY_TMUX_STDOUT"
PINENTRY_TMUX_STDIN="$fifodir/t2r.sock";  mkfifo "$PINENTRY_TMUX_STDIN"

# Traps and cleanup.
cleanup() {
	if [ -e "$PINENTRY_TMUX_STDOUT" ]; then rm "$PINENTRY_TMUX_STDOUT"; fi 
	if [ -e "$PINENTRY_TMUX_STDIN"  ]; then rm "$PINENTRY_TMUX_STDIN";  fi
	if [ -d "$fifodir" ]; then rmdir "$fifodir"; fi

	if [ -n "${pid_popup:-}" ]   && kill -0 "$pid_popup" &>/dev/null; then tmux display-popup -C; fi
	if [ -n "${pid_in_sock:-}" ] && kill -0 "$pid_in_sock" &>/dev/null; then kill -INT "$pid_in_sock"; fi
}

trap cleanup EXIT INT

# Read STDIN from the socket to pinentry-tmux STDOUT.
cat <"$PINENTRY_TMUX_STDIN" &
pid_in_sock=$!

# Create the popup.
pid_pinentry_tmux=$$
({
	# Capture all the exported environment variables.
	# These will be forwarded to the popup.
	envs=()
	while read -r envvar; do
		envs+=(-e "$envvar")
	done < <(env)

	# Create the popup.
	tmux display-popup -E \
		-d "$(pwd)" \
		"${envs[@]}" \
		-e "PINENTRY_TMUX_POPUP=1" \
		-e "PINENTRY_TMUX_PROGRAM=$PINENTRY_TMUX_PROGRAM" \
		-e "PINENTRY_TMUX_STDIN=$PINENTRY_TMUX_STDOUT" \
		-e "PINENTRY_TMUX_STDOUT=$PINENTRY_TMUX_STDIN" \
		-T "[ pinentry-tmux ]" \
		-s 'fg=#0066aa bg=0' \
		-S 'fg=#0066ff' \
		-b 'double' \
		"$0" || true

	# Kill everything except the parent process (notably, cat).
	# This prevents the script from hanging while piping data.
	kill -INT $({
		{
			if ps --version &>/dev/null; then
				ps -o pid --ppid=$$  # GNU ps
			else
				ps -o pid -g $$      # BSD ps
			fi
		} | sed '1d' | grep -Fv "$$"
	}) || true
}) 0>&- &>/dev/null &
pid_popup=$!

# Write STDOUT from pinentry-tmux to the socket STDIN.
# A couple options will need to be intercepted for this to work properly.
exec 3>"$PINENTRY_TMUX_STDOUT"
while IFS='' read -r line; do
	case "$line" in
		"OPTION ttyname="*) printf "OK\n"; continue ;;
		"GETINFO flavor"*) printf "D pinentry-tmux\nOK\n"; continue ;;
		*) printf "%s\n" "$line" 1>&3 ;;
	esac
done

# Wait for the real pinentry to finish.
wait "$pid_in_sock"
wait "$pid_popup"

