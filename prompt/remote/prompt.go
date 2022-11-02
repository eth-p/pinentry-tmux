package remote

import (
	"context"
	"fmt"
	"net"

	"github.com/keegancsmith/rpc"

	"github.com/eth-p/pinentry-tmux/prompt"
)

// Prompt is a pinentry-tmux prompt implementation that uses remote procedure calls to perform the
// actual prompt. This is used by the pinentry shim to prompt the user in a tmux popup window.
type Prompt struct {
	ctx    context.Context
	client *rpc.Client
}

var _ prompt.Prompt = &Prompt{}

// Password requests a password/PIN.
func (p *Prompt) Password(options prompt.PasswordOptions) ([]byte, error) {
	var reply struct {
		Password []byte
		Err      error
	}

	err := p.client.Call(p.ctx, "Prompt.Password", options, &reply)
	if err != nil {
		return nil, fmt.Errorf("rpc failed: %w", err)
	}

	return reply.Password, reply.Err
}

// Connect accepts a connection from a remote frontend and uses it to fulfill the prompt requests.
func Connect(ctx context.Context, listen net.Listener) (*Prompt, error) {
	// Listen for a connection from the frontend.
	conn, err := listen.Accept()
	if err != nil {
		return nil, fmt.Errorf("remote: accept() failed: %w", err)
	}

	// Create an RPC client from the new connection.
	client := rpc.NewClient(conn)
	return &Prompt{
		ctx:    ctx,
		client: client,
	}, nil
}
