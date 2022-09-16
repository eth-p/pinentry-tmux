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
	unset TMUX_TMPDIR
	unset TMUX

	# Call the real pinentry.
	"${PINENTRY_TMUX_PINENTRY}" --ttyname="${popup_tty}"
	result=$?

	rm "${PINENTRY_TMUX_STDOUT}"
	exit $result
fi

# -----------------------------------------------------------------------------
# pinentry-tmux
# -----------------------------------------------------------------------------

# Get the correct pinentry program
set -euo pipefail
while read -r pinentry_program; do
	if [[ "$pinentry_program" = "$0" ]]; then
		continue
	fi

	break
done < <(which -a pinentry)

# If TMUX is not running, then call the pinentry program directly.
if [[ -z "${TMUX:-}" ]] && ! tmux display-message -p '' &>/dev/null; then
	"$pinentry_program"
	exit $?
fi

# Make a FIFO to communicate with the popup.
tempdir=$(mktemp -u)
mkdir -m 700 "$tempdir"
PINENTRY_TMUX_STDOUT="$tempdir/r2t.sock"; mkfifo "$PINENTRY_TMUX_STDOUT"
PINENTRY_TMUX_STDIN="$tempdir/t2r.sock";  mkfifo "$PINENTRY_TMUX_STDIN"

# Traps and cleanup.
cleanup() {
	if [ -e "$PINENTRY_TMUX_STDOUT" ]; then rm "$PINENTRY_TMUX_STDOUT"; fi 
	if [ -e "$PINENTRY_TMUX_STDIN"  ]; then rm "$PINENTRY_TMUX_STDIN";  fi
	if [ -d "$tempdir" ]; then rmdir "$tempdir"; fi

	if kill -0 "$pid_popup" &>/dev/null; then tmux display-popup -C; fi
	if kill -0 "$pid_in_sock" &>/dev/null; then kill -INT "$pid_in_sock"; fi
}

trap cleanup EXIT INT

# Create the popup.
({
	tmux display-popup -E \
		-d "$(pwd)" \
		-e "PINENTRY_TMUX_POPUP=1" \
		-e "PINENTRY_TMUX_PINENTRY=$pinentry_program" \
		-e "PINENTRY_TMUX_STDIN=$PINENTRY_TMUX_STDOUT" \
		-e "PINENTRY_TMUX_STDOUT=$PINENTRY_TMUX_STDIN" \
		-T "[ pinentry-tmux ]" \
		-s 'fg=#0066aa bg=0' \
		-S 'fg=#0066ff' \
		-b 'double' \
		"$0"
}) 0>&- &
pid_popup=$!

# Read STDIN from the socket.
cat <"$PINENTRY_TMUX_STDIN" &
pid_in_sock=$!

# Write STDOUT to the socket.
cat >"$PINENTRY_TMUX_STDOUT"

# Wait for the real pinentry to finish.
wait "$pid_in_sock"
wait "$pid_popup"

# Clean up the files.
rm "$PINENTRY_TMUX_STDOUT"
rmdir "$tempdir"

