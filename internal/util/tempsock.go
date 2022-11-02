package util

import (
	"fmt"
	"net"
	"os"
	"syscall"
)

// CreateTempsock creates a temporary UNIX domain socket with 0700 permissions.
// This is intended to create one-off sockets for inter-process communication.
func CreateTempsock() (net.Listener, string, error) {
	oldmask := syscall.Umask(0077)
	defer syscall.Umask(oldmask)

	// Create temporary file to get a unique name.
	f, err := os.CreateTemp(os.TempDir(), "pinentry-tmux")
	if err != nil {
		return nil, "", fmt.Errorf("could not create temp file: %w", err)
	}

	defer func(f *os.File) {
		_ = f.Close()
		_ = os.Remove(f.Name())
	}(f)

	// Create a UNIX domain socket to communicate between the popup and the pinentry server.
	socketFile := f.Name() + ".S"
	listener, err := net.Listen("unix", socketFile)
	if err != nil {
		return nil, "", fmt.Errorf("could not bind unix socket: %w", err)
	}

	// All good.
	return listener, socketFile, nil
}
