package main

import (
	"fmt"
	"os"
)

const TMUX_SOCKET_ENVIRON = "TMUX"
const TMUX_PINENTRY_SOCKET_ENVIRON = "TMUX_PINENTRY_SOCKET"

func main() {
	var err error
	tmuxPinentrySocket, ok := os.LookupEnv(TMUX_PINENTRY_SOCKET_ENVIRON)

	// Call the appropriate main function, depending on how the program was invoked.
	if !ok {
		err = RunAsPinentry(os.Getenv(TMUX_SOCKET_ENVIRON))
	} else {
		err = MainTUI(tmuxPinentrySocket, os.Args[1])
	}

	// Handle errors.
	if err != nil {
		fmt.Printf("Encountered an unexpected error: %s", err)
		os.Exit(1)
	}
}
