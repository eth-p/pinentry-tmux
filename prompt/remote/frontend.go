package remote

import (
	"net"

	"github.com/keegancsmith/rpc"

	"github.com/eth-p/pinentry-tmux/prompt"
)

// Serve listens for remote procedure calls from the backend and uses the provided Prompt instance to fulfill them.
func Serve(conn net.Conn, prompt prompt.Prompt) error {
	server := rpc.NewServer()
	if err := server.RegisterName("Prompt", prompt); err != nil {
		panic(err)
	}

	server.ServeConn(conn)
	return nil
}
